#!/bin/bash -l
#SBATCH --job-name=sequence_cloudDat_prerun
#SBATCH --account=UCUB0082
#SBATCH --ntasks=8
#SBATCH --ntasks-per-node=4
#SBATCH --time=10:00:00
#SBATCH --partition=dav
#SBATCH --output=sequence_cloudDat_prerun.out.%j

export TMPDIR=/glade/scratch/$USER/temp
mkdir -p $TMPDIR

### Run program
module load ncl/6.6.2
ncl /glade/work/eleanorm/cases/cesm2_cldlck/scripts/sequenceCloudData.ncl >> /glade/work/eleanorm/cases/cesm2_cldlck/scripts/prerun_sequence.log 
