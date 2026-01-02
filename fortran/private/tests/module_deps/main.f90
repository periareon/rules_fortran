program test_module_deps
    use geometry, only: circle_area, circle_circumference
    implicit none

    double precision :: radius, area, circumference

    radius = 5.0d0
    area = circle_area(radius)
    circumference = circle_circumference(radius)

    if (abs(area - 78.5398d0) > 0.001d0) then
        print *, "FAIL: circle_area returned", area
        stop 1
    end if

    if (abs(circumference - 31.4159d0) > 0.001d0) then
        print *, "FAIL: circle_circumference returned", circumference
        stop 1
    end if

    print *, "PASS: module dependency chain works correctly"
end program test_module_deps
