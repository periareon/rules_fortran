program test_main
    implicit none
    integer :: test_value, expected

    test_value = 42
    expected = 42

    if (test_value == expected) then
        write (*, *) 'Test passed: values match'
        stop 0
    else
        write (*, *) 'Test failed: values do not match'
        stop 1
    end if
end program test_main

