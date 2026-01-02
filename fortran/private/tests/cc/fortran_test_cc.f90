! Fortran test that uses C++ library
program fortran_test_cc
    use fortran_using_cc, only: subtract_wrapper, divide_wrapper
    implicit none
    integer :: a, b, diff, quotient
    logical :: test_passed

    a = 10
    b = 3

    diff = subtract_wrapper(a, b)
    quotient = divide_wrapper(a, b)

    test_passed = (diff == 7) .and. (quotient == 3)

    if (test_passed) then
        write (*, *) 'Fortran test using C++ library passed!'
        write (*, *) '  subtract(10, 3) = ', diff, ' (expected 7)'
        write (*, *) '  divide(10, 3) = ', quotient, ' (expected 3)'
        stop 0
    else
        write (*, *) 'Test failed!'
        write (*, *) '  subtract(10, 3) = ', diff, ' (expected 7)'
        write (*, *) '  divide(10, 3) = ', quotient, ' (expected 3)'
        stop 1
    end if
end program fortran_test_cc

