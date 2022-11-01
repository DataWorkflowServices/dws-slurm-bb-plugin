#!/bin/sh
#SBATCH --output=/jobs/slurm-%j.out
#BB_LUA pool=pool1 capacity=1K
/bin/hostname
srun -l /bin/hostname
srun -l /bin/pwd
