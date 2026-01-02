"""# Fortran rules"""

load(
    ":fortran_binary.bzl",
    _fortran_binary = "fortran_binary",
)
load(
    ":fortran_library.bzl",
    _fortran_library = "fortran_library",
)
load(
    ":fortran_shared_library.bzl",
    _fortran_shared_library = "fortran_shared_library",
)
load(
    ":fortran_test.bzl",
    _fortran_test = "fortran_test",
)
load(
    ":fortran_toolchain.bzl",
    _fortran_toolchain = "fortran_toolchain",
)

fortran_binary = _fortran_binary
fortran_library = _fortran_library
fortran_shared_library = _fortran_shared_library
fortran_test = _fortran_test
fortran_toolchain = _fortran_toolchain
