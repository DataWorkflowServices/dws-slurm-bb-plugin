# dws-slurm-bb-plugin
A Lua script for Slurm’s Burst Buffer plugin that maps DataWarp-style data movement directives to Workflows in Data Workflow Services.

## Using the test environment as a playground

The test environment may be used a playground to experiment with Slurm, DWS, and the dws-test-driver.

Begin by setting up the test environment.  This will start KIND to create a k8s cluster where it will launch DWS and the dws-test-driver.  This will also run Slurm's `slurmctld` and `slurmd` containers.  The Slurm containers will not be running in the k8s cluster, but they are able to communicate with the DWS API.

Note: this is a minimalist Slurm environment and it does not support all Slurm functionality.

```console
$ make -C testsuite/integration setup
```

Enter the `slurmctld` container to use Slurm's commands.  Jobs must be launched by the `slurm` user.

```console
$ docker exec -it slurmctld bash

[root@slurmctld jobs]# su slurm
bash-4.4$ cd /jobs
```

The `/jobs` directory is mounted into the container from your workarea.  You can find it in your workarea at `testsuite/integration/slurm/jobs`.  This directory contains a sample job script.  Any output files from job scripts will also be stored in this directory.  Slurm commands such as `sbatch`, `scontrol`, and `scancel` may be used from this location in the container if run as the `slurm` user.

The Slurm `sacct` command, and certain others, will not work in this minimalist Slurm environment.

To shutdown and cleanup the entire test environment, use the `clean` target in the makefile:

```console
$ make -C testsuite/integration clean
```

### Simple playground exercise

This simple exercise will cause the job to proceed to DataOut state and wait for us to mark that state as complete, and then it will proceed to Teardown state.

Edit `testsuite/integration/slurm/jobs/test-bb.sh` to change the `#DW` line to be `#DW DataOut action=wait`.

```bash
#SBATCH --output=/jobs/slurm-%j.out
#DW DataOut action=wait
/bin/hostname
srun -l /bin/hostname
srun -l /bin/pwd
```

In the container, from inside the `/jobs` directory, submit this new batch job:

```console
bash-4.4$ sbatch test-bb.sh
```

You can watch the Workflow resource appear and proceed through the states to DataOut, where it will pause with a state of DriverWait:

```console
$ kubectl get workflow -wA
```

When the Workflow is in DriverWait, you can release it by marking it as completed.  In this case, my job ID is `12`, so the Workflow resource we're editing is `bb12`.  The paths specified in this patch refer to index 0, the first (and only) `#DW` directive in our job script.

```console
$ kubectl patch workflow -n slurm bb12 --type=json -p '[{"op":"replace", "path":"/status/drivers/0/status", "value": "Completed"}, {"op":"replace", "path":"/status/drivers/0/completed", "value": true}]'
```

You can then watch the Workflow resource proceed to Teardown state, after which the burst_buffer.lua teardown function will delete the resource.

