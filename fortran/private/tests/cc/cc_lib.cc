// C++ library with C interface for use from Fortran
#include <cstdint>

extern "C" {
// C-compatible function to subtract two integers
int32_t cc_subtract(int32_t a, int32_t b) { return a - b; }

// C-compatible function to divide two integers
int32_t cc_divide(int32_t a, int32_t b) {
    if (b == 0) {
        return 0;  // Simple error handling
    }
    return a / b;
}
}
