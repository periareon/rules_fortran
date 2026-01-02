module geometry
    use constants, only: PI
    implicit none

contains
    function circle_area(radius) result(area)
        double precision, intent(in) :: radius
        double precision :: area
        area = PI*radius*radius
    end function circle_area

    function circle_circumference(radius) result(circumference)
        double precision, intent(in) :: radius
        double precision :: circumference
        circumference = 2.0d0*PI*radius
    end function circle_circumference
end module geometry
