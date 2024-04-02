# dws-slurm-bb-plugin
A Lua script for Slurm’s Burst Buffer plugin that maps DataWarp-style data movement directives to Workflows in Data Workflow Services.

## Parts of the plugin

The plugin is found in `src/burst_buffer/burst_buffer.lua`.

In that same directory is the `burst_buffer.conf` file which manages certain configurable items as handled by Slurm.  For more details, refer to the [slurm docs](https://slurm.schedmd.com/burst_buffer.conf.html).

### Basic unit test

The basic unit test for the plugin is found in `testsuite/unit/src/burst_buffer/dws-test.lua`.  It is implemented using the [busted](https://lunarmodules.github.io/busted/) unit test framework.  This test mocks all calls to k8s, DWS, or Slurm.

To run this test, use the `test-no-docker` target in the top-level Makefile.  You must have the required Lua dependencies installed on your system.

```console
make test-no-docker
```

If you do not have the required Lua dependencies installed, you can run the unit test the way it would be run by the `unit-test.yaml` workflow, using a Docker environment. Use the `test` target in the top-level Makefile.

```console
make test
```

### Integration test

The integration test is found in `testsuite/integration`. It is written using the [pytest_bdd](https://pypi.org/project/pytest-bdd/) framework.

This will start a k8s environment using [KIND](https://kind.sigs.k8s.io) and will add DWS, dws-test-driver, and Slurm.  The Slurm containers run alongside the k8s environment.  This will run the tests that reside in `testsuite/integration/src`.  This is the same test that is run by the `integration-test.yaml` workflow.

To run this test, use the `integration-test` target in the top-level Makefile.

```console
make integration-test
```

## The integration test environment as a playground

The integration test environment may be used as a playground to experiment with Slurm, DWS, and the dws-test-driver.

Begin by setting up the test environment.  This will start KIND to create a k8s cluster where it will launch DWS and the dws-test-driver.  This will also run Slurm's `slurmctld` and `slurmd` containers.  The Slurm containers will not be running in the k8s cluster, but they are able to communicate with the DWS API.

Note: this is a minimalist Slurm environment and it does not support all Slurm functionality.

```console
make -C testsuite/integration setup
```

Enter the `slurmctld` container to use Slurm's commands.  Jobs must be launched by the `slurm` user.

```console
docker exec -it slurmctld bash

[root@slurmctld jobs]# su slurm
bash-4.4$ cd /jobs
```

The `/jobs` directory is mounted into the container from your workarea.  You can find it in your workarea at `testsuite/integration/slurm/jobs`.  This directory contains a sample job script.  Any output files from job scripts will also be stored in this directory.  Slurm commands such as `sbatch`, `scontrol`, and `scancel` may be used from this location in the container if run as the `slurm` user.

Watch the Slurm log which includes the log messages from the burst buffer
plugin:

```console
docker logs slurmctld
```

The Slurm `sacct` command, and certain others, will not work in this minimalist Slurm environment.

### Playground shutdown and cleanup

To shutdown and cleanup the entire test environment, use the `clean` target in the makefile:

```console
make -C testsuite/integration clean
```

### Simple playground exercise #1

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

You can watch the Workflow resource appear and proceed through the states to DataOut, where it will pause with a state of DriverWait.  Run all `kubectl` commands from your host, not from inside the slurmctld container:

```console
kubectl get workflow -wA
```

If you want to run the `kubectl` commands from inside the slumctld container, then set the KUBECONFIG environment variable in the container.  The kubectl command will then use this kubeconfig file.

```console
export KUBECONFIG=/etc/slurm/slurm-dws.kubeconfig
```

When the Workflow is in DriverWait, you can release it by marking it as completed.  In this case, my job ID is `12`, so the Workflow resource we're editing is `bb12`.  The paths specified in this patch refer to index 0, the first (and only) `#DW` directive in our job script.

```console
kubectl patch workflow -n slurm bb12 --type=json -p '[{"op":"replace", "path":"/status/drivers/0/status", "value": "Completed"}, {"op":"replace", "path":"/status/drivers/0/completed", "value": true}]'
```

You can then watch the Workflow resource proceed to Teardown state, after which the burst_buffer.lua teardown function will delete the resource.

### Simple playground exercise #2

This exercise will cause the job to wait on a Major error in DataOut and after
we clear the error it will proceed to Teardown state where it will wait for
us to release it.

Edit `testsuite/integration/slurm/jobs/test-bb.sh` to change the `#DW` lines to be the following:

```bash
#SBATCH --output=/jobs/slurm-%j.out
#DW DataOut action=error message=johnson_rod_misalignment severity=Major
#DW Teardown action=wait
/bin/hostname
srun -l /bin/hostname
srun -l /bin/pwd
```

Submit this job using the `sbatch` command as shown above.

Watch the workflow with `kubectl get workflow -wA` as shown above.

When the workflow is in DataOut state with a status of `TransientCondition`, you can view the error:

```console
kubectl get workflow -n slurm bb3 -o yaml
```

Now clear the error and mark the state as complete:

```console
kubectl patch workflow -n slurm bb3 --type=json -p '[{"op":"replace", "path":"/status/drivers/0/status", "value": "Completed"}, {"op":"replace", "path":"/status/drivers/0/completed", "value": true}, {"op":"remove", "path":"/status/drivers/0/error"}]'
```

Again, we can view the workflow:

```console
kubectl get workflow -n slurm bb3 -o yaml
```

The workflow is now in Teardown with a status of DriverWait.  Release it by marking the state as complete.  This time the paths in this patch refer to index 1, the second `#DW` directive in our job script.

```console
kubectl patch workflow -n slurm bb3 --type=json -p '[{"op":"replace", "path":"/status/drivers/1/status", "value": "Completed"}, {"op":"replace", "path":"/status/drivers/1/completed", "value": true}]'
```


