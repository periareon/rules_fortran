program runfiles_test
    use runfiles
    implicit none

    type(runfiles_t) :: rf
    character(len=512) :: error_msg
    character(len=:), allocatable :: path
    logical :: ok
    integer :: unit_num, ios
    character(len=256) :: line

    call runfiles_create_for_test(rf, error_msg, ok)
    if (.not. ok) then
        print *, 'FAIL: runfiles_create_for_test: ', trim(error_msg)
        stop 1
    end if

    path = rf%rlocation('_main/fortran/runfiles/tests/test_data.txt')
    if (len(path) == 0) then
        print *, 'FAIL: rlocation returned empty string'
        stop 1
    end if

    unit_num = 42
    open(unit=unit_num, file=path, status='old', action='read', iostat=ios)
    if (ios /= 0) then
        print *, 'FAIL: could not open file: ', path
        stop 1
    end if

    read(unit_num, '(A)', iostat=ios) line
    close(unit_num)

    if (ios /= 0) then
        print *, 'FAIL: could not read from file'
        stop 1
    end if

    if (trim(line) /= 'Hello from runfiles!') then
        print *, 'FAIL: unexpected content: "', trim(line), '"'
        stop 1
    end if

    ! Test that absolute paths are returned as-is.
    path = rf%rlocation('/absolute/path')
    if (path /= '/absolute/path') then
        print *, 'FAIL: absolute path not returned as-is: "', path, '"'
        stop 1
    end if

    ! Test that invalid paths return empty string.
    path = rf%rlocation('../escape')
    if (len(path) /= 0) then
        print *, 'FAIL: expected empty for ../escape, got: "', path, '"'
        stop 1
    end if

    call rf%destroy()

    print *, 'PASS: all runfiles tests passed'
end program runfiles_test
