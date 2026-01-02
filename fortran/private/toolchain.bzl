"""Fortran toolchain rules"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(":providers.bzl", "FortranToolchainInfo")

TOOLCHAIN_TYPE = str(Label("//fortran:toolchain_type"))

def _fortran_toolchain_impl(ctx):
    """Implementation of the fortran_toolchain rule.

    Assembles a FortranToolchainInfo provider from the configured compiler,
    flags, and the underlying C++ toolchain used for linking. The provider
    is wrapped inside a generic ToolchainInfo for Bazel's toolchain
    resolution mechanism.

    Args:
        ctx (ctx): The rule context.

    Returns:
        list[Provider]: ToolchainInfo, FortranToolchainInfo, and TemplateVariableInfo.
    """
    make_variable_info = platform_common.TemplateVariableInfo({
        "FC": ctx.file.fortran.path,
        "FORTRAN": ctx.file.fortran.path,
    })

    cc_toolchain = ctx.attr.cc_toolchain
    if not cc_toolchain:
        cc_toolchain = ctx.toolchains["@rules_cc//cc:toolchain_type"]

        if not cc_toolchain:
            fail("No cc_toolchain provided or found for fortran_toolchain.")

    fortran_toolchain_info = FortranToolchainInfo(
        label = ctx.label,
        compiler = ctx.attr.compiler,
        fortran = ctx.file.fortran,
        compile_flags = ctx.attr.compile_flags,
        link_flags = ctx.attr.link_flags,
        compiler_config = struct(
            compile_flag = ctx.attr.compile_flag,
            output_flag = ctx.attr.output_flag,
            module_dir_flag = ctx.attr.module_dir_flag,
            module_search_flag = ctx.attr.module_search_flag,
            object_extension = ctx.attr.object_extension,
        ),
        cc_toolchain = cc_toolchain,
    )

    return [
        platform_common.ToolchainInfo(
            fortran_toolchain = fortran_toolchain_info,
        ),
        fortran_toolchain_info,
        make_variable_info,
    ]

fortran_toolchain = rule(
    doc = """\
Defines a Fortran toolchain that provides the Fortran compiler and compilation/linking flags.

Example:

```python
load("@rules_fortran//fortran:fortran_toolchain.bzl", "fortran_toolchain")

fortran_toolchain(
    name = "gfortran_toolchain",
    compiler = "gfortran",
    fortran = "@gcc_toolchain//:bin/gfortran",
    compile_flags = ["-O2"],
    link_flags = ["-lgfortran"],
)

Register the resulting toolchain with:

```python
register_toolchains("//:gfortran_toolchain")
```
""",
    implementation = _fortran_toolchain_impl,
    attrs = {
        "cc_toolchain": attr.label(
            doc = "The C++ toolchain to use for linking. If not provided, will attempt to find one from the default C++ toolchain.",
            providers = [cc_common.CcToolchainInfo],
        ),
        "compile_flag": attr.string(
            default = "-c",
            doc = "Flag to compile without linking.",
        ),
        "compile_flags": attr.string_list(
            doc = "Additional compiler flags to use when compiling Fortran source files.",
        ),
        "compiler": attr.string(
            doc = "Identifier for the Fortran compiler (e.g. gfortran, flang, ifx). Used by config_settings at //fortran/compiler/ for select().",
        ),
        "fortran": attr.label(
            doc = "The Fortran compiler executable (e.g., gfortran).",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "link_flags": attr.string_list(
            doc = "Additional linker flags to use when linking Fortran executables and libraries (e.g., -lgfortran).",
        ),
        "module_dir_flag": attr.string(
            default = "-J",
            doc = "Flag to specify the module output directory. Varies by compiler: -J (gfortran), -module-dir (LLVM flang), -module (ifx), -mdir (nagfor).",
        ),
        "module_search_flag": attr.string(
            default = "-I",
            doc = "Flag to add a module/include search path.",
        ),
        "object_extension": attr.string(
            default = ".o",
            doc = "File extension for compiled object files (e.g. .o on Unix, .obj on Windows).",
        ),
        "output_flag": attr.string(
            default = "-o",
            doc = "Flag to specify the output file.",
        ),
    },
    toolchains = [
        config_common.toolchain_type("@rules_cc//cc:toolchain_type", mandatory = False),
    ],
)

def _current_fortran_toolchain_impl(ctx):
    """Implementation of the current_fortran_toolchain rule.

    Forwards the resolved Fortran toolchain providers.

    Args:
        ctx (ctx): The rule context.

    Returns:
        list[Provider]: ToolchainInfo and FortranToolchainInfo.
    """
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
    fortran_toolchain = toolchain_info.fortran_toolchain

    return [
        toolchain_info,
        fortran_toolchain,
    ]

current_fortran_toolchain = rule(
    doc = "A rule that provides access to the currently selected Fortran toolchain.",
    implementation = _current_fortran_toolchain_impl,
    toolchains = [TOOLCHAIN_TYPE],
)
