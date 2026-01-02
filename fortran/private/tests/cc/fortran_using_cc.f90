! Fortran library that uses C++ library
module fortran_using_cc
    use iso_c_binding
    implicit none

    ! Interface to C++ functions
    interface
        function cc_subtract(a, b) result(diff) bind(c, name='cc_subtract')
            import :: c_int32_t
            integer(c_int32_t), intent(in), value :: a, b
            integer(c_int32_t) :: diff
        end function cc_subtract

        function cc_divide(a, b) result(quotient) bind(c, name='cc_divide')
            import :: c_int32_t
            integer(c_int32_t), intent(in), value :: a, b
            integer(c_int32_t) :: quotient
        end function cc_divide
    end interface

contains
    function subtract_wrapper(a, b) result(diff)
        integer, intent(in) :: a, b
        integer :: diff
        diff = int(cc_subtract(int(a, c_int32_t), int(b, c_int32_t)))
    end function subtract_wrapper

    function divide_wrapper(a, b) result(quotient)
        integer, intent(in) :: a, b
        integer :: quotient
        quotient = int(cc_divide(int(a, c_int32_t), int(b, c_int32_t)))
    end function divide_wrapper
end module fortran_using_cc

