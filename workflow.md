# cesm_cloud_locking WORKFLOW

This outlines the steps for cloud locking in CESM2. There are three aspects:
- source code modifications
- reference simulation to create cloud data
- locked simulation

# Get CESM and cesm_cloud_locking
Both the model and the cloud-locking code are available via git.

For convenience, let's say that cesm_cloud_locking is obtained and resides in the `lock_code` directory.

# Reference Case
From the CESM2 root, find the `cime/scripts` directory and make a new case.
```
> create_newcase --case /glade/work/brianpm/fhist.2.ref.001 --compset FHIST --res f09_g17 --project P93300642 --walltime 03:30:00 --run-unsupported
> cd /glade/work/brianpm/fhist.2.ref.001
> cp lock_code/* ./SourceMods/src.cam/
> case.setup
```
Next, specify to write the cloud parameters to output in user_nl_cam, such that this included:
```
FINCL2 = 'DEI_rad', 'MU_rad', 'LAMBDAC_rad', 'ICIWP_rad', 'ICLWP_rad', 'DES_rad', 'ICSWP_rad', 'CLD_rad', 'CLDFSNOW_rad'
nhtfrq = 0,-2
mfilt = 1,12
avgflag_pertape = 'A','I'
ndens = 2,2
```
Note that here we've set up the case to save instantaneous cloud data every 2 hours in daily `h1` files. The `h0` files will be the usual monthly means.

Now set whatever runtime parameters are needed in `env_run.xml`.  For example:
```
xmlchange STOP_N=24
xmlchange STOP_OPTION=nmonths
```

Build the case. A useful tip for cheyenne is that if you are unable to build because of an overspent account, you can change to a different account with an environment variable, e.g., `> export PBS_ACCOUNT=P93300642`
```
> qcmd -- case.build
> case.submit
```

# Locked Case
The reference case provides the cloud data that needs to be used by the locked case. `cesm_cloud_locking` provides a couple of ways to specify this data. For this example, we will concatenate the h1 files into one (large) netCDF file and specify that.
Assuming that short-term archiving is used, the files will be in the archive directory, which we will denote as `archive`.
```
> cd archive
> cd casename/atm/hist
> ncrcat *.cam.h1.* cloud_locking_data.nc
> mv cloud_locking_data.nc /some/place/for/data/
```

Return to the CESM root directory to set up the second, locked case.
```
> cd CESMROOT/cime/scripts
> create_newcase --case /glade/work/brianpm/fhist.2.lock.001 --compset FHIST --res f09_g17 --project P93300642 --walltime 03:30:00 --run-unsupported
> cd /glade/work/brianpm/fhist.2.lock.001
> cp lock_code/* ./SourceMods/src.cam/
> case.setup
```
Edit the `user_nl_cam` file to make use of the `prescribed_cloud` module and  specify the cloud output data. For example:
```
prescribed_cloud_datapath = '/some/place/for/data/'
prescribed_cloud_file = 'cloud_locking_data.nc'
prescribed_cloud_type = 'CYCLICAL'
prescribed_cloud_cycle_yr = '0001'
pertlim = 0.1
```
Note that we have applied an initial perturbation using `pertlim`; the purpose here is to get the locked simulation to diverge from the reference simulation faster than it would otherwise. If we were locking clouds at every radiation step, the two would be identical but for this initial perturbation. With our 2-hourly locking and an initial perturbation, the two should differ significantly within days of initialization.

Set runtime options, build, and run the model:
```

> xmlchange STOP_N=24
> xmlchange STOP_OPTION=nmonths
> qcmd -- case.build
> case.submit
```
