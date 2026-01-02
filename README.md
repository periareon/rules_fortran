# rules_fortran

Bazel rules for [Fortran](https://fortran-lang.org/): build, test, and configure Fortran code with Bazel toolchains and rules.

## Quickstart

1. **Add the module extension** to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_fortran", version = "<latest>")
```

2. **Define a simple binary** in `BUILD.bazel`:

```starlark
load("//fortran:defs.bzl", "fortran_binary")

fortran_binary(
    name = "hello_world",
    srcs = ["hello_world.f90"],
)
```

For full setup details, rule reference, and more examples, see the docs: <https://periareon.github.io/rules_fortran/>
