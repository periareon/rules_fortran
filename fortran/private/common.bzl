"""Common utilities for Fortran compilation and linking."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:action_names.bzl", "CPP_COMPILE_ACTION_NAME")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

CC_DISABLED_FEATURES = [
    "macos_minimum_os",
    "default_compile_flags",
    "cpp_compile_flags",
]

def _disambiguate_output_names(srcs):
    """Disambiguate object file output names when multiple sources share a basename.

    Mirrors rules_cc's _calculate_output_name_map: assigns numeric prefixes
    when two or more sources have the same basename (case-insensitive).

    Args:
        srcs (list[File]): Source files to disambiguate.

    Returns:
        dict[File, str]: Map from each source File to its disambiguated output stem.
    """
    count = {}
    for src in srcs:
        stem = src.basename.rpartition(".")[0].lower()
        count[stem] = count.get(stem, 0) + 1
    number = {}
    result = {}
    for src in srcs:
        stem = src.basename.rpartition(".")[0]
        stem_lower = stem.lower()
        if count.get(stem_lower, 0) >= 2:
            num = number.get(stem_lower, 0)
            number[stem_lower] = num + 1
            result[src] = "%d/%s" % (num, stem)
        else:
            result[src] = stem
    return result

def _compile(
        *,
        actions,
        feature_configuration,
        fortran_toolchain,
        cc_toolchain,
        srcs = [],
        public_hdrs = [],
        private_hdrs = [],
        includes = [],
        quote_includes = [],
        defines = [],
        local_defines = [],
        user_compile_flags = [],
        fortran_flags = [],
        compilation_contexts = [],
        fortran_deps_module_dirs = [],
        name,
        create_module_file = True,
        disallow_pic_outputs = False,
        additional_inputs = [],
        coverage_enabled = False):
    """Compile Fortran source files using a custom Fortran compilation action.

    Args:
        actions (actions): The actions object from the rule context.
        feature_configuration (FeatureConfiguration): Feature configuration for the compilation.
        fortran_toolchain (FortranToolchainInfo): The Fortran toolchain.
        cc_toolchain (CcToolchainInfo): The C++ toolchain to use for compilation.
        srcs (list[File]): Fortran source files to compile.
        public_hdrs (list[File]): Public header/include files propagated to dependents.
        private_hdrs (list[File]): Private header/include files not propagated to dependents.
        includes (list[str]): Include directories to add to the search path.
        quote_includes (list[str]): Quote include directories.
        defines (list[str]): Preprocessor defines propagated to dependents.
        local_defines (list[str]): Preprocessor defines local to this target only.
        user_compile_flags (list[str]): Toolchain-level compile flags.
        fortran_flags (list[str]): Per-target Fortran compile flags (fopts).
        compilation_contexts (list[CcCompilationContext]): Compilation contexts from dependencies.
        fortran_deps_module_dirs (depset[File]): Module directories from Fortran dependencies.
        name (str): Name for the compilation outputs.
        create_module_file (bool): Whether to create .mod files (True for libraries, False for binaries/tests).
        disallow_pic_outputs (bool): Whether to disallow position-independent code outputs.
        additional_inputs (list[File]): Extra input files needed during compilation.
        coverage_enabled (bool): Whether code coverage instrumentation is enabled (from ctx.configuration.coverage_enabled).

    Returns:
        tuple[CcCompilationContext, CcCompilationOutputs, depset[File]]: A tuple of
            (compilation_context, compilation_outputs, module_dirs). module_dirs is a
            depset of module directories (one per source file), or an empty depset if
            no modules are produced.
    """
    if not srcs:
        return (cc_common.create_compilation_context(), cc_common.create_compilation_outputs(), depset())

    merged_compilation_context = None
    if compilation_contexts:
        merged_compilation_context = cc_common.merge_compilation_contexts(compilation_contexts = compilation_contexts)

    module_dirs_from_deps = []
    module_dirs_from_deps_paths = []
    if fortran_deps_module_dirs:
        module_dirs_from_deps = fortran_deps_module_dirs.to_list()
        module_dirs_from_deps_paths = [entry.path for entry in module_dirs_from_deps]

    system_include_dirs = []
    if merged_compilation_context:
        system_include_dirs.extend(merged_compilation_context.system_includes.to_list())

    all_user_compile_flags = user_compile_flags + fortran_flags
    fortran_compiler = fortran_toolchain.fortran
    config = fortran_toolchain.compiler_config
    suffix = config.object_extension

    include_dirs_transitive = []
    quote_include_dirs_transitive = []
    system_include_dirs_transitive = []
    system_include_dirs_direct = list(system_include_dirs)
    if merged_compilation_context:
        include_dirs_transitive.append(merged_compilation_context.includes)
        quote_include_dirs_transitive.append(merged_compilation_context.quote_includes)
        system_include_dirs_transitive.append(merged_compilation_context.system_includes)
    if hasattr(cc_toolchain, "built_in_include_directories"):
        system_include_dirs_direct.extend(cc_toolchain.built_in_include_directories)

    include_dirs = depset(direct = includes, transitive = include_dirs_transitive)
    quote_include_dirs = depset(direct = quote_includes, transitive = quote_include_dirs_transitive)
    system_include_dirs_depset = depset(direct = system_include_dirs_direct, transitive = system_include_dirs_transitive)

    compile_variables = cc_common.create_compile_variables(
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        include_directories = include_dirs,
        quote_include_directories = quote_include_dirs,
        system_include_directories = system_include_dirs_depset,
        user_compile_flags = all_user_compile_flags,
        preprocessor_defines = depset(defines + local_defines),
    )

    cpp_compile_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )

    is_gfortran = fortran_toolchain.compiler == "gfortran"

    filtered_flags = []
    keep_next = False
    skip_next = False
    for flag in cpp_compile_flags:
        if skip_next:
            skip_next = False
            continue
        if keep_next:
            filtered_flags.append(flag)
            keep_next = False
            continue
        if flag == "-isystem":
            if is_gfortran:
                filtered_flags.append(flag)
                keep_next = True
            else:
                skip_next = True
        elif flag.startswith("-isystem"):
            if is_gfortran:
                filtered_flags.append(flag)
        elif flag.startswith(("-I", "-D", "-L")):
            filtered_flags.append(flag)
        elif flag in all_user_compile_flags:
            filtered_flags.append(flag)
    cpp_compile_flags = filtered_flags

    if coverage_enabled and fortran_toolchain.compiler == "gfortran":
        cpp_compile_flags = cpp_compile_flags + ["--coverage"]

    output_name_map = _disambiguate_output_names(srcs)

    module_dirs = []
    object_files = []
    for src in srcs:
        src_filestem = output_name_map[src]

        out_name = paths.join("_objs", name, src_filestem + suffix)
        object_file = actions.declare_file(out_name)
        object_files.append(object_file)
        outputs = [object_file]

        module_dir = None
        if create_module_file:
            mod_name = paths.join("_objs", name, src_filestem + "_mod")
            module_dir = actions.declare_directory(mod_name)
            module_dirs.append(module_dir)
            outputs.append(module_dir)

        src_args = actions.args()
        src_args.use_param_file("@%s", use_always = True)
        src_args.set_param_file_format("multiline")
        src_args.add(config.compile_flag)
        src_args.add_all(module_dirs_from_deps_paths, before_each = config.module_search_flag)
        src_args.add_all(cpp_compile_flags)
        if create_module_file and module_dir:
            src_args.add(config.module_dir_flag, module_dir.path)

        src_args.add(src)
        src_args.add(config.output_flag, object_file)

        action_inputs = [src] + list(public_hdrs) + list(private_hdrs) + list(additional_inputs)
        for mod_dir in module_dirs_from_deps:
            if mod_dir:
                action_inputs.append(mod_dir)

        actions.run(
            inputs = action_inputs,
            outputs = outputs,
            executable = fortran_compiler,
            arguments = [src_args],
            mnemonic = "FortranCompile",
            progress_message = "Compiling Fortran source %s" % src.short_path,
        )

    compilation_outputs = cc_common.create_compilation_outputs(
        objects = depset(object_files),
        pic_objects = depset(object_files) if not disallow_pic_outputs else depset(),
    )

    system_includes_list = [mod_dir.path for mod_dir in module_dirs]
    system_includes_list.extend(system_include_dirs)

    new_compilation_context = cc_common.create_compilation_context(
        headers = depset(public_hdrs + private_hdrs),
        system_includes = depset(system_includes_list),
        includes = depset(includes) if includes else depset(),
        quote_includes = depset(quote_includes) if quote_includes else depset(),
        defines = depset(defines + local_defines),
    )

    if merged_compilation_context:
        compilation_context = cc_common.merge_compilation_contexts(
            compilation_contexts = [new_compilation_context, merged_compilation_context],
        )
    else:
        compilation_context = new_compilation_context

    return (
        compilation_context,
        compilation_outputs,
        depset(module_dirs),
    )

def _link(
        *,
        actions,
        name,
        feature_configuration,
        cc_toolchain,
        fortran_toolchain,
        compilation_outputs,
        linking_contexts = [],
        user_link_flags = [],
        link_deps_statically = True,
        output_type = "executable",
        stamp = -1,
        **kwargs):
    """Link Fortran object files into an executable or shared library.

    Args:
        actions (actions): The actions object from the rule context.
        name (str): Name for the output file.
        feature_configuration (FeatureConfiguration): Feature configuration for linking.
        cc_toolchain (CcToolchainInfo): The C++ toolchain to use for linking.
        fortran_toolchain (FortranToolchainInfo): The Fortran toolchain containing link flags.
        compilation_outputs (CcCompilationOutputs): Compilation outputs containing object files to link.
        linking_contexts (list[CcLinkingContext]): Linking contexts from dependencies.
        user_link_flags (list[str]): User-provided linker flags from the rule (e.g., linkopts).
        link_deps_statically (bool): If True, prefer static libraries when linking deps.
        output_type (str): Type of output ("executable", "dynamic_library", etc.).
        stamp (int): Whether to include build information (0 = no, 1 = yes, -1 = default).
        **kwargs: Additional arguments passed to cc_common.link.

    Returns:
        CcLinkingOutputs: The linked executable or library.
    """
    all_user_link_flags = list(user_link_flags)
    all_user_link_flags.extend(fortran_toolchain.link_flags)
    return cc_common.link(
        actions = actions,
        name = name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = linking_contexts,
        user_link_flags = all_user_link_flags,
        link_deps_statically = link_deps_statically,
        output_type = output_type,
        stamp = stamp,
        **kwargs
    )

def _configure_features(
        *,
        ctx,
        cc_toolchain,
        requested_features = None,
        unsupported_features = None):
    """Configure CC features for Fortran compilation, disabling C++-specific defaults.

    Uses a two-pass probe: first configures without CC_DISABLED_FEATURES to
    detect which features are active (and potentially unconditionally implied
    by the toolchain), then reconfigures with only the safely-disableable
    subset.  Features that remain active despite being unwanted are handled
    by the compile-flag allowlist filter in _compile().

    Args:
        ctx (ctx): The rule context.
        cc_toolchain (CcToolchainInfo): The C++ toolchain to configure features for.
        requested_features (list[str]): Features to enable. Defaults to ctx.features.
        unsupported_features (list[str]): Features to disable. Defaults to
            ctx.disabled_features plus CC_DISABLED_FEATURES.

    Returns:
        FeatureConfiguration: The configured feature set.
    """
    if requested_features == None:
        requested_features = ctx.features

    if unsupported_features == None:
        unsupported_features = ctx.disabled_features

    # Pass 1: probe without CC_DISABLED_FEATURES to see what the toolchain
    # activates by default.  This call always succeeds.
    probe_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = requested_features,
        unsupported_features = unsupported_features,
    )

    # Features NOT enabled in the probe are safe to mark unsupported -- they
    # are definitely not unconditionally implied by the toolchain.
    # Features that ARE enabled might be unconditionally implied; adding them
    # to unsupported_features would trigger a hard fail() in rules_cc >=0.2.17.
    # Those are left active and handled by the compile-flag allowlist filter.
    safe_unsupported = [
        f
        for f in CC_DISABLED_FEATURES
        if not cc_common.is_enabled(
            feature_configuration = probe_config,
            feature_name = f,
        )
    ]

    if not safe_unsupported:
        return probe_config

    # Pass 2: reconfigure with the safely-disableable subset.
    return cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = requested_features,
        unsupported_features = unsupported_features + safe_unsupported,
    )

def _get_cc_toolchain(fortran_toolchain):
    """Extract the CcToolchainInfo from a Fortran toolchain.

    Handles multiple provider shapes: the legacy `.cc` accessor, the
    CcToolchainInfo provider key, or a direct CcToolchainInfo value.

    Args:
        fortran_toolchain (FortranToolchainInfo): The resolved Fortran toolchain.

    Returns:
        CcToolchainInfo: The underlying C++ toolchain.
    """
    cc_toolchain = fortran_toolchain.cc_toolchain
    if hasattr(cc_toolchain, "cc"):
        return cc_toolchain.cc
    elif cc_common.CcToolchainInfo in cc_toolchain:
        return cc_toolchain[cc_common.CcToolchainInfo]
    else:
        return cc_toolchain

fortran_common = struct(
    compile = _compile,
    link = _link,
    configure_features = _configure_features,
    merge_compilation_contexts = cc_common.merge_compilation_contexts,
    create_linking_context = cc_common.create_linking_context,
    create_linker_input = cc_common.create_linker_input,
    create_library_to_link = cc_common.create_library_to_link,
    merge_linking_contexts = cc_common.merge_linking_contexts,
    create_linking_context_from_compilation_outputs = cc_common.create_linking_context_from_compilation_outputs,
    get_cc_toolchain = _get_cc_toolchain,
)
