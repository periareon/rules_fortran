// C++ wrapper that uses the Fortran library
#include <iostream>

// Forward declarations for Fortran functions
extern "C" {
int fortran_add(int a, int b);
int fortran_multiply(int a, int b);
}

namespace cc_wrapper {
int add(int a, int b) { return fortran_add(a, b); }

int multiply(int a, int b) { return fortran_multiply(a, b); }
}  // namespace cc_wrapper
