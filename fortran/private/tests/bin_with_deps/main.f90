program main
    use math_utils, only: add, multiply
    implicit none
    integer :: x, y, result_sum, result_product

    x = 10
    y = 5

    result_sum = add(x, y)
    result_product = multiply(x, y)

    write (*, *) 'x = ', x
    write (*, *) 'y = ', y
    write (*, *) 'x + y = ', result_sum
    write (*, *) 'x * y = ', result_product
end program main

