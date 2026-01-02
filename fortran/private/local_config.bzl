"""Fortran toolchain configuration"""

load(":compiler_config.bzl", "get_default_config")

_FORTRAN_WINDOWS = """\
@ECHO OFF
set "A=%~1"
set "A=%A:/=\\%"
"{fortran}" %A%
exit /b %ERRORLEVEL%
"""

_NO_FORTRAN_WINDOWS = """\
@ECHO OFF

echo "Fortran could not be located on host"
exit 1
"""

_FORTRAN_UNIX = """\
#!/bin/sh

exec {fortran} "$@"
"""

_NO_FORTRAN_UNIX = """\
#!/bin/sh

echo "Fortran could not be located on host"
exit 1
"""

_FORTRAN_TOOLCHAIN_TEMPLATE = """\
load("@rules_fortran//fortran:fortran_toolchain.bzl", "fortran_toolchain")

filegroup(
    name = "fortran",
    srcs = ["{fortran}"],
)

fortran_toolchain(
    name = "fortran_toolchain",
    compiler = "{compiler_id}",
    fortran = ":fortran",
    link_flags = {link_flags},
    module_dir_flag = "{module_dir_flag}",
    visibility = ["//visibility:public"],
)

alias(
    name = "{name}",
    actual = ":fortran_toolchain",
    visibility = ["//visibility:public"],
)
"""

def _auto_configure_warning(msg):
    """Output a colored warning message during auto configuration.

    Args:
        msg (str): The warning message to display.
    """
    yellow = "\033[1;33m"
    no_color = "\033[0m"

    # buildifier: disable=print
    print("\n%sFortran Auto-Configuration Warning:%s %s\n" % (yellow, no_color, msg))

def _verify_compiler(repository_ctx, fortran):
    """Verify that the Fortran compiler works by running --version.

    Args:
        repository_ctx (repository_ctx): The repository rule context.
        fortran (path): Path to the Fortran compiler executable.

    Returns:
        bool: True if the compiler works, False otherwise.
    """
    result = repository_ctx.execute([fortran, "--version"])
    if result.return_code != 0:
        _auto_configure_warning(
            "Fortran compiler at '%s' failed --version check (exit code %d): %s" % (
                fortran,
                result.return_code,
                result.stderr,
            ),
        )
        return False
    return True

def _discover_library_dirs(repository_ctx, fortran, runtime_libraries):
    """Discover Fortran runtime library directories by probing the compiler.

    For each library in runtime_libraries, tries
    ``-print-file-name=lib<name>.<ext>`` with static (``.a``) then shared
    (``.dylib`` on macOS, ``.so`` on Linux) extensions, then falls back to
    parsing ``-print-search-dirs`` output.

    Args:
        repository_ctx (repository_ctx): The repository rule context.
        fortran (path): Path to the Fortran compiler executable.
        runtime_libraries (list[str]): Runtime library names to probe for.

    Returns:
        list[str]: A list of ``-L<path>`` flags for discovered library directories.
    """
    lib_dirs = []

    extensions = [".a"]
    if "mac" in repository_ctx.os.name:
        extensions.append(".dylib")
    elif "win" not in repository_ctx.os.name:
        extensions.append(".so")

    for lib_name in runtime_libraries:
        for ext in extensions:
            filename = "lib%s%s" % (lib_name, ext)
            result = repository_ctx.execute([fortran, "-print-file-name=" + filename])
            if result.return_code == 0:
                path = result.stdout.strip()
                if path and path != filename:
                    last_sep = path.rfind("/")
                    if last_sep > 0:
                        lib_dir = "-L" + path[:last_sep]
                        if lib_dir not in lib_dirs:
                            lib_dirs.append(lib_dir)
                    break

    if lib_dirs:
        return lib_dirs

    result = repository_ctx.execute([fortran, "-print-search-dirs"])
    if result.return_code == 0:
        for line in result.stdout.split("\n"):
            if line.startswith("libraries:"):
                paths_str = line[len("libraries:"):].strip()
                if paths_str.startswith("="):
                    paths_str = paths_str[1:]
                for p in paths_str.split(":"):
                    p = p.strip()
                    if p:
                        lib_dirs.append("-L" + p)
                break

    if lib_dirs:
        return lib_dirs

    fortran_path = str(fortran)
    bin_idx = fortran_path.rfind("/bin/")
    if bin_idx > 0:
        lib_dirs.append("-L" + fortran_path[:bin_idx] + "/lib")

    return lib_dirs

def _detect_compiler_id(compiler_name):
    """Derive a canonical compiler identifier from the compiler command name.

    Args:
        compiler_name (str): The compiler command (e.g. "gfortran", "flang-new",
            "ifx", "/usr/bin/gfortran-13").

    Returns:
        str: A short identifier ("gfortran", "flang", "ifx", "nagfor",
            "lfortran"), or the original name if unrecognized.
    """
    name = compiler_name.lower()
    if "gfortran" in name:
        return "gfortran"
    if "flang" in name:
        return "flang"
    if "ifx" in name or "ifort" in name:
        return "ifx"
    if "nagfor" in name:
        return "nagfor"
    if "lfortran" in name:
        return "lfortran"
    return compiler_name

def _fortran_autoconf_impl(repository_ctx):
    """Detect and configure the Fortran compiler on the host system.

    Locates the Fortran compiler via environment variables (FORTRAN, FC, CC)
    or falls back to gfortran. Creates a wrapper script and generates a
    BUILD.bazel with a fortran_toolchain target.

    Args:
        repository_ctx (repository_ctx): The repository rule context.
    """
    env = repository_ctx.os.environ

    compiler = "gfortran"
    if "FORTRAN" in env:
        compiler = env["FORTRAN"]
    elif "FC" in env:
        compiler = env["FC"]
    elif "CC" in env:
        if "clang" in env["CC"]:
            compiler = "flang"
        elif "gcc" in env["CC"]:
            compiler = "gfortran"

    compiler_id = _detect_compiler_id(compiler)
    compiler_config = get_default_config(compiler_id)
    is_windows = "win" in repository_ctx.os.name

    fortran = repository_ctx.which(compiler)
    link_flags = []
    if fortran:
        if not _verify_compiler(repository_ctx, fortran):
            _auto_configure_warning(
                "Fortran compiler '%s' was found but failed validation. " +
                "Builds requiring Fortran will fail." % compiler,
            )

        if is_windows:
            repository_ctx.file(
                "fortran.bat",
                _FORTRAN_WINDOWS.format(fortran = fortran),
                executable = True,
            )
        else:
            repository_ctx.file(
                "fortran.sh",
                _FORTRAN_UNIX.format(fortran = fortran),
                executable = True,
            )

        runtime_libs = compiler_config.runtime_libraries
        if runtime_libs:
            lib_dirs = _discover_library_dirs(repository_ctx, fortran, runtime_libs)
            link_flags = lib_dirs + ["-l%s" % lib for lib in runtime_libs]
    elif is_windows:
        repository_ctx.file("fortran.bat", _NO_FORTRAN_WINDOWS, executable = True)
    else:
        repository_ctx.file("fortran.sh", _NO_FORTRAN_UNIX, executable = True)

    link_flags_str = "[" + ", ".join(['"' + flag + '"' for flag in link_flags]) + "]" if link_flags else "[]"
    repository_ctx.file("BUILD.bazel", _FORTRAN_TOOLCHAIN_TEMPLATE.format(
        compiler_id = compiler_id,
        fortran = "fortran.bat" if is_windows else "fortran.sh",
        module_dir_flag = compiler_config.module_dir_flag,
        name = repository_ctx.original_name,
        link_flags = link_flags_str,
    ))

    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.original_name,
    ))

fortran_autoconf = repository_rule(
    doc = "Repository rule that automatically detects and configures the Fortran compiler on the host system.",
    environ = [
        "CC",
        "DEVELOPER_DIR",
        "FC",
        "FORTRAN",
        "PATH",
    ],
    implementation = _fortran_autoconf_impl,
    configure = True,
)

_TOOLCHAIN_TEMPLATE = """\
load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")

toolchain(
    name = "toolchain",
    exec_compatible_with = HOST_CONSTRAINTS,
    target_compatible_with = HOST_CONSTRAINTS,
    toolchain = "{toolchain}",
    toolchain_type = "@rules_fortran//fortran:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

_NO_TOOLCHAIN_TEMPLATE = """\
# Fortran toolchain autoconfiguration was disabled by BAZEL_DO_NOT_DETECT_FORTRAN_TOOLCHAIN env variable.
"""

def _fortran_autoconf_toolchains_impl(repository_ctx):
    """Generate a BUILD file with toolchain targets for the local Fortran toolchain.

    Creates a `toolchain()` target constrained to the host platform, or an
    empty BUILD file if `BAZEL_DO_NOT_DETECT_FORTRAN_TOOLCHAIN=1` is set.

    Args:
        repository_ctx (repository_ctx): The repository rule context.
    """
    env = repository_ctx.os.environ

    should_detect_fortran_toolchain = "BAZEL_DO_NOT_DETECT_FORTRAN_TOOLCHAIN" not in env or env["BAZEL_DO_NOT_DETECT_FORTRAN_TOOLCHAIN"] != "1"

    if should_detect_fortran_toolchain:
        repository_ctx.file("BUILD.bazel", _TOOLCHAIN_TEMPLATE.format(
            toolchain = str(repository_ctx.attr.local_config_fortran),
        ))
    else:
        repository_ctx.file("BUILD.bazel", _NO_TOOLCHAIN_TEMPLATE)

    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.original_name,
    ))

fortran_autoconf_toolchains = repository_rule(
    doc = "Repository rule that generates toolchain targets for the detected Fortran compiler.",
    implementation = _fortran_autoconf_toolchains_impl,
    environ = [
        "BAZEL_DO_NOT_DETECT_FORTRAN_TOOLCHAIN",
    ],
    attrs = {
        "local_config_fortran": attr.label(
            doc = "Label pointing to the local_config_fortran repository containing the Fortran toolchain definition.",
            mandatory = True,
        ),
    },
    configure = True,
)
