! Fortran library with C bindings for use from C++
module fortran_lib
    use iso_c_binding
    implicit none

contains
    ! C-compatible function to add two integers
    function fortran_add(a, b) result(sum) bind(c, name='fortran_add')
        integer(c_int), intent(in), value :: a, b
        integer(c_int) :: sum
        sum = a + b
    end function fortran_add

    ! C-compatible function to multiply two integers
    function fortran_multiply(a, b) result(product) bind(c, name='fortran_multiply')
        integer(c_int), intent(in), value :: a, b
        integer(c_int) :: product
        product = a*b
    end function fortran_multiply
end module fortran_lib

