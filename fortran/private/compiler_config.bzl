"""Compiler-specific flag configuration for Fortran toolchains.

Provides preset configurations for supported compilers and a constructor
for building custom configurations. The toolchain reads these values to
produce compiler-agnostic compilation actions.
"""

def create_compiler_config(
        compile_flag = "-c",
        output_flag = "-o",
        module_dir_flag = "-J",
        module_search_flag = "-I",
        object_extension = ".o",
        runtime_libraries = ["gfortran"]):
    """Create a compiler configuration struct.

    Args:
        compile_flag (str): Flag to compile without linking.
        output_flag (str): Flag to specify the output file.
        module_dir_flag (str): Flag to specify the module output directory.
        module_search_flag (str): Flag to add a module/include search path.
        object_extension (str): File extension for compiled object files.
        runtime_libraries (list[str]): Runtime library names to link (without
            the ``lib`` prefix or file extension).

    Returns:
        struct: A compiler configuration with all specified fields.
    """
    return struct(
        compile_flag = compile_flag,
        output_flag = output_flag,
        module_dir_flag = module_dir_flag,
        module_search_flag = module_search_flag,
        object_extension = object_extension,
        runtime_libraries = runtime_libraries,
    )

COMPILER_CONFIGS = {
    "flang": create_compiler_config(
        module_dir_flag = "-module-dir",
        runtime_libraries = ["flang_rt.runtime"],
    ),
    "gfortran": create_compiler_config(),
    "ifx": create_compiler_config(
        module_dir_flag = "-module",
        runtime_libraries = ["ifcore", "ifport"],
    ),
    "lfortran": create_compiler_config(
        runtime_libraries = [],
    ),
    "nagfor": create_compiler_config(
        module_dir_flag = "-mdir",
        runtime_libraries = [],
    ),
}

def get_default_config(compiler_id):
    """Look up the preset compiler configuration for a given compiler identifier.

    Falls back to the gfortran configuration for unrecognized identifiers.

    Args:
        compiler_id (str): A compiler identifier (e.g. "gfortran", "flang").

    Returns:
        struct: The matching compiler configuration.
    """
    return COMPILER_CONFIGS.get(compiler_id, COMPILER_CONFIGS["gfortran"])
