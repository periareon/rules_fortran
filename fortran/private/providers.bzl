"""Fortran rule providers."""

FortranInfo = provider(
    doc = "Information about Fortran targets.",
    fields = {
        "cc_info": "CcInfo: The CcInfo provider for the current target.",
        "mods": "depset[File]: Directories containing module files.",
        "objects": "depset[File]: Compiled object files.",
    },
)

FortranToolchainInfo = provider(
    doc = "Information about a configured Fortran toolchain.",
    fields = {
        "cc_toolchain": "Target: The underlying C++ toolchain for linking.",
        "compile_flags": "list[str]: Toolchain-level compile flags.",
        "compiler": "str: Compiler identifier (gfortran, flang, ifx, nagfor, lfortran).",
        "compiler_config": "struct: Compiler-specific flag configuration (compile_flag, output_flag, module_dir_flag, module_search_flag, object_extension).",
        "fortran": "File: The Fortran compiler executable.",
        "label": "Label: The label of the toolchain target.",
        "link_flags": "list[str]: Toolchain-level link flags.",
    },
)
