module greeting
    implicit none

contains
    subroutine greet(name, length)
        integer, intent(in) :: length
        character(len=length), intent(in) :: name
        write (*, '(A, A)') 'Hello, ', trim(name)
    end subroutine greet
end module greeting
