module ops_mod
    use types_mod, only: point_t
    implicit none

contains
    function translate_point(p, dx, dy) result(translated)
        type(point_t), intent(in) :: p
        double precision, intent(in) :: dx, dy
        type(point_t) :: translated

        translated%x = p%x + dx
        translated%y = p%y + dy
    end function translate_point
end module ops_mod
