module prescribed_cloud

!-------------------------------------------------------------------------- 
! Purpose:
!
! Reads cloud-related fields, puts the them into the physics buffer for use
! by radiation
! 
!--------------------------------------------------------------------------

  use shr_kind_mod, only : r8 => shr_kind_r8
  use abortutils,   only : endrun
  use spmd_utils,   only : masterproc
  use tracer_data,  only : trfld, trfile
  use cam_logfile,  only : iulog

  implicit none
  private
  save 

  type(trfld), pointer :: fields(:)
  type(trfile)         :: file

  public :: prescribed_cloud_init
  public :: prescribed_cloud_adv
  public :: write_prescribed_cloud_restart
  public :: read_prescribed_cloud_restart
  public :: has_prescribed_cloud
  public :: prescribed_cloud_register
  public :: init_prescribed_cloud_restart
  public :: prescribed_cloud_readnl

  logical :: has_prescribed_cloud = .false.
!! JGOmod
!  integer          , parameter :: nflds             = 10
!  character(len=16), parameter :: cloud_name(nflds) = (/'DEI_in'   ,'MU_in'  ,'LAMBDAC_in' ,'ICIWP_in' ,'ICLWP_in' ,'DES_in' , &
!                                                        'ICSWP_in' ,'CLD_in' ,'CLDLIQ_in'  ,'CLDICE_in'  /)
!
!  character(len=16)  :: fld_name(nflds)             = (/'DEI_rad'  ,'MU_rad' ,'LAMBDAC_rad','ICIWP_rad','ICLWP_rad','DES_rad', &
!                                                        'ICSWP_rad','CLD_rad','CLDLIQ_rad' ,'CLDICE_rad' /)
  integer          , parameter :: nflds             = 8
  character(len=16), parameter :: cloud_name(nflds) = (/'DEI_in'   ,'MU_in'  ,'LAMBDAC_in' ,'ICIWP_in' ,'ICLWP_in' ,'DES_in' , &
                                                        'ICSWP_in' ,'CLD_in' /)

  character(len=16)  :: fld_name(nflds)             = (/'DEI_rad'  ,'MU_rad' ,'LAMBDAC_rad','ICIWP_rad','ICLWP_rad','DES_rad', &
                                                        'ICSWP_rad','CLD_rad'/)
!! JGOmod
  character(len=256) :: filename                    = ' '
  character(len=256) :: filelist                    = ' '
  character(len=256) :: datapath                    = ' '
  character(len=32)  :: data_type                   = 'SERIAL'
  logical            :: rmv_file                    = .false.
  integer            :: cycle_yr                    = 0
  integer            :: fixed_ymd                   = 0
  integer            :: fixed_tod                   = 0
  character(len=32)  :: specifier(nflds)            = ''

contains

!-------------------------------------------------------------------
!-------------------------------------------------------------------
  subroutine prescribed_cloud_register()
    use ppgrid,         only: pver, pcols
    use physics_buffer, only : pbuf_add_field, dtype_r8

    integer :: i,idx

    if (has_prescribed_cloud) then
       do i = 1,nflds
          call pbuf_add_field(cloud_name(i),'physpkg',dtype_r8,(/pcols,pver/),idx)
       enddo
    endif

  endsubroutine prescribed_cloud_register

!-------------------------------------------------------------------
!-------------------------------------------------------------------
  subroutine prescribed_cloud_init()

    use tracer_data, only : trcdata_init

    implicit none

    integer :: ndx, istat, i
    
    if ( has_prescribed_cloud ) then
       if ( masterproc ) then
          write(iulog,*) 'cloud is prescribed in :'//trim(filename)
       endif
    else
       return
    endif

    do i = 1,nflds
       specifier(i) = trim(cloud_name(i))//':'//trim(fld_name(i))
    end do


    allocate(file%in_pbuf(size(specifier)))
    file%in_pbuf(:) = .true.
    file%stepTime   = .true.
    file%xyzint     = .false.
    call trcdata_init( specifier, filename, filelist, datapath, fields, file, &
                       rmv_file, cycle_yr, fixed_ymd, fixed_tod, data_type)

  end subroutine prescribed_cloud_init

!-------------------------------------------------------------------
!-------------------------------------------------------------------
subroutine prescribed_cloud_readnl(nlfile)

   use namelist_utils,  only: find_group_name
   use units,           only: getunit, freeunit
   use mpishorthand

   character(len=*), intent(in) :: nlfile  ! filepath for file containing namelist input

   ! Local variables
   integer :: unitn, ierr
   character(len=*), parameter :: subname = 'prescribed_cloud_readnl'

   character(len=256) :: prescribed_cloud_file
   character(len=256) :: prescribed_cloud_filelist
   character(len=256) :: prescribed_cloud_datapath
   character(len=32)  :: prescribed_cloud_type
   logical            :: prescribed_cloud_rmfile
   integer            :: prescribed_cloud_cycle_yr
   integer            :: prescribed_cloud_fixed_ymd
   integer            :: prescribed_cloud_fixed_tod

   namelist /prescribed_cloud_nl/ &
      prescribed_cloud_file,      &
      prescribed_cloud_filelist,  &
      prescribed_cloud_datapath,  &
      prescribed_cloud_type,      &
      prescribed_cloud_rmfile,    &
      prescribed_cloud_cycle_yr,  &
      prescribed_cloud_fixed_ymd, &
      prescribed_cloud_fixed_tod      
   !-----------------------------------------------------------------------------

   ! Initialize namelist variables from local module variables.
   prescribed_cloud_file     = filename
   prescribed_cloud_filelist = filelist
   prescribed_cloud_datapath = datapath
   prescribed_cloud_type     = data_type
   prescribed_cloud_rmfile   = rmv_file
   prescribed_cloud_cycle_yr = cycle_yr
   prescribed_cloud_fixed_ymd= fixed_ymd
   prescribed_cloud_fixed_tod= fixed_tod

   ! Read namelist
   if (masterproc) then
      unitn = getunit()
      open( unitn, file=trim(nlfile), status='old' )
      call find_group_name(unitn, 'prescribed_cloud_nl', status=ierr)
      if (ierr == 0) then
         read(unitn, prescribed_cloud_nl, iostat=ierr)
         if (ierr /= 0) then
            call endrun(subname // ':: ERROR reading namelist')
         end if
      end if
      close(unitn)
      call freeunit(unitn)
   end if

#ifdef SPMD
   ! Broadcast namelist variables
   call mpibcast(prescribed_cloud_file,     len(prescribed_cloud_file),     mpichar, 0, mpicom)
   call mpibcast(prescribed_cloud_filelist, len(prescribed_cloud_filelist), mpichar, 0, mpicom)
   call mpibcast(prescribed_cloud_datapath, len(prescribed_cloud_datapath), mpichar, 0, mpicom)
   call mpibcast(prescribed_cloud_type,     len(prescribed_cloud_type),     mpichar, 0, mpicom)
   call mpibcast(prescribed_cloud_rmfile,   1, mpilog,  0, mpicom)
   call mpibcast(prescribed_cloud_cycle_yr, 1, mpiint,  0, mpicom)
   call mpibcast(prescribed_cloud_fixed_ymd,1, mpiint,  0, mpicom)
   call mpibcast(prescribed_cloud_fixed_tod,1, mpiint,  0, mpicom)
#endif

   ! Update module variables with user settings.
   filename   = prescribed_cloud_file
   filelist   = prescribed_cloud_filelist
   datapath   = prescribed_cloud_datapath
   data_type  = prescribed_cloud_type
   rmv_file   = prescribed_cloud_rmfile
   cycle_yr   = prescribed_cloud_cycle_yr
   fixed_ymd  = prescribed_cloud_fixed_ymd
   fixed_tod  = prescribed_cloud_fixed_tod

   ! Turn on prescribed cloud if user has specified an input dataset.
   if (len_trim(filename) > 0 ) has_prescribed_cloud = .true.

end subroutine prescribed_cloud_readnl

!-------------------------------------------------------------------
!-------------------------------------------------------------------
  subroutine prescribed_cloud_adv( state, pbuf2d)

    use tracer_data,  only : advance_trcdata
    use physics_types,only : physics_state
    use ppgrid,       only : begchunk, endchunk
    use ppgrid,       only : pcols, pver
    use string_utils, only : to_lower, GLC
    use physconst,    only : mwdry                ! molecular weight dry air ~ kg/kmole
    
    use physics_buffer, only : physics_buffer_desc, pbuf_get_chunk, pbuf_get_field, pbuf_set_field

    implicit none

    type(physics_state), intent(in)    :: state(begchunk:endchunk)                 
    
    type(physics_buffer_desc), pointer :: pbuf2d(:,:)

    if( .not. has_prescribed_cloud ) return

    call advance_trcdata( fields, file, state, pbuf2d )

  end subroutine prescribed_cloud_adv

!-------------------------------------------------------------------

  subroutine init_prescribed_cloud_restart( piofile )
    use pio, only : file_desc_t
    use tracer_data, only : init_trc_restart
    implicit none
    type(file_desc_t),intent(inout) :: pioFile     ! pio File pointer

    call init_trc_restart( 'prescribed_cloud', piofile, file )

  end subroutine init_prescribed_cloud_restart
!-------------------------------------------------------------------
  subroutine write_prescribed_cloud_restart( piofile )
    use tracer_data, only : write_trc_restart
    use pio, only : file_desc_t
    implicit none

    type(file_desc_t) :: piofile

    call write_trc_restart( piofile, file )

  end subroutine write_prescribed_cloud_restart

!-------------------------------------------------------------------
  subroutine read_prescribed_cloud_restart( pioFile )
    use tracer_data, only : read_trc_restart
    use pio, only : file_desc_t
    implicit none

    type(file_desc_t) :: piofile
    
    call read_trc_restart( 'prescribed_cloud', piofile, file )

  end subroutine read_prescribed_cloud_restart
!================================================================================================

end module prescribed_cloud

