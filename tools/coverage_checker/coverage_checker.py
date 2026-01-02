"""Verify that a Bazel lcov coverage report contains Fortran source file entries."""

import re
import sys

FORTRAN_SF_PATTERN = re.compile(r"^SF:.*\.(f90|f|F90|F|for|FOR)$", re.MULTILINE)
ALL_SF_PATTERN = re.compile(r"^SF:(.+)$", re.MULTILINE)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-coverage-report>", file=sys.stderr)
        return 2

    report_path = sys.argv[1]

    try:
        with open(report_path) as f:
            content = f.read()
    except FileNotFoundError:
        print(f"ERROR: Coverage report not found at {report_path}", file=sys.stderr)
        return 1

    fortran_matches = FORTRAN_SF_PATTERN.findall(content)
    if not fortran_matches:
        all_sources = ALL_SF_PATTERN.findall(content)
        print(
            "ERROR: Coverage report does not contain Fortran source files",
            file=sys.stderr,
        )
        if all_sources:
            print("Source files present in report:", file=sys.stderr)
            for src in all_sources:
                print(f"  {src}", file=sys.stderr)
        else:
            print("Report contains no SF: entries at all", file=sys.stderr)
        return 1

    fortran_sources = [
        m.group(0)
        for m in re.finditer(r"^SF:.*\.(f90|f|F90|F|for|FOR)$", content, re.MULTILINE)
    ]
    print("Coverage report contains Fortran coverage data:")
    for sf in fortran_sources:
        print(f"  {sf}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
