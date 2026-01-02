program test_main
    use math_utils, only: add, multiply
    implicit none
    integer :: a, b, sum_result, product_result
    logical :: test_passed

    a = 7
    b = 3

    sum_result = add(a, b)
    product_result = multiply(a, b)

    test_passed = (sum_result == 10) .and. (product_result == 21)

    if (test_passed) then
        write (*, *) 'All tests passed!'
        write (*, *) '  add(7, 3) = ', sum_result, ' (expected 10)'
        write (*, *) '  multiply(7, 3) = ', product_result, ' (expected 21)'
        stop 0
    else
        write (*, *) 'Test failed!'
        write (*, *) '  add(7, 3) = ', sum_result, ' (expected 10)'
        write (*, *) '  multiply(7, 3) = ', product_result, ' (expected 21)'
        stop 1
    end if
end program test_main

