module string_utils
    use math_utils, only: add
    implicit none

contains
    function concatenate_lengths(str1, str2) result(total_length)
        character(len=*), intent(in) :: str1, str2
        integer :: total_length
        total_length = add(len(str1), len(str2))
    end function concatenate_lengths
end module string_utils

