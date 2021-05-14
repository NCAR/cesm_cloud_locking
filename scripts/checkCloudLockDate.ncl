;---------------------------------------------------
; locate weird dates & datesecs in dataFiles 

dirDataFiles = "/glade/scratch/eleanorm/clockinput/dataFiles/B1850_clockoutput"
fnames = systemfunc("ls "+dirDataFiles)
nofiles = dimsizes(fnames)
;
weirddatefiles = new(nofiles,string)
n=0
time = systemfunc("date")
do i=0,nofiles-1
	f = addfile(dirDataFiles+"/"+fnames(i),"r")
	date = f->date
	datesec = f->datesec
	if dimsizes(ind(date.gt.12123)).gt.1 .or. dimsizes(ind(datesec.gt.79200)).gt.1 
		print("Weird date detected!")
		print("In "+fnames(i))
		weirddatefiles(n) = fnames(i)
		n=n+1
	end if
end do
wallClockElapseTime(time,"Time to locate weird times",0)

if dimsizes(ind(ismissing(weirddatefiles).eq.True)).eq.nofiles
	print("No weird dates or datesecs among files detected!")
else
	print("Weird files detected.")
end if

;---------------------------------------------------
; correct weird dates & datesecs:
weirddatefiles:=weirddatefiles(ind(ismissing(weirddatefiles).eq.False))

; obtain a correct datesec vector:
f = addfile(dirDataFiles+"/"+fnames(0),"r")
datesecCorrect = f->datesec
do n=0,dimsizes(weirddatefiles)-1
        f = addfile(dirDataFiles+"/"+weirddatefiles(n),"w")
	dateNew = f->date
	; assuming the first date is right
	dateNew = where(dateNew.ne.dateNew(0),dateNew(0),dateNew)
    	f->date = dateNew
	
	; correct datesec
	f->datesec = datesecCorrect
end do
