program test_transitive_mods
    use types_mod, only: point_t
    use ops_mod, only: translate_point
    implicit none

    type(point_t) :: p, result

    p%x = 1.0d0
    p%y = 2.0d0
    result = translate_point(p, 3.0d0, 4.0d0)

    if (abs(result%x - 4.0d0) > 1.0d-10) then
        print *, "FAIL: expected x=4.0, got", result%x
        stop 1
    end if

    if (abs(result%y - 6.0d0) > 1.0d-10) then
        print *, "FAIL: expected y=6.0, got", result%y
        stop 1
    end if

    print *, "PASS: transitive module dependency works correctly"
end program test_transitive_mods
