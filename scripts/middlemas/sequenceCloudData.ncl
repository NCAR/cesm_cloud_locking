; This script takes raw CESM2 history
;   files containing 2-hourly cloud-related data and resequences them
;   into new daily files and creates symbolic links to those files.  The new files and
;   symlinks are intended for use as inputs to "cloud-locking" simulations.
;
; DISCLAIMER:  THIS SCRIPT MAY NOT BE ERROR-FREE.  ALTHOUGH WE HAVE CONFIDENCE THAT MOST
;              OPERATIONS IN THIS SCRIPT WORK, WE HAVE NOT ROBUSTLY TESTED EVERY
;              POSSIBLE OPTION.  THE USER IS ULTIMATELY RESPONSIBLE FOR ENSURING THAT THE
;              SCRIPT OPERATES AS INTENDED.  IF A BUG IS SUSPECTED, PLEASE CONTACT US
;              VIA GITHUB AND WE WILL CORRECT IT.
;
;
; !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! 
; IMPORTANT: THIS SCRIPT MUST BE RUN MANUALLY FIRST, BEFORE
;     THE CLOUD LOCKED RUN IS STARTED, IN ORDER TO SET UP THE PROPER DATA FILES.
;     IT MAY ALSO NEED TO BE RUN MANUALLY PRIOR TO
;     CONTINUING A RUN IF FOR ANY REASON THE 'DATE' VARIABLES IN THE STAGED CLOUD DATA
;     (in [dirProcData]) AND SYMLINKS (IN [dirSymLinks]) DO NOT MATCH THE EXPECTED RESTART
;     DATE OF THE RUN ABOUT TO BE RESTARTED.
;
;     TO RUN MANUALLY PRIOR TO BEGINNING A CLOUD-LOCKED SIMULATION, DO THE
;     FOLLOWING:
;     * Best to remove all files in [dirProcData], the processed data directory
;     * Best to remove symbolic links (in [dirSymLinks]) to the processed data 
;     * Modify and use csh script run_sequenceCloudData to submit script to
;       NCAR-Casper to run in batch mode. This is needed because the
;       script will take >1 hr to run interactively and may "time out" of a Cheyenne
;       login node.
;     * Once the intial run of the script is completed and the data and symlinks are
;       correctly staged, the cloud-locked simulation can be submitted.
; !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
;
;
; Main assumptions/requirements/defined setup of this script:
;   (1) noleap calendar used for files in raw cloud data pool
;   (2) processed data directory contains 1 yr of data (not multiple years)
;   (3) all raw cloud data files span 1 day and have the same number of time steps in each
;   (4) the raw cloud data files contain variables, at sub-daily resolution, defined in
;       'cldVarNames' below
;   (5) the first year of prescribed cloud data must be 0001 or after (cannot be 0000)
;   (6) user's operating system has access to standard bash commands 'rename' and 'date'
;
;-------------------------------------------------------------------
; Author:  Jim Benedict
; Origin date:  Apr 2018
; Modified:
;   19 Sep 2018, JB:
;         * Adapted script to handle 3-yr of raw data, and to
;           randomize the time steps.
;    4 Jun 2020, JB:
;         * Expanded capability to handle a data pool size of N years instead of
;           hard-coding 3 years.  Note that the staged prescribed-cloud data directory in
;           'dirProcData/[CASE]' will still house only 1 year of data.
;         * Removed hard-coded "h1", allow user to define arbitrary CAM history file
;           stream 'hTape' associated with cloud data files
;         * Added wallclock time stamp (printed at end of log)
;         * Removed obsolete commented-out code
; 
;-------------------------------------------------------------------


load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"

begin

; ----------------------------------------------------------------------------------------
; -------------------    (Begin) USER-defined variables    -------------------------------

cloudLockYearStart = 1       ; Year in which cloud locking production run will start (most likely "1", but could be changed to continue an existing run)

useSymLinks     = True       ; Recommended setting:  True
                             ;   Option to use symlinks to data files, or the actual data files themselves
                             ;   Note: If useSymLinks = False, the staged data file names will be -renamed-
                             ;         to include the file sequence number

iseqBeg         = 1          ; file sequencing begins with this number (should be set to "1")

hTape           = 1          ; CAM history file stream associated with existing raw cloud
                             ;   property files to be resequenced and staged


; - - - - - - - - - - - - - - - - -

dirRawDataPool = "/glade/p/univ/umia0021/B1850_c201_cloudLockDat_Yr20_22/run"
dirProcBase    = "/glade/p/univ/umia0021/cloudLockData"
dirProcData    = dirProcBase+"/dataFiles/B1850_c201_CTL_NyrTest"   ; processed data directory. 
; ^^ The name of the folder inside dataFiles should *not* be the rawDataCaseName because 
; later on, a unix command will replace rawDataCaseName with procDataCaseName, which will
; lead to an error if the folder is also titled rawDataCasename

rawDataCaseName   = "B1850_c201_cloudLockDat_Yr20_22"         ; case name tag for raw data files (must match dirRawDataPool)
procDataCaseName  = "B1850_c201_lockDat_Yr20_22_NyrTest"      ; name tag for processed data files... A "_rand", "_seq", or "_match" suffix will be appended depending on type of cloud ordering
                                              ; *** IF EXTENDING AND EXISTING RUN, ENSURE THAT procDataCaseName MATCHES prescribed_cloud_file IN THE CASE'S USER_NL_CAM (MINUS THE "_random" or "_seq" etc. suffix ***)
clockCaseName     = "B1850_c201_CLOCK_NyrTest"   ; case name for corresponding CESM simulation that -uses- the prescribed cloud data



;dirRawDataPool = "/glade/scratch/eleanorm/clockinput/rawData/B1850_clockoutput"
;dirProcBase    = "/glade/scratch/eleanorm/clockinput"
;dirProcData    = dirProcBase+"/dataFiles/B1850_clock_test"   ; processed data directory. 
;; ^^ The name of the folder inside dataFiles should *not* be the rawDataCaseName because 
;; later on, a unix command will replace rawDataCaseName with procDataCaseName, which will
;; lead to an error if the folder is also titled rawDataCasename
;
;rawDataCaseName   = "B1850_clockoutput"         ; case name tag for raw data files (must match dirRawDataPool)
;procDataCaseName  = "B1850_lockDat_yr1_3"      ; name tag for processed data files... A "_rand", "_seq", or "_match" suffix will be appended depending on type of cloud ordering
;                                              ; *** IF EXTENDING AND EXISTING RUN, ENSURE THAT procDataCaseName MATCHES prescribed_cloud_file IN THE CASE'S USER_NL_CAM (MINUS THE "_random" or "_seq" etc. suffix ***)
;clockCaseName     = "B1850_clocktest_yr1_3"   ; case name for corresponding CESM simulation that -uses- the prescribed cloud data



dirSymLinks = dirProcBase+"/symLinks/"+rawDataCaseName
dirLog = dirProcBase+"/logFiles/"+rawDataCaseName

; The variables that will be subbed into the prescribed cloud data file templates
cldVarNames = (/ "DEI_rad","MU_rad","LAMBDAC_rad","ICIWP_rad","ICLWP_rad","DES_rad", \
                 "ICSWP_rad","CLD_rad","CLDFSNOW_rad","PS"/)
;;cldVarNames = (/ "DEI_rad","MU_rad","LAMBDAC_rad","ICIWP_rad","ICLWP_rad","DES_rad", \
;;                 "ICSWP_rad","CLD_rad","CLDFSNOW_rad","PS","Q_rad" /)

; - - - - - - - - - - - - - - - - -

; Switches that determines whether and how cloud data will be randomized, sequential, or matched to a previous run
seqType = "random"
                         ; options: random, sequential, matchR... option "matchS" not supported at this time
                         ;   - random:     chooses random year from raw data pool (slow, ~90 mins on 1 node)
                         ;   - sequential: repeats same single year of cloud data over and over (fast, < 10 mins on 1 node)
                         ;   - matchR:     matches date sequence from previous RANDOMIZED simulation (slow, ~90 mins on 1 node)
                         ;   - matchS:     matches date sequence from previous SEQUENTIAL simulation (fast, < 10 mins on 1 node)
;;sequentialYr = "0022"  ; (string) Only used if seqType = sequential.  Of the years of data
                         ;          within the raw data pool, the selected year to be cycled over.
                         ;          Must be of the form "yyyy" (like "0020", not "20")
matchRunLog  = dirLog    ; (string) Only used if seqType = matchR.  Path to where logfile of cloud data sequencing exists

if(seqType .eq. "matchR") then
  matchLogFirstFile = matchRunLog + "/sequenceLog."+clockCaseName+".YR0001"  ; do NOT include date stamp
end if
if(seqType .eq. "matchS") then
  ;matchLogFirstFile = matchRunLog + "/sequenceLog.B1850_c201_CLOCK22.YR0001.2018-10-10_111959.txt"
  print("seqType option 'matchS' not supported at this time. Exiting.")
  exit
end if
; -------------------    (End) USER-defined variables    -------------------------------
; ----------------------------------------------------------------------------------------



;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;------------------- BEGIN MAIN SCRIPT -----------------------------
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

; ----------------------------------------------------------------------------------------
; Prep work

; Start wallclock timer
wcStrt = systemfunc("date")

cr = inttochar(10)   ; designator for carriage return when printing

; Set seed for random number generator
rseed1 = toint(systemfunc(" date +%s"))   ; returns seconds since 1970-01-01
print("rseed1: " + rseed1)
srand(rseed1)

nvar = dimsizes(cldVarNames)

if(seqType .eq. "random") then
  procDataCaseName = procDataCaseName + "_rand"
end if
if(seqType .eq. "sequential") then
  procDataCaseName = procDataCaseName + "_seq"
end if
if(seqType .eq. "matchR") then
  procDataCaseName = procDataCaseName + "_matchR"
end if
;;if(seqType .eq. "matchS") then
;;  procDataCaseName = procDataCaseName + "_matchS"   ; not currently supported
;;end if

; Check if directory housing symbolic links (dirSymLinks) exists... if not, create it
if(.not. fileexists(dirSymLinks)) then   ; NCL's fileexists can also be used to check the existence of directories
  system("mkdir " + dirSymLinks)
end if

; Check if logfile directory (dirLog) exists... if not, create it
if(.not. fileexists(dirLog)) then   ; NCL's fileexists can also be used to check the existence of directories
  system("mkdir " + dirLog)
end if


; ----------------------------------------------------------------------------------------
; Check if sub-daily raw cloud property data exist
cmd = "ls -1 " + dirRawDataPool + "/" + rawDataCaseName + ".cam.h" + hTape + ".*.nc"
fnamesRawDataAll = systemfunc(cmd)
if(all(ismissing(fnamesRawDataAll))) then
  print("Raw data files not found in: " + dirRawDataPool)
  status_exit(1)
else
  print("Number of raw data files found in data pool: " + dimsizes(fnamesRawDataAll))
end if

; Define date stamps from names of raw data files
yyyyRaw = str_get_cols(fnamesRawDataAll,-19,-16)   ; (string) year stamp of all raw data files
mmRaw   = str_get_cols(fnamesRawDataAll,-14,-13)   ; (string) month
ddRaw   = str_get_cols(fnamesRawDataAll,-11,-10)   ; (string) day
nRawFiles = dimsizes(yyyyRaw)                      ; number of raw data files in raw data pool

nRawYrs = nRawFiles / 365   ; "noleap" calendar assumption here


; ----------------------------------------------------------------------------------------
; Check if processed/sequenced cloud data files already exist... if so, note year stamp
cmd = "ls -1 " + dirProcData + "/" + procDataCaseName + "*.cam.h" + hTape + ".*.nc"
fnamesProcDataAll = systemfunc(cmd)
if(all(ismissing(fnamesProcDataAll))) then
  haveProcData = False
  delete(fnamesProcDataAll)
  print(cr + "No processed data files currently exist in directory: " + dirProcData)
  print("Will CREATE new time sequencing for processed data files.")
else
  print(cr + "Processed data files currently exist in directory: " + dirProcData)
  print("Proceeding...")
  haveProcData = True
  nProcFiles   = dimsizes(fnamesProcDataAll)               ; should be 367 (365 days plus the 2 buffer days)
  dateProc     = str_get_cols(fnamesProcDataAll,-19,-10)   ; date string (YYYY-MM-DD) of each processed file name
  yyyyProc     = str_get_cols(dateProc,0,3)       ; (string) year stamp of all processed data files
  iyyyyProc    = toint(yyyyProc)                           ; (integer) year stamp of all processed data files
  currentYr    = yyyyProc(1)                               ; (string) year of "current" year, skipping first buffer day (index 0)
  icurrentYr   = toint(currentYr)                          ; (integer) year of "current" year, skipping first buffer day (index 0)

  ; Record "current year" of processed data files -- read index "1" (current year) rather
  ;   than "0" (previous year, in case "buffer" days added)
  ; This is *only* used for print statement on final lines of this script
  fTmp  = addfile(fnamesProcDataAll(1), "r")
  yrOld = toint(floor(tofloat(fTmp->date(0))/10000.))
  delete(fTmp)

end if

; ----------------------------------------------------------------------------------------
; If no processed data files exist yet, copy over a year of files from the raw
;  data pool to the processed data directory to serve as file templates
if(.not. haveProcData) then
  yyyyFirst = yyyyRaw(0)    ; YYYY string matching the FIRST year of the raw data files
  if(seqType .eq. "sequential" .and. isvar("sequentialYr")) then
    yyyyFirst = sequentialYr
  end if
  
  ; Check if dirProcData exists... if not, create it
  if(.not. fileexists(dirProcData)) then   ; NCL's fileexists can also be used to check the existence of directories
    system("mkdir " + dirProcData)
  end if
  
  cmd = "cp -p " + dirRawDataPool + "/" + rawDataCaseName + ".cam.h" + hTape + "." + \
        yyyyFirst + "*.nc " + dirProcData
  print(cr + "Copying year " + yyyyFirst + \
        " data from raw data pool to processed data directory, as file templates...")
  print("Command is: " + cmd)
  system(cmd)
    
  ; Rename case name, to help distinguish raw data from processed data
  cmd        = "ls -1 " + dirProcData + "/" + rawDataCaseName + ".cam.h" + hTape + ".*.nc"
  fNamesTmp  = systemfunc(cmd)                   ; all processed data file names
  cmd        = "rename " + rawDataCaseName + " " + procDataCaseName + " " + \
               dirProcData + "/" + rawDataCaseName + ".cam.h" + hTape + ".*.nc"
  print(cr + "Renaming processed-data case names (within file name) from " + \
        rawDataCaseName + " to " + procDataCaseName + "...")
  print("Command is: " + cmd)
  system(cmd)
  print("Renaming successful!")
  
  ; ----------   BEGIN BUFFER SECTION   ------------------
  ; Also add buffer template files before the first file and after the last file:
  ;   Copy YYYY-12-31 to (YYYY-1)-12-31, and YYYY-01-01 to (YYYY+1)-01-01, where
  ;   "YYYY" is year string of selected year (first year of data from raw data pool)
  cmd        = "ls -1 " + dirProcData + "/" + procDataCaseName + ".cam.h" + hTape + ".*.nc"
  fNamesTmp  = systemfunc(cmd)                   ; all processed data file names (FULL PATH)
  nProcFiles = dimsizes(fNamesTmp)               ; should be 367 (365 days plus the 2 buffer days)
  dateTmp    = str_get_cols(fNamesTmp,-19,-10)   ; date string (YYYY-MM-DD) of each processed file name
;  yyyyProc   = str_get_cols(dateTmp,0,3)         ; (string) year stamp of all processed data files
  
  mmddTmp    = "12-31"
  dateStrTmp = yyyyFirst + "-" + mmddTmp
  indTmp     = ind(dateTmp .eq. dateStrTmp)      ; index of processed data file with date stamp matching dateStrTmp
  a          = toint(yyyyFirst)
  dateStrRevised  = sprinti("%0.4i",(a-1)) + "-" + mmddTmp
  revisedFileName = str_sub_str(fNamesTmp(indTmp),dateStrTmp,dateStrRevised)
  cmd = "cp -p " + fNamesTmp(indTmp) + " " + revisedFileName   ; note: files names already contain FULL PATH
  print(cr + "Adding buffer template file (Dec 31 of previous year)...")
  print("Command is: " + cmd)
  system(cmd)
  delete([/mmddTmp,dateStrTmp,indTmp,a,dateStrRevised,revisedFileName/])
  
  mmddTmp    = "01-01"
  dateStrTmp = yyyyFirst + "-" + mmddTmp
  indTmp     = ind(dateTmp .eq. dateStrTmp)      ; index of processed data file with date stamp matching dateStrTmp
  a          = toint(yyyyFirst)
  dateStrRevised  = sprinti("%0.4i",(a+1)) + "-" + mmddTmp
  revisedFileName = str_sub_str(fNamesTmp(indTmp),dateStrTmp,dateStrRevised)
  cmd = "cp -p " + fNamesTmp(indTmp) + " " + revisedFileName   ; note: files names already contain FULL PATH
  print(cr + "Adding buffer template file (Jan 1 of next year)...")
  print("Command is: " + cmd)
  system(cmd)
  delete([/mmddTmp,dateStrTmp,indTmp,a,dateStrRevised,revisedFileName/])
  ; ----------   END BUFFER SECTION   ------------------
  
  ; Reassess processed data file directory (after two new buffer files were just been added)
  delete([/fNamesTmp,nProcFiles,dateTmp/])
  cmd = "ls -1 " + dirProcData + "/" + procDataCaseName + ".cam.h" + hTape + ".*.nc"
  fnamesProcDataAll = systemfunc(cmd)
  nProcFiles = dimsizes(fnamesProcDataAll)               ; should be 367 (365 days plus the 2 buffer days)
  dateProc   = str_get_cols(fnamesProcDataAll,-19,-10)   ; date string (YYYY-MM-DD) of each processed file name
  yyyyProc   = str_get_cols(dateProc,0,3)                ; (string) year stamp of all processed data files
  iyyyyProc  = toint(yyyyProc)                           ; (integer) year stamp of all processed data files
  currentYr  = yyyyProc(1)                               ; (string) year of "current" year, skipping first buffer day (index 0)
  icurrentYr = toint(currentYr)                          ; (integer) year of "current" year, skipping first buffer day (index 0)
  
  ; Record "current year" of processed data files -- read index "1" (current year) rather
  ;   than "0" (previous year, in case "buffer" days added)
  ; This is *only* used for print statement on final lines of this script
  fTmp  = addfile(fnamesProcDataAll(1), "r")
  yrOld = toint(floor(tofloat(fTmp->date(0))/10000.))
  delete(fTmp)
  
  ; Roll back 'date' of all new template files to [cloudLockStartYear] -- best to loop
  ;   through files indivdually
  ;  * For first file (a buffer file, 31 Dec of "previous" year), roll back date to
  ;    [cloudLockYearStart]-1
  ;  * For last file (buffer file, 1 Jan of "next" year), roll back date to
  ;    [cloudLockYearStart]+1
  print(cr + "Rolling back 'date' variable for each template file...")
  do i = 0,nProcFiles-1
    f = addfile(fnamesProcDataAll(i), "w")
    dateNew = f->date
    if(iyyyyProc(i) .eq. (icurrentYr-1)) then
      dateNew = (/dateNew - ((icurrentYr-cloudLockYearStart+1)*10000)/)   ; roll back 'date' year to [cloudLockYearStart]-1
    else if(iyyyyProc(i) .eq. (icurrentYr+1)) then
      dateNew = (/dateNew - ((icurrentYr-cloudLockYearStart-1)*10000)/)   ; roll back 'date' year to [cloudLockYearStart]+1
    else
      dateNew = (/dateNew - ((icurrentYr-cloudLockYearStart)*10000)/)   ; roll back 'date' year to [cloudLockYearStart]
    end if
    end if
    print( sprinti("%10i",f->date(0)) + " -> " + sprinti("%10i",dateNew) + "  " + fnamesProcDataAll(i) )
    f->date = dateNew
    delete(dateNew)
  end do    ; end i loop through all processed files
  
  ; At this time, we should have 367 daily files within the processed data directory.
  ;   These files should be labeled as follows:
  ;   (1)   [procDataCaseName].cam.h*.[currentYr-1]-12-31.*.nc  date = [cloudLockYearStart-1]1231, final 'date' entry = [cloudLockYearStart]0101
  ;   (2)   [procDataCaseName].cam.h*.[currentYr]-01-01.*.nc    date = [cloudLockYearStart]0101, final 'date' entry = [cloudLockYearStart]0102
  ;   ...
  ;   (366) [procDataCaseName].cam.h*.[currentYr]-12-31.*.nc    date = [cloudLockYearStart]1231, final 'date' entry = [cloudLockYearStart+1]0101
  ;   (367) [procDataCaseName].cam.h*.[currentYr+1]-01-01.*.nc  date = [cloudLockYearStart+1]0101, final 'date' entry = [cloudLockYearStart+1]0102
  
end if   ; if haveProcData was false (if script had to do one-time initial setup of processed data directory)

;exit   ; activate for testing initial staging of processed data


;; ----------------------------------------------------------------------------------------
;; A note on available metadata:  these variables are available to use, regardless of
;;   whether newly generated or pre-existing files resided in the processed data directory
;;
;;  fnamesProcDataAll = systemfunc(cmd)
;;  nProcFiles = dimsizes(fnamesProcDataAll)               ; should be 367 (365 days plus the 2 buffer days)
;;  dateProc   = str_get_cols(fnamesProcDataAll,-19,-10)   ; date string (YYYY-MM-DD) of each processed file name
;;  yyyyProc   = str_get_cols(fnamesProcDataAll,0,3)       ; (string) year stamp of all processed data files
;;  iyyyyProc  = toint(yyyyProc)                           ; (integer) year stamp of all processed data files
;;  currentYr  = yyyyProc(1)                               ; (string) year of "current" year, skipping first buffer day (index 0)
;;  icurrentYr = toint(currentYr)                          ; (integer) year of "current" year, skipping first buffer day (index 0)



; ========================================================================================
; RANDOM ORDERING (if seqType = "random")

if(seqType .eq. "random" .or. seqType .eq. "matchR") then

  ; --------------------------------------------------------------------------------------
  ; Setup for random number generator
  delta   = 0.00001       ; to be sure that rounding is correctly done (e.g., round(-0.5,3) = -1, not 0... and there is no file index -1)
  randMin = -0.5 + delta
  randMax = nRawYrs - 0.5 - delta              ; 
  con     = (randMax - randMin) / 32766.0      ; 32766.0 forces a 0.0 to 1.0 range
  fNum    = new(10000,"integer")               ; 10000 is just some arbitrarily large number,
                                               ;   but must be large enough to cover all time steps
                                               ;   of processed data files (e.g., if there are
                                               ;   367 processed data files and each file
                                               ;   contains 12 time steps for 2-hourly resolution,
                                               ;   then fNum must be at least 4404 in length)
  iRandN     = fNum                            ; saves generated random number
  timeRandN  = new(dimsizes(fNum),"string")    ; saves time stamp (yyyymmdd-sssss) associated with iRandN
  fNameRandN = timeRandN                       ; saves file name associated with iRandN
  
  ; ----------------------------------------------------------------------------------------
  ; If seqType = "matchR", retrieve current year of processed data files -- read index "1" (current year) rather
  ;   than "0" (previous year, in case "buffer" days have been added)
  ; This is used to read the correct logfile so the cloud data sequencing between original locked run and
  ;   matched locked run are the same
  if(seqType .eq. "matchR") then
    if(haveProcData) then
      fTmp    = addfile(fnamesProcDataAll(1), "r")
      yrMatch = toint(floor(tofloat(fTmp->date(0))/10000.)) + 1   ; have not yet increment dates in processed file
      delete(fTmp)
    else
      fTmp    = addfile(fnamesProcDataAll(1), "r")
      yrMatch = toint(floor(tofloat(fTmp->date(0))/10000.))   ; have already set file dates within processed data file
      delete(fTmp)
    end if
    
    ; Read corresponding logfile matching "yrMatch" to get cloud data integer sequence ONLY (not data)
    logFileMatch    = matchLogFirstFile
    logFileYrStr    = str_get_cols(logFileMatch,-4,-1)   ; (string) yyyy year associated with log file
    logFileYrStr    = "YR" + logFileYrStr                  ; (string) YRyyyy year tag associated with log file
    logFileYrStrNew = "YR" + sprinti("%0.4i",yrMatch)      ; revised YRyyyy string matching current year (yrMatch)
    logFileMatch    = str_sub_str(logFileMatch, logFileYrStr, logFileYrStrNew) + "*.txt"  ; this avoids having to specify filename time stamp
    print("Opening/reading the following logfile ONLY to get cloud sequence values (not yet data) for yrMatch = " + yrMatch + ":")
    logFileMatchUse = systemfunc("ls -1 " + logFileMatch)
    print("     " + logFileMatchUse)
    nhdr          = 1        ; number of rows of header
    data          = readAsciiTable(logFileMatchUse,1,"string",(/nhdr/))  ; "1": read data as a single column, then extract fields...
                         ; ...but data is then (time, 1), hence the use of data(:,0) for, e.g., logYrValStr below
    logSeqNumStr  = str_get_field(data(:,0), 1, " ")    ; (string) single dimension
    logYrValStr   = str_get_field(data(:,0), 2, " ")    ; (string) 4404 entries: 365 + 2 (buffer) daily files * 12 time steps per file
    logValYrInt   = stringtointeger(logYrValStr)        ; integer values of logYrValStr
    logDateStr    = str_get_field(data(:,0), 3, " ")
    logSrcFileStr = str_get_field(data(:,0), 4, " ")
  end if
  
  ; --------------------------------------------------------------------------------------
  ; Recursively examine each day and resequence processed data files

  mmddRawAll = str_get_cols(fnamesRawDataAll,-14,-10)          ; mm-dd format for ALL raw data files


  tcnt = 0    ; total time step counter
  do idate = 0,nProcFiles-1
;;;  do idate = 0,3        ; for testing only

    ; Open existing processed data file, to be used as template
    fProcCurrent = addfile(fnamesProcDataAll(idate), "w")
    nstepsDay = dimsizes(fProcCurrent->datesec)
  
    ; Open all files from the raw data pool that match the same month-day time stamp 
    mmddCurrent   = str_get_cols(fnamesProcDataAll(idate),-14,-10)  ; mm-dd format of current date
    indRawCurrent = ind(mmddRawAll .eq. mmddCurrent)                ; indices of raw data files matching current mm-dd date stamp
    fnamesRawCurrent = fnamesRawDataAll(indRawCurrent)              ; the names of the raw data files with dates matching current mm-dd date
    fRawN = addfiles(fnamesRawCurrent(:),"r")                       ; create list of file pointers to all raw data files with dates matching current mm-dd date
  
    print(fnamesRawCurrent)
  
    ; If processed data files already existed when the script was run (if not the first time
    ;   the script has been run during a multi-job simulation), increment date forward one year
    if(haveProcData) then
      print( cr + "Incrementing date forward 1 year" )
      dateNew = fProcCurrent->date
      dateNew = (/dateNew + 10000/)   ; increment 'date' forward 1 year, for all processed data files
      fProcCurrent->date = dateNew
      delete(dateNew)
    end if
  
    ; Read in template variables for current day; these will be overwritten with the newly
    ;   selected random-year data
    dailyVar1 = fProcCurrent->$cldVarNames(0)$     ; use as a template daily variable
    dailyVar2 = fProcCurrent->$cldVarNames(1)$     ; use as a template daily variable
    dailyVar3 = fProcCurrent->$cldVarNames(2)$     ; use as a template daily variable
    dailyVar4 = fProcCurrent->$cldVarNames(3)$     ; use as a template daily variable
    dailyVar5 = fProcCurrent->$cldVarNames(4)$     ; use as a template daily variable
    dailyVar6 = fProcCurrent->$cldVarNames(5)$     ; use as a template daily variable
    dailyVar7 = fProcCurrent->$cldVarNames(6)$     ; use as a template daily variable
    dailyVar8 = fProcCurrent->$cldVarNames(7)$     ; use as a template daily variable
    dailyVar9 = fProcCurrent->$cldVarNames(8)$     ; use as a template daily variable
    dailyVar10 = fProcCurrent->$cldVarNames(9)$     ; use as a template daily variable
    if(dimsizes(cldVarNames) .eq. 11) then
      dailyVar11 = fProcCurrent->$cldVarNames(10)$     ; use as a template daily variable
    end if
  
    ; Loop through sub-daily time steps, resequencing data using a random
    ;   year from the raw data pool
    do jtime = 0,nstepsDay-1
  
      ; If seqType is "random", generate a random number to identify which year of data to write to processed data file
      if(seqType .eq. "random") then
        ; Integer identifying random year drawn from raw data pool:
        iRandN(tcnt)    = round( (randMin + con * rand()), 3)   ; "3" to output as integer... will run 0 -> nRawYrs-1
        ; (String) year associated with random integer index value
        print("   >>> jtime,nstepsDay,iRandN(tcnt),tcnt: " + \
              jtime + "," + nstepsDay + "," + iRandN(tcnt) + "," + tcnt)
        timeRandN(tcnt) = sprinti("%0.8i",fProcCurrent->date(jtime)) + "-" + \
                          sprinti("%0.5i",fProcCurrent->datesec(jtime))  ; (string) yyyymmdd-sssss
      end if
      
      ; If seqType is "matchR", read random number values from logfile
      if(seqType .eq. "matchR") then
        iRandN(tcnt)    = logValYrInt(tcnt)
        ; (String) year associated with random integer index value
        print("   >>> jtime,nstepsDay,iRandN(tcnt),tcnt: " + \
              jtime + "," + nstepsDay + "," + iRandN(tcnt) + "," + tcnt)
        timeRandN(tcnt) = sprinti("%0.8i",fProcCurrent->date(jtime)) + "-" + \
                          sprinti("%0.5i",fProcCurrent->datesec(jtime))  ; (string) yyyymmdd-sssss
      end if
    
    
      ; For this date and time step, designate the "pointer" to one of the random raw-data files
      ; !!! NOTE: This procedure ensures that each cloud variable will be taken from the
      ;           same randomly selected time step
      fRand = fRawN[iRandN(tcnt)]                        ; select single file pointer from fRawN list
      fNameRandN(tcnt) = fnamesRawCurrent(iRandN(tcnt))  ; (String) file name (from raw data pool) associated with random integer index value
    
      print( sprinti("%10i",tcnt) + sprinti("%5i",iRandN(tcnt)) + " " + fnamesRawCurrent(iRandN(tcnt)) )
    
      dailyVar1(jtime,:,:,:) = fRand->$cldVarNames(0)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar2(jtime,:,:,:) = fRand->$cldVarNames(1)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar3(jtime,:,:,:) = fRand->$cldVarNames(2)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar4(jtime,:,:,:) = fRand->$cldVarNames(3)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar5(jtime,:,:,:) = fRand->$cldVarNames(4)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar6(jtime,:,:,:) = fRand->$cldVarNames(5)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar7(jtime,:,:,:) = fRand->$cldVarNames(6)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar8(jtime,:,:,:) = fRand->$cldVarNames(7)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar9(jtime,:,:,:) = fRand->$cldVarNames(8)$(jtime,:,:,:)     ; (time,lev,lat,lon)
      dailyVar10(jtime,:,:)  = fRand->$cldVarNames(9)$(jtime,:,:)       ; (time,lat,lon)
      if(dimsizes(cldVarNames) .eq. 11) then
        dailyVar11(jtime,:,:,:) = fRand->$cldVarNames(10)$(jtime,:,:,:) ; (time,lev,lat,lon)
      end if
    
      tcnt = tcnt + 1    ; increment total time step counter
    
      ; Clean up within jtime loop (sub-daily time steps)
     delete([/fRand/])
   
    end do   ; end jtime loop (daily time steps)
    
    ; Write randomly resequenced data for each cloud variable to current template file
    fProcCurrent->$cldVarNames(0)$ = dailyVar1
    fProcCurrent->$cldVarNames(1)$ = dailyVar2
    fProcCurrent->$cldVarNames(2)$ = dailyVar3
    fProcCurrent->$cldVarNames(3)$ = dailyVar4
    fProcCurrent->$cldVarNames(4)$ = dailyVar5
    fProcCurrent->$cldVarNames(5)$ = dailyVar6
    fProcCurrent->$cldVarNames(6)$ = dailyVar7
    fProcCurrent->$cldVarNames(7)$ = dailyVar8
    fProcCurrent->$cldVarNames(8)$ = dailyVar9
    fProcCurrent->$cldVarNames(9)$ = dailyVar10
    if(dimsizes(cldVarNames) .eq. 11) then
      fProcCurrent->$cldVarNames(10)$ = dailyVar11
    end if
  
    ; Clean up within idate loop (each daily file within processed data directory)
    delete([/fProcCurrent,nstepsDay,mmddCurrent,indRawCurrent,fnamesRawCurrent, \
             fRawN, \
             dailyVar1,dailyVar2,dailyVar3,dailyVar4,dailyVar5,dailyVar6,dailyVar7, \
             dailyVar8,dailyVar9,dailyVar10/])
    if(dimsizes(cldVarNames) .eq. 11) then
      delete(dailyVar11)
    end if
  
  end do     ; end idate loop


  ; ----------------------------------------------------------------------------------------
  ; Examine statistics of randomization
  print( cr + "Statistics of random sampling:" )
  totSteps = tcnt
  do i = 0,nRawYrs-1
    b     = where( iRandN(0:totSteps-1) .eq. i, 1, 0 )    ; create array of binaries (0 & 1), setting value to 1 to match file index number
    runs  = dim_numrun_n(b, 0, 0)           ; 
    indmx = ind(runs .ne. 0)                ; (/0, 1, 2/) ==> subscripts (index)    
    if( .not. indmx(0) ) then
      mxrun = indmx(dimsizes(indmx)-1) + 1  ; add 1 because NCL is 0-based indexing
    end if
    print("Max consecutive run for file year " + sprinti("%0.4i",toint(yyyyRaw(0))+i) + ": " + mxrun)
    nb    = num(b .eq. 1)                   ; result:  integer
    pct   = 100. * tofloat(nb) / tofloat(totSteps)
    print("   Number of occurrences for file year " + sprinti("%0.4i",toint(yyyyRaw(0))+i) + ": " \
          + sprinti("%8i",nb) + " (" + sprintf("%6.2f",pct) + "%)")
    delete([/b,runs,indmx,mxrun,nb,pct/])
  end do
  acr = esacr(iRandN(0:totSteps-1),1)   ; acr(0:1), lagged autocorrelation
  print("Lag-1 autocorrelation of sequencing: " + acr(1))
  delete(acr)
  print("")

  
  ; ----------------------------------------------------------------------------------------
  ; Record "new current year" of processed data files -- read index "1" (new current year) rather
  ;   than "0" (new previous year, in case "buffer" days have been added)
  ; This is only used for logfile (below) and print statement on final lines of this script
  fTmp  = addfile(fnamesProcDataAll(1), "r")
  yrNew = toint(floor(tofloat(fTmp->date(0))/10000.))
  delete(fTmp)
  
  ; ----------------------------------------------------------------------------------------
  ; Write information on file sequencing, for simulation reproducibility
  totSteps = tcnt
  tspan    = ispan(0,totSteps-1,1)
  a = tspan
  b = iRandN(0:totSteps-1)
  c = timeRandN(0:totSteps-1)
  d = fNameRandN(0:totSteps-1)
  alist = [/a, b, c, d/]
  header = (/"Number, file integer, time stamp, file name:  Random-year sequence for case " + clockCaseName + " and simulated year " + yrNew/)
  hlist = [/header/]
  timeStamp = systemfunc("date '+%F_%H%M%S'")
  logName = dirLog + "/" + "sequenceLog." + clockCaseName + ".YR" + sprinti("%0.4i",yrNew) + "." + timeStamp + ".txt"
  write_table(logName, "w", hlist, "%s")
  write_table(logName, "a", alist, "%8i  %8i  %s  %s")
  print( cr + "Log sequencing file written to: " + logName )


end if       ; end if seqType .eq. "random" or "matchR"




; ========================================================================================
; SEQUENTIAL ORDERING (if seqType = "sequential")
;   ...This essentially just increments date forward one year...

if(seqType .eq. "sequential") then

  if(haveProcData) then    ; if this is the first (offline) time script is run, do NOT increment date (already done above)
                           ; otherwise, need to increment date forward

    print( cr + "Incrementing date forward 1 year" )
  
    ; Loop over each day and increment date
    do idate = 0,nProcFiles-1

      ; Open existing processed data file
      fProcCurrent = addfile(fnamesProcDataAll(idate), "w")

      ; If processed data files already existed when the script was run (if not the first time
      ;   the script has been run during a multi-job simulation), increment date forward one year
      dateNew = fProcCurrent->date
      dateNew = (/dateNew + 10000/)   ; increment 'date' forward 1 year, for all processed data files
      fProcCurrent->date = dateNew
      delete(dateNew)
  
      delete([/fProcCurrent/])

    end do     ; end idate loop
    
  end if       ; end if block based on check of haveProcData
  
  ; ----------------------------------------------------------------------------------------
  ; Record "new current year" of processed data files -- read index "1" (new current year) rather
  ;   than "0" (new previous year, in case "buffer" days have been added)
  ; This is only used for logfile (below) and print statement on final lines of this script
  fTmp  = addfile(fnamesProcDataAll(1), "r")
  yrNew = toint(floor(tofloat(fTmp->date(0))/10000.))
  delete(fTmp)
  
  ; ----------------------------------------------------------------------------------------
  ; Write information on file sequencing, for simulation reproducibility
  timeStamp = systemfunc("date '+%F_%H%M%S'")
  logName = dirLog + "/" + "sequenceLog." + clockCaseName + ".YR" + sprinti("%0.4i",yrNew) + "." + timeStamp + ".txt"
  asciiwrite( logName, "All days use cloud data from year " + sequentialYr + " of case " + rawDataCaseName )
  print( cr + "Log sequencing file written to: " + logName )
  
  
end if       ; end if seqType .eq. "sequential"




; ----------------------------------------------------------------------------------------
; If generating new resequenced data (if running before first cloud-locked job submission
;   to initially state prescribed-cloud data files), create symbolic links to each daily
;   file in the processed data directory

if(.not. haveProcData) then
  print( cr + "At beginning of script, did not detect any template files in processed data directory...")
  print( "...will now delete all existing symbolic links and regenerate them.")
  cmd = "rm -f " + dirSymLinks + "/*.nc"
  print("Command is: " + cmd)
  system(cmd)
  print( cr + "Symbolic links to processed cloud data being created..." )
  iseq = iseqBeg
  do i = 0,nProcFiles-1
    print("")
    fSym = dirSymLinks + "/" + procDataCaseName + ".cam.h" + hTape + "." + sprinti("%0.5i",iseq) + ".nc"
    print("Linked file name : " + fnamesProcDataAll(i))
    print("Symlink file name: " + fSym)
    cmd = "/bin/ln -s " + fnamesProcDataAll(i) + " " + fSym
    print("Command is: " + cmd)
    system(cmd)
    iseq = iseq + 1
  end do
end if


; ----------------------------------------------------------------------------------------
; Print wallclock time required to run the full script, plus some other details
print( cr )
wallClockElapseTime(wcStrt, "sequenceCloudData.ncl", 0)

print( cr + "Script " + get_script_name() + " has completed. Old year stamp: " + \
       sprinti("%0.4i",yrOld) + ", new year stamp: " + sprinti("%0.4i",yrNew) )

end
