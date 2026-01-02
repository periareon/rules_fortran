// C++ test that uses Fortran library via C++ wrapper
#include <cassert>
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

int main() {
    int a = 7;
    int b = 3;

    int sum = cc_wrapper::add(a, b);
    int product = cc_wrapper::multiply(a, b);

    assert(sum == 10);
    assert(product == 21);

    std::cout << "C++ test using Fortran library passed!" << std::endl;
    std::cout << "  add(" << a << ", " << b << ") = " << sum << std::endl;
    std::cout << "  multiply(" << a << ", " << b << ") = " << product
              << std::endl;

    return 0;
}
