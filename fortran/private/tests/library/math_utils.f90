module math_utils
    implicit none

contains
    function add(a, b) result(sum)
        integer, intent(in) :: a, b
        integer :: sum
        sum = a + b
    end function add

    function multiply(a, b) result(product)
        integer, intent(in) :: a, b
        integer :: product
        product = a*b
    end function multiply
end module math_utils

