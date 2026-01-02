"""Fortran rules"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":common.bzl", "fortran_common")
load(":providers.bzl", "FortranInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

_SRC_EXTENSIONS = [
    ".f",
    ".F",
    ".f90",
    ".F90",
    ".for",
    ".FOR",
]

def _create_instrumented_files_info(ctx):
    """Create an InstrumentedFilesInfo provider for code coverage support.

    Args:
        ctx (ctx): The rule context.

    Returns:
        InstrumentedFilesInfo: Coverage instrumentation metadata.
    """
    dep_attrs = ["deps", "data"]
    if hasattr(ctx.attr, "implementation_deps"):
        dep_attrs.append("implementation_deps")
    return coverage_common.instrumented_files_info(
        ctx,
        source_attributes = ["srcs"],
        dependency_attributes = dep_attrs,
        extensions = [ext.strip(".") for ext in _SRC_EXTENSIONS],
    )

_COMMON_ATTRS = {
    "data": attr.label_list(
        doc = "List of additional files to include in the runfiles of the target.",
        allow_files = True,
    ),
    "defines": attr.string_list(
        doc = "List of preprocessor definitions to pass to the compiler (e.g., -DDEBUG).",
    ),
    "deps": attr.label_list(
        doc = "List of dependencies. Can be C++ targets (CcInfo) or Fortran targets (CcInfo, FortranInfo).",
        providers = [
            [CcInfo],
            [FortranInfo],
        ],
    ),
    "fopts": attr.string_list(
        doc = "List of Fortran-specific compiler flags (e.g., -O2, -fopenmp).",
    ),
    "hdrs": attr.label_list(
        doc = "Header and include files for this target. Made available to dependents.",
        allow_files = True,
    ),
    "includes": attr.string_list(
        doc = "Include directories to add to the compilation search path.",
    ),
    "linkopts": attr.string_list(
        doc = "List of additional linker flags to pass to the linker.",
    ),
    "srcs": attr.label_list(
        doc = "List of Fortran source files to compile (.f, .F, .f90, .F90, .for, .FOR).",
        allow_files = _SRC_EXTENSIONS,
    ),
}

def _fortran_library_impl(ctx):
    """Implementation for fortran_library rule.

    Structured based on cc_library implementation pattern.
    """
    fortran_toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fortran_toolchain

    # Extract CcToolchainInfo from the toolchain
    cc_toolchain = fortran_common.get_cc_toolchain(fortran_toolchain)

    # Configure features for compilation
    feature_configuration = fortran_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    # Collect compilation and linking contexts from dependencies
    compilation_contexts = []
    linking_contexts = []
    fortran_deps_module_dirs = []
    for dep in ctx.attr.deps:
        if FortranInfo in dep:
            dep_fortran_info = dep[FortranInfo]
            if dep_fortran_info.mods:
                fortran_deps_module_dirs.append(dep_fortran_info.mods)
            dep_cc_info = dep_fortran_info.cc_info
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)
        elif CcInfo in dep:
            dep_cc_info = dep[CcInfo]
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)

    # Collect implementation_deps separately -- used for compilation but NOT
    # propagated to consumers via CcInfo/FortranInfo.
    impl_compilation_contexts = []
    impl_linking_contexts = []
    impl_module_dirs = []
    for dep in ctx.attr.implementation_deps:
        if FortranInfo in dep:
            dep_fortran_info = dep[FortranInfo]
            if dep_fortran_info.mods:
                impl_module_dirs.append(dep_fortran_info.mods)
            dep_cc_info = dep_fortran_info.cc_info
            impl_compilation_contexts.append(dep_cc_info.compilation_context)
            impl_linking_contexts.append(dep_cc_info.linking_context)
        elif CcInfo in dep:
            dep_cc_info = dep[CcInfo]
            impl_compilation_contexts.append(dep_cc_info.compilation_context)
            impl_linking_contexts.append(dep_cc_info.linking_context)

    # Merge compilation contexts from deps and implementation_deps for compilation
    all_compilation_contexts = compilation_contexts + impl_compilation_contexts
    merged_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = all_compilation_contexts,
    ) if all_compilation_contexts else cc_common.create_compilation_context()

    includes = list(ctx.attr.includes) if ctx.attr.includes else []

    compilation_context, compilation_outputs, module_dirs = fortran_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        fortran_toolchain = fortran_toolchain,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        public_hdrs = ctx.files.hdrs,
        includes = includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines if hasattr(ctx.attr, "local_defines") else [],
        user_compile_flags = fortran_toolchain.compile_flags,
        fortran_flags = ctx.attr.fopts,
        compilation_contexts = [merged_compilation_context],
        fortran_deps_module_dirs = depset(transitive = fortran_deps_module_dirs + impl_module_dirs) if (fortran_deps_module_dirs or impl_module_dirs) else depset(),
        name = ctx.label.name,
        create_module_file = True,
        coverage_enabled = ctx.configuration.coverage_enabled,
    )

    # For the returned CcInfo, only include deps' compilation context (not impl_deps')
    deps_only_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = compilation_contexts,
    ) if compilation_contexts else cc_common.create_compilation_context()
    final_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = [compilation_context, deps_only_compilation_context],
    )

    has_compilation_outputs = compilation_outputs.objects and len(compilation_outputs.objects.to_list()) > 0 if hasattr(compilation_outputs.objects, "to_list") else (compilation_outputs.objects and len(compilation_outputs.objects) > 0)

    linking_context = CcInfo().linking_context
    linking_outputs = struct(library_to_link = None)

    # For linking, include BOTH deps and implementation_deps
    all_linking_contexts = linking_contexts + impl_linking_contexts

    if has_compilation_outputs:
        (
            linking_context,
            linking_outputs,
        ) = fortran_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            name = ctx.label.name,
            compilation_outputs = compilation_outputs,
            cc_toolchain = cc_toolchain,
            feature_configuration = feature_configuration,
            additional_inputs = ctx.files.data,
            linking_contexts = all_linking_contexts,
            user_link_flags = ctx.attr.linkopts,
            alwayslink = ctx.attr.alwayslink,
            disallow_dynamic_library = True,
        )

    contexts_to_merge = [linking_context]
    if not has_compilation_outputs:
        if ctx.attr.linkopts:
            linker_input = fortran_common.create_linker_input(
                owner = ctx.label,
                user_link_flags = ctx.attr.linkopts,
            )
            contexts_to_merge.append(fortran_common.create_linking_context(
                linker_inputs = depset([linker_input]),
            ))
        contexts_to_merge.extend(all_linking_contexts)

    merged_linking_context = fortran_common.merge_linking_contexts(
        linking_contexts = contexts_to_merge,
    )

    # Collect files for DefaultInfo
    files_builder = []
    if linking_outputs.library_to_link != None:
        artifacts_to_build = linking_outputs.library_to_link
        if artifacts_to_build.static_library != None:
            files_builder.append(artifacts_to_build.static_library)
        if artifacts_to_build.pic_static_library != None:
            files_builder.append(artifacts_to_build.pic_static_library)

    # If no library was created, include object files
    if not files_builder and has_compilation_outputs:
        files_builder.extend(compilation_outputs.objects.to_list())

    # Collect object files for FortranInfo
    object_files = compilation_outputs.objects if has_compilation_outputs else depset()

    # Build runfiles
    runfiles_list = []
    for data_dep in ctx.attr.data:
        if data_dep[DefaultInfo].data_runfiles.files:
            runfiles_list.append(data_dep[DefaultInfo].data_runfiles)
        else:
            runfiles_list.append(ctx.runfiles(transitive_files = data_dep[DefaultInfo].files))
            runfiles_list.append(data_dep[DefaultInfo].default_runfiles)

    for src in ctx.attr.srcs:
        if DefaultInfo in src:
            runfiles_list.append(src[DefaultInfo].default_runfiles)

    for dep in ctx.attr.deps:
        if DefaultInfo in dep:
            runfiles_list.append(dep[DefaultInfo].default_runfiles)

    runfiles = ctx.runfiles().merge_all(runfiles_list)

    # Create CcInfo provider
    cc_info = CcInfo(
        compilation_context = final_compilation_context,
        linking_context = merged_linking_context,
    )

    # Create FortranInfo provider with transitive module dirs from deps
    fortran_info = FortranInfo(
        objects = object_files,
        mods = depset(transitive = [module_dirs] + fortran_deps_module_dirs),
        cc_info = cc_info,
    )

    output_groups = {}
    if has_compilation_outputs:
        output_groups["compilation_outputs"] = compilation_outputs.objects

    return [
        DefaultInfo(
            files = depset(files_builder),
            default_runfiles = runfiles,
            data_runfiles = runfiles,
        ),
        cc_info,
        fortran_info,
        _create_instrumented_files_info(ctx),
        OutputGroupInfo(**output_groups),
    ]

_LIBRARY_ATTRS = _COMMON_ATTRS | {
    "alwayslink": attr.bool(
        doc = "If True, any binary that depends (directly or indirectly) on this library will link in all object files, even if some contain no symbols referenced by the binary.",
    ),
    "implementation_deps": attr.label_list(
        doc = "Dependencies used only for compiling this library. Their modules and includes are not propagated to dependents, but they are still linked transitively.",
        providers = [
            [CcInfo],
            [FortranInfo],
        ],
    ),
    "local_defines": attr.string_list(
        doc = "List of preprocessor definitions that apply only to this target, not to its dependents.",
    ),
}

fortran_library = rule(
    doc = "Compiles Fortran source files into a static library. Libraries can export Fortran modules for use by dependent targets.",
    implementation = _fortran_library_impl,
    attrs = _LIBRARY_ATTRS | {
    },
    toolchains = [TOOLCHAIN_TYPE],
    fragments = ["cpp"],
    provides = [CcInfo, FortranInfo],
)

def _fortran_shared_library_impl(ctx):
    """Implementation for fortran_shared_library rule.

    Compiles Fortran sources and links them into a shared library.
    Similar to fortran_library but creates a dynamic library.
    """
    fortran_toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fortran_toolchain

    # Extract CcToolchainInfo from the toolchain
    cc_toolchain = fortran_common.get_cc_toolchain(fortran_toolchain)

    # Configure features for compilation
    feature_configuration = fortran_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    # Collect compilation and linking contexts from dependencies
    compilation_contexts = []
    linking_contexts = []
    fortran_deps_module_dirs = []
    for dep in ctx.attr.deps:
        if FortranInfo in dep:
            dep_fortran_info = dep[FortranInfo]
            if dep_fortran_info.mods:
                fortran_deps_module_dirs.append(dep_fortran_info.mods)
            dep_cc_info = dep_fortran_info.cc_info
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)
        elif CcInfo in dep:
            dep_cc_info = dep[CcInfo]
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)

    # Collect implementation_deps separately -- used for compilation but NOT
    # propagated to consumers via CcInfo/FortranInfo.
    impl_compilation_contexts = []
    impl_linking_contexts = []
    impl_module_dirs = []
    for dep in ctx.attr.implementation_deps:
        if FortranInfo in dep:
            dep_fortran_info = dep[FortranInfo]
            if dep_fortran_info.mods:
                impl_module_dirs.append(dep_fortran_info.mods)
            dep_cc_info = dep_fortran_info.cc_info
            impl_compilation_contexts.append(dep_cc_info.compilation_context)
            impl_linking_contexts.append(dep_cc_info.linking_context)
        elif CcInfo in dep:
            dep_cc_info = dep[CcInfo]
            impl_compilation_contexts.append(dep_cc_info.compilation_context)
            impl_linking_contexts.append(dep_cc_info.linking_context)

    # Merge compilation contexts from deps and implementation_deps for compilation
    all_compilation_contexts = compilation_contexts + impl_compilation_contexts
    merged_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = all_compilation_contexts,
    ) if all_compilation_contexts else cc_common.create_compilation_context()

    includes = list(ctx.attr.includes) if ctx.attr.includes else []

    compilation_context, compilation_outputs, module_dirs = fortran_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        fortran_toolchain = fortran_toolchain,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        public_hdrs = ctx.files.hdrs,
        includes = includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines if hasattr(ctx.attr, "local_defines") else [],
        user_compile_flags = fortran_toolchain.compile_flags,
        fortran_flags = ctx.attr.fopts,
        compilation_contexts = [merged_compilation_context],
        fortran_deps_module_dirs = depset(transitive = fortran_deps_module_dirs + impl_module_dirs) if (fortran_deps_module_dirs or impl_module_dirs) else depset(),
        name = ctx.label.name,
        create_module_file = True,
        coverage_enabled = ctx.configuration.coverage_enabled,
    )

    # For the returned CcInfo, only include deps' compilation context (not impl_deps')
    deps_only_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = compilation_contexts,
    ) if compilation_contexts else cc_common.create_compilation_context()
    final_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = [compilation_context, deps_only_compilation_context],
    )

    has_compilation_outputs = compilation_outputs.objects and len(compilation_outputs.objects.to_list()) > 0 if hasattr(compilation_outputs.objects, "to_list") else (compilation_outputs.objects and len(compilation_outputs.objects) > 0)

    linking_context = CcInfo().linking_context
    linking_outputs = struct(library_to_link = None)

    # For linking, include BOTH deps and implementation_deps
    all_linking_contexts = linking_contexts + impl_linking_contexts

    if has_compilation_outputs:
        (
            linking_context,
            linking_outputs,
        ) = fortran_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            name = ctx.label.name,
            compilation_outputs = compilation_outputs,
            cc_toolchain = cc_toolchain,
            feature_configuration = feature_configuration,
            additional_inputs = ctx.files.data,
            linking_contexts = all_linking_contexts,
            user_link_flags = ctx.attr.linkopts + fortran_toolchain.link_flags,
            alwayslink = ctx.attr.alwayslink,
            disallow_dynamic_library = False,
        )

    contexts_to_merge = [linking_context]
    if not has_compilation_outputs:
        if ctx.attr.linkopts:
            linker_input = fortran_common.create_linker_input(
                owner = ctx.label,
                user_link_flags = ctx.attr.linkopts,
            )
            contexts_to_merge.append(fortran_common.create_linking_context(
                linker_inputs = depset([linker_input]),
            ))
        contexts_to_merge.extend(all_linking_contexts)

    merged_linking_context = fortran_common.merge_linking_contexts(
        linking_contexts = contexts_to_merge,
    )

    # Collect files for DefaultInfo
    files_builder = []
    if linking_outputs.library_to_link != None:
        artifacts_to_build = linking_outputs.library_to_link
        if artifacts_to_build.static_library != None:
            files_builder.append(artifacts_to_build.static_library)
        if artifacts_to_build.pic_static_library != None:
            files_builder.append(artifacts_to_build.pic_static_library)
        if artifacts_to_build.dynamic_library != None:
            files_builder.append(artifacts_to_build.dynamic_library)
        if artifacts_to_build.interface_library != None:
            files_builder.append(artifacts_to_build.interface_library)

    # If no library was created, include object files
    if not files_builder and has_compilation_outputs:
        files_builder.extend(compilation_outputs.objects.to_list())

    # Collect object files for FortranInfo
    object_files = compilation_outputs.objects if has_compilation_outputs else depset()

    # Build runfiles
    runfiles_list = []
    for data_dep in ctx.attr.data:
        if DefaultInfo in data_dep:
            if data_dep[DefaultInfo].data_runfiles.files:
                runfiles_list.append(data_dep[DefaultInfo].data_runfiles)
            else:
                runfiles_list.append(ctx.runfiles(transitive_files = data_dep[DefaultInfo].files))
                runfiles_list.append(data_dep[DefaultInfo].default_runfiles)

    for src in ctx.attr.srcs:
        if DefaultInfo in src:
            runfiles_list.append(src[DefaultInfo].default_runfiles)

    for dep in ctx.attr.deps:
        if DefaultInfo in dep:
            runfiles_list.append(dep[DefaultInfo].default_runfiles)

    runfiles = ctx.runfiles().merge_all(runfiles_list)

    # Create CcInfo provider
    cc_info = CcInfo(
        compilation_context = final_compilation_context,
        linking_context = merged_linking_context,
    )

    # Create FortranInfo provider with transitive module dirs from deps
    fortran_info = FortranInfo(
        objects = object_files,
        mods = depset(transitive = [module_dirs] + fortran_deps_module_dirs),
        cc_info = cc_info,
    )

    output_groups = {}
    if has_compilation_outputs:
        output_groups["compilation_outputs"] = compilation_outputs.objects

    return [
        DefaultInfo(
            files = depset(files_builder),
            default_runfiles = runfiles,
            data_runfiles = runfiles,
        ),
        cc_info,
        fortran_info,
        _create_instrumented_files_info(ctx),
        OutputGroupInfo(**output_groups),
    ]

fortran_shared_library = rule(
    doc = "Compiles Fortran source files into a shared (dynamic) library. Libraries can export Fortran modules for use by dependent targets.",
    implementation = _fortran_shared_library_impl,
    attrs = _LIBRARY_ATTRS | {
    },
    toolchains = [TOOLCHAIN_TYPE],
    fragments = ["cpp"],
    provides = [CcInfo, FortranInfo],
)

_EXECUTABLE_ATTRS = _COMMON_ATTRS | {
    "env": attr.string_dict(
        mandatory = False,
        doc = """\
            Specifies additional environment variables to set when the test is executed by bazel test.
            Values are subject to `$(rootpath)`, `$(execpath)`, location, and
            ["Make variable"](https://docs.bazel.build/versions/master/be/make-variables.html) substitution.
        """,
    ),
    "linkstatic": attr.bool(
        default = True,
        doc = "If True, prefer linking deps statically. If False, prefer dynamic libraries.",
    ),
}

def _create_run_environment_info(ctx, env, env_inherit, targets):
    """Create a RunEnvironmentInfo provider with location and Make variable expansion.

    Args:
        ctx (ctx): The rule context.
        env (dict[str, str]): Environment variables to set, subject to expansion.
        env_inherit (list[str]): Environment variable names to inherit from the host.
        targets (list[Target]): Targets available for $(location) expansion.

    Returns:
        RunEnvironmentInfo: The environment provider for test/binary execution.
    """

    known_variables = {}
    for target in ctx.attr.toolchains:
        if platform_common.TemplateVariableInfo in target:
            variables = getattr(target[platform_common.TemplateVariableInfo], "variables", {})
            known_variables.update(variables)

    expanded_env = {}
    for key, value in env.items():
        expanded_env[key] = ctx.expand_make_variables(
            key,
            ctx.expand_location(value, targets),
            known_variables,
        )

    workspace_name = ctx.label.workspace_name
    if not workspace_name:
        workspace_name = ctx.workspace_name

    if not workspace_name:
        workspace_name = "_main"

    # Needed for bzlmod-aware runfiles resolution.
    expanded_env["REPOSITORY_NAME"] = workspace_name

    return RunEnvironmentInfo(
        environment = expanded_env,
        inherited_environment = env_inherit,
    )

def _fortran_binary_impl(ctx):
    """Implementation for fortran_binary rule.

    Compiles Fortran sources and links them into an executable.
    """
    fortran_toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fortran_toolchain

    # Extract CcToolchainInfo from the toolchain
    cc_toolchain = fortran_common.get_cc_toolchain(fortran_toolchain)

    # Configure features for compilation
    feature_configuration = fortran_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    # Collect compilation and linking contexts from dependencies
    compilation_contexts = []
    linking_contexts = []
    fortran_deps_module_dirs = []
    for dep in ctx.attr.deps:
        if FortranInfo in dep:
            dep_fortran_info = dep[FortranInfo]
            if dep_fortran_info.mods:
                fortran_deps_module_dirs.append(dep_fortran_info.mods)
            dep_cc_info = dep_fortran_info.cc_info
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)
        elif CcInfo in dep:
            dep_cc_info = dep[CcInfo]
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)

    merged_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = compilation_contexts,
    ) if compilation_contexts else cc_common.create_compilation_context()

    includes = list(ctx.attr.includes) if ctx.attr.includes else []

    compilation_context, compilation_outputs, module_dirs = fortran_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        fortran_toolchain = fortran_toolchain,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        public_hdrs = ctx.files.hdrs,
        includes = includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines if hasattr(ctx.attr, "local_defines") else [],
        user_compile_flags = fortran_toolchain.compile_flags,
        fortran_flags = ctx.attr.fopts,
        compilation_contexts = [merged_compilation_context],
        fortran_deps_module_dirs = depset(transitive = fortran_deps_module_dirs) if fortran_deps_module_dirs else depset(),
        name = ctx.label.name,
        create_module_file = False,
        coverage_enabled = ctx.configuration.coverage_enabled,
    )

    linking_outputs = fortran_common.link(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        fortran_toolchain = fortran_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = linking_contexts,
        user_link_flags = ctx.attr.linkopts,
        link_deps_statically = ctx.attr.linkstatic,
        output_type = "executable",
    )

    executable = linking_outputs.executable

    runfiles_list = []
    for data_dep in ctx.attr.data:
        if DefaultInfo in data_dep:
            if data_dep[DefaultInfo].data_runfiles.files:
                runfiles_list.append(data_dep[DefaultInfo].data_runfiles)
            else:
                runfiles_list.append(ctx.runfiles(transitive_files = data_dep[DefaultInfo].files))
                runfiles_list.append(data_dep[DefaultInfo].default_runfiles)

    for src in ctx.attr.srcs:
        if DefaultInfo in src:
            runfiles_list.append(src[DefaultInfo].default_runfiles)

    for dep in ctx.attr.deps:
        if DefaultInfo in dep:
            runfiles_list.append(dep[DefaultInfo].default_runfiles)

    runfiles = ctx.runfiles().merge_all(runfiles_list)

    object_files = compilation_outputs.objects if compilation_outputs.objects else depset()

    merged_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = [compilation_context, merged_compilation_context],
    )
    cc_info = CcInfo(
        compilation_context = merged_compilation_context,
        linking_context = CcInfo().linking_context,
    )

    # Create FortranInfo provider
    fortran_info = FortranInfo(
        objects = object_files,
        mods = module_dirs,
        cc_info = cc_info,
    )

    output_groups = {}
    if compilation_outputs.objects:
        output_groups["compilation_outputs"] = compilation_outputs.objects

    return [
        DefaultInfo(
            files = depset([executable]),
            runfiles = runfiles,
            executable = executable,
        ),
        _create_run_environment_info(
            ctx,
            ctx.attr.env if hasattr(ctx.attr, "env") else {},
            [],
            ctx.attr.data,
        ),
        cc_info,
        fortran_info,
        _create_instrumented_files_info(ctx),
        OutputGroupInfo(**output_groups),
    ]

fortran_binary = rule(
    doc = "Compiles Fortran source files and links them into an executable.",
    implementation = _fortran_binary_impl,
    attrs = _EXECUTABLE_ATTRS,
    toolchains = [TOOLCHAIN_TYPE],
    fragments = ["cpp"],
    provides = [CcInfo, FortranInfo],
    executable = True,
)

def _fortran_test_impl(ctx):
    """Implementation for fortran_test rule.

    Compiles Fortran sources and links them into a test executable.
    Similar to fortran_binary but with test-specific attributes.
    """
    fortran_toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fortran_toolchain

    # Extract CcToolchainInfo from the toolchain
    cc_toolchain = fortran_common.get_cc_toolchain(fortran_toolchain)

    # Configure features for compilation
    feature_configuration = fortran_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    # Collect compilation and linking contexts from dependencies
    compilation_contexts = []
    linking_contexts = []
    fortran_deps_module_dirs = []
    for dep in ctx.attr.deps:
        if FortranInfo in dep:
            dep_fortran_info = dep[FortranInfo]
            if dep_fortran_info.mods:
                fortran_deps_module_dirs.append(dep_fortran_info.mods)
            dep_cc_info = dep_fortran_info.cc_info
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)
        elif CcInfo in dep:
            dep_cc_info = dep[CcInfo]
            compilation_contexts.append(dep_cc_info.compilation_context)
            linking_contexts.append(dep_cc_info.linking_context)

    merged_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = compilation_contexts,
    ) if compilation_contexts else cc_common.create_compilation_context()

    includes = list(ctx.attr.includes) if ctx.attr.includes else []

    compilation_context, compilation_outputs, module_dirs = fortran_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        fortran_toolchain = fortran_toolchain,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        public_hdrs = ctx.files.hdrs,
        includes = includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines if hasattr(ctx.attr, "local_defines") else [],
        user_compile_flags = fortran_toolchain.compile_flags,
        fortran_flags = ctx.attr.fopts,
        compilation_contexts = [merged_compilation_context],
        fortran_deps_module_dirs = depset(transitive = fortran_deps_module_dirs) if fortran_deps_module_dirs else depset(),
        name = ctx.label.name,
        create_module_file = False,
        coverage_enabled = ctx.configuration.coverage_enabled,
    )

    linking_outputs = fortran_common.link(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        fortran_toolchain = fortran_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = linking_contexts,
        user_link_flags = ctx.attr.linkopts,
        link_deps_statically = ctx.attr.linkstatic,
        output_type = "executable",
        stamp = 0,
    )

    executable = linking_outputs.executable

    runfiles_list = []
    for data_dep in ctx.attr.data:
        if DefaultInfo in data_dep:
            if data_dep[DefaultInfo].data_runfiles.files:
                runfiles_list.append(data_dep[DefaultInfo].data_runfiles)
            else:
                runfiles_list.append(ctx.runfiles(transitive_files = data_dep[DefaultInfo].files))
                runfiles_list.append(data_dep[DefaultInfo].default_runfiles)

    for src in ctx.attr.srcs:
        if DefaultInfo in src:
            runfiles_list.append(src[DefaultInfo].default_runfiles)

    for dep in ctx.attr.deps:
        if DefaultInfo in dep:
            runfiles_list.append(dep[DefaultInfo].default_runfiles)

    runfiles = ctx.runfiles().merge_all(runfiles_list)

    object_files = compilation_outputs.objects if compilation_outputs.objects else depset()

    merged_compilation_context = fortran_common.merge_compilation_contexts(
        compilation_contexts = [compilation_context, merged_compilation_context],
    )
    cc_info = CcInfo(
        compilation_context = merged_compilation_context,
        linking_context = CcInfo().linking_context,
    )

    # Create FortranInfo provider
    fortran_info = FortranInfo(
        objects = object_files,
        mods = module_dirs,
        cc_info = cc_info,
    )

    output_groups = {}
    if compilation_outputs.objects:
        output_groups["compilation_outputs"] = compilation_outputs.objects

    return [
        DefaultInfo(
            files = depset([executable]),
            runfiles = runfiles,
            executable = executable,
        ),
        _create_run_environment_info(
            ctx,
            ctx.attr.env if hasattr(ctx.attr, "env") else {},
            ctx.attr.env_inherit if hasattr(ctx.attr, "env_inherit") else [],
            ctx.attr.data,
        ),
        cc_info,
        fortran_info,
        _create_instrumented_files_info(ctx),
        OutputGroupInfo(**output_groups),
    ]

fortran_test = rule(
    doc = "Compiles Fortran source files and links them into a test executable. Can be run with `bazel test`.",
    implementation = _fortran_test_impl,
    attrs = _EXECUTABLE_ATTRS | {
        "env_inherit": attr.string_list(
            doc = "Specifies additional environment variables to inherit from the external environment when the test is executed by bazel test.",
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
    fragments = ["cpp"],
    provides = [CcInfo, FortranInfo],
    test = True,
)
