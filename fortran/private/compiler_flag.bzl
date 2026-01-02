"""Rule that allows select() to differentiate between Fortran compilers."""

load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _compiler_flag_impl(ctx):
    """Read the Fortran toolchain's compiler identifier and expose it as a feature flag.

    Args:
        ctx (ctx): The rule context.

    Returns:
        list[FeatureFlagInfo]: A single-element list with the compiler identifier.
    """
    fortran_toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fortran_toolchain
    value = fortran_toolchain.compiler if fortran_toolchain.compiler else ""
    return [config_common.FeatureFlagInfo(value = value)]

compiler_flag = rule(
    doc = "Exposes the Fortran toolchain's `compiler` identifier as a feature flag for use with `config_setting` `flag_values`.",
    implementation = _compiler_flag_impl,
    toolchains = [TOOLCHAIN_TYPE],
)
