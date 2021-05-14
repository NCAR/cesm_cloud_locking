;***********************************************************
; Changes the value of variable 'date' within
; cloud locking data files. Designed to be invoked interactively
; as a means of manually adjusting the 'date' value. For example,
; this script can be used to reset the date value if a test run
; with cloud locking had previously incremented the year of 'date'
; beyond a year-0 start. If the test run was 2 years long,
; the user could set subtractYears = 2 below and the script
; would subrtact 2 years from the 'date' variable within each
; cloud locking data file, effectively resetting the years back
; to a Year 0 start.
; This script is NOT designed to be used via POSTRUN_SCRIPT
; in env_run.xml.
;***********************************************************

; Auhtor:  Jim Benedict jjb278@gmail.com
; Origin:  22 Mar 2018
; Modified:
;     

load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"  
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"  

; User-defined variables
cloudDataPath = "/glade/scratch/eleanorm/clockinput/dataFiles/B1850_clock_test"
subtractYears = -1   ; how many years to subtract from current year in cloud data fles?

begin

;  print("cloudDataPath: " + cloudDataPath)
  fileNames = systemfunc("ls -1 " + cloudDataPath + "/*.nc")
  
  do i = 0,dimsizes(fileNames)-1
    print("Reseting date in file: " + fileNames(i) + "...")
    f = addfile(fileNames(i), "w")
    dateNew = f->date
;    yrNow   = toint(floor(tofloat(dateNew)/10000.))
;    mmddNow = dateNew - (yrNow * 10000)
;    dateNew = (/ (reset2year * 10000) + mmddNow /)   ; reset 'date' year stamp to [reset2year]
;    dateNew = (/ dateNew + (2 * 10000) /)   ; used with case B1850_c201_CTL_F
    dateNew = (/ dateNew - (subtractYears * 10000) /)   ; roll back 'date' year stamp by [subtractYears] years
    f->date = dateNew
    delete(dateNew)
  end do
    
end
