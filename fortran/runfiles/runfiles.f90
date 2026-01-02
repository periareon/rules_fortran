!> Runfiles lookup library for Bazel-built Fortran binaries and tests.
!>
!> Usage:
!>   1. Add @rules_fortran//fortran/runfiles to your deps:
!>
!>        fortran_binary(
!>            name = "my_binary",
!>            ...
!>            deps = ["@rules_fortran//fortran/runfiles"],
!>        )
!>
!>   2. USE the module and locate runfiles:
!>
!>        use runfiles
!>        type(runfiles_t) :: rf
!>        character(len=512) :: err
!>        character(len=:), allocatable :: path
!>        logical :: ok
!>
!>        call runfiles_create(rf, err, ok)  ! or runfiles_create_for_test
!>        if (.not. ok) stop 'cannot find runfiles'
!>
!>        path = rf%rlocation('my_workspace/data/input.txt')
!>        ! ... use path ...
!>
!>        call rf%destroy()
module runfiles
    use iso_c_binding
    implicit none
    private

    integer, parameter :: RF_BUF_LEN = 4096

    type, public :: runfiles_t
        private
        type(c_ptr) :: handle = c_null_ptr
    contains
        procedure :: rlocation => runfiles_rlocation
        procedure :: destroy => runfiles_destroy
    end type runfiles_t

    public :: runfiles_create
    public :: runfiles_create_for_test

    interface
        function c_rf_create(argv0, error_buf, error_buf_len) &
                result(ptr) bind(C, name='rf_create')
            import :: c_ptr, c_char, c_int
            character(kind=c_char), intent(in) :: argv0(*)
            character(kind=c_char), intent(out) :: error_buf(*)
            integer(c_int), value, intent(in) :: error_buf_len
            type(c_ptr) :: ptr
        end function c_rf_create

        function c_rf_create_for_test(error_buf, error_buf_len) &
                result(ptr) bind(C, name='rf_create_for_test')
            import :: c_ptr, c_char, c_int
            character(kind=c_char), intent(out) :: error_buf(*)
            integer(c_int), value, intent(in) :: error_buf_len
            type(c_ptr) :: ptr
        end function c_rf_create_for_test

        function c_rf_rlocation(rf, path, result_buf, result_buf_len) &
                result(length) bind(C, name='rf_rlocation')
            import :: c_ptr, c_char, c_int
            type(c_ptr), value, intent(in) :: rf
            character(kind=c_char), intent(in) :: path(*)
            character(kind=c_char), intent(out) :: result_buf(*)
            integer(c_int), value, intent(in) :: result_buf_len
            integer(c_int) :: length
        end function c_rf_rlocation

        subroutine c_rf_free(rf) bind(C, name='rf_free')
            import :: c_ptr
            type(c_ptr), value, intent(in) :: rf
        end subroutine c_rf_free
    end interface

contains

    !> Create a Runfiles instance for use from fortran_binary rules.
    !>
    !> Reads RUNFILES_MANIFEST_FILE and RUNFILES_DIR environment variables,
    !> falling back to argv0-based discovery.
    subroutine runfiles_create(rf, error, ok)
        type(runfiles_t), intent(out) :: rf
        character(len=*), intent(out) :: error
        logical, intent(out) :: ok

        character(len=RF_BUF_LEN) :: argv0
        character(kind=c_char) :: c_error(RF_BUF_LEN)
        character(kind=c_char) :: c_argv0(RF_BUF_LEN)
        integer :: argv0_len, i

        call get_command_argument(0, argv0, argv0_len)

        do i = 1, min(argv0_len, RF_BUF_LEN - 1)
            c_argv0(i) = argv0(i:i)
        end do
        c_argv0(min(argv0_len, RF_BUF_LEN - 1) + 1) = c_null_char

        c_error(1) = c_null_char
        rf%handle = c_rf_create(c_argv0, c_error, int(RF_BUF_LEN, c_int))

        if (c_associated(rf%handle)) then
            ok = .true.
            error = ' '
        else
            ok = .false.
            call c_buf_to_f_string(c_error, RF_BUF_LEN, error)
        end if
    end subroutine runfiles_create

    !> Create a Runfiles instance for use from fortran_test rules.
    !>
    !> Reads RUNFILES_MANIFEST_FILE and TEST_SRCDIR environment variables.
    subroutine runfiles_create_for_test(rf, error, ok)
        type(runfiles_t), intent(out) :: rf
        character(len=*), intent(out) :: error
        logical, intent(out) :: ok

        character(kind=c_char) :: c_error(RF_BUF_LEN)

        c_error(1) = c_null_char
        rf%handle = c_rf_create_for_test(c_error, int(RF_BUF_LEN, c_int))

        if (c_associated(rf%handle)) then
            ok = .true.
            error = ' '
        else
            ok = .false.
            call c_buf_to_f_string(c_error, RF_BUF_LEN, error)
        end if
    end subroutine runfiles_create_for_test

    !> Resolve a runfile path.
    !>
    !> Returns the runtime path to the given runfile, or an empty string
    !> if the runfile cannot be found.
    function runfiles_rlocation(self, path) result(resolved)
        class(runfiles_t), intent(in) :: self
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: resolved

        character(kind=c_char) :: c_path(RF_BUF_LEN)
        character(kind=c_char) :: c_result(RF_BUF_LEN)
        integer(c_int) :: length
        integer :: i, path_len

        if (.not. c_associated(self%handle)) then
            resolved = ''
            return
        end if

        path_len = len_trim(path)
        if (path_len >= RF_BUF_LEN) then
            resolved = ''
            return
        end if

        do i = 1, path_len
            c_path(i) = path(i:i)
        end do
        c_path(path_len + 1) = c_null_char

        c_result(1) = c_null_char
        length = c_rf_rlocation(self%handle, c_path, c_result, &
                                int(RF_BUF_LEN, c_int))

        if (length > 0) then
            allocate(character(len=length) :: resolved)
            do i = 1, length
                resolved(i:i) = c_result(i)
            end do
        else
            resolved = ''
        end if
    end function runfiles_rlocation

    !> Free the underlying Runfiles handle.
    subroutine runfiles_destroy(self)
        class(runfiles_t), intent(inout) :: self
        if (c_associated(self%handle)) then
            call c_rf_free(self%handle)
            self%handle = c_null_ptr
        end if
    end subroutine runfiles_destroy

    ! -- Internal helpers --

    subroutine c_buf_to_f_string(c_buf, c_buf_len, f_str)
        character(kind=c_char), intent(in) :: c_buf(*)
        integer, intent(in) :: c_buf_len
        character(len=*), intent(out) :: f_str
        integer :: i

        f_str = ' '
        do i = 1, min(c_buf_len, len(f_str))
            if (c_buf(i) == c_null_char) exit
            f_str(i:i) = c_buf(i)
        end do
    end subroutine c_buf_to_f_string

end module runfiles
