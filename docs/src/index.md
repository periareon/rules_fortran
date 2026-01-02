# rules_fortran

Bazel rules for [Fortran](https://fortran-lang.org/), providing Bazel-native targets for building, testing, and configuring Fortran code via toolchains and a module extension.

## Installation and setup

These rules assume you are using Bazel with bzlmod (a `MODULE.bazel` file).

Add a dependency on `rules_fortran` and enable the module extension that auto-detects a Fortran toolchain:

```starlark
bazel_dep(name = "rules_fortran", version = "<latest>")
```

This will use the host Fortran compiler discovered by the extension (for example, `gfortran` if present on your system).

## Minimal examples

**Library and binary**

```python
load("@rules_fortran//fortran:fortran_binary.bzl", "fortran_binary")
load("@rules_fortran//fortran:fortran_library.bzl", "fortran_library")

fortran_library(
    name = "math_lib",
    srcs = ["math.f90"],
)

fortran_binary(
    name = "app",
    srcs = ["main.f90"],
    deps = [":math_lib"],
)
```

**Test**

```python
load("@rules_fortran//fortran:fortran_test.bzl", "fortran_test")

fortran_test(
    name = "math_test",
    srcs = ["math_test.f90"],
    deps = [":math_lib"],
)
```

For more attributes, configuration options, and module-extension behavior, continue to the [rules reference](./rules.md).
