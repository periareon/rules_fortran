"""Fortran module extensions for automatically configuring host toolchains."""

load("//fortran/private:local_config.bzl", "fortran_autoconf", "fortran_autoconf_toolchains")

def _fortran_configure_extension_impl(module_ctx):
    """Configure the Fortran toolchain for the host platform.

    Creates the `local_config_fortran` and `local_config_fortran_toolchains`
    repositories via auto-detection.

    Args:
        module_ctx (module_ctx): The module extension context.

    Returns:
        module_ctx.extension_metadata: Extension metadata marked as reproducible.
    """
    fortran_autoconf(
        name = "local_config_fortran",
    )
    fortran_autoconf_toolchains(
        name = "local_config_fortran_toolchains",
        local_config_fortran = "@local_config_fortran",
    )

    return module_ctx.extension_metadata(reproducible = True)

fortran_configure_extension = module_extension(
    doc = "Module extension that detects a host Fortran compiler and exports local_config_fortran and local_config_fortran_toolchains repositories.",
    implementation = _fortran_configure_extension_impl,
)
