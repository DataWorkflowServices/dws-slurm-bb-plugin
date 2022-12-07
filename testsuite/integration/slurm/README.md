# Slurm Docker Cluster

This is a multi-container Slurm v22 cluster using docker-compose.  The compose file creates named volumes for persistent storage of MySQL data files as well as Slurm state and log directories. The burst_buffer.lua script and burst_buffer.conf are mounted in the slurmctld container and the burst_buffer script is available to be tested using `#DW` directives.

## Containers and Volumes

The compose file will run the following containers:

* mysql
* slurmdbd
* slurmctld
* c1 (slurmd)
* c2 (slurmd)

The compose file will create the following named volumes:

* etc_munge         ( -> /etc/munge     )
* var_lib_mysql     ( -> /var/lib/mysql )
* var_log_slurm     ( -> /var/log/slurm )

## Building the Docker Image

Build the image locally:

```console
docker build -t slurm-bb:test .
```

Or equivalently using `docker-compose`:

```console
docker-compose build
```


## Starting the Cluster

Run `docker-compose` to instantiate the cluster:

```console
docker-compose up -d
```

## Register the Cluster with SlurmDBD

To register the cluster to the slurmdbd daemon, run the `register_cluster.sh`
script:

```console
./register_cluster.sh
```

> Note: You may have to wait a few seconds for the cluster daemons to become
> ready before registering the cluster.  Otherwise, you may get an error such
> as **sacctmgr: error: Problem talking to the database: Connection refused**.
>
> You can check the status of the cluster by viewing the logs: `docker-compose
> logs -f`

## Accessing the Cluster

Use `docker exec` to run a bash shell on the controller container:

```console
docker exec -it slurmctld bash
```

From the shell, execute slurm commands, for example:

```console
[root@slurmctld /]# sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 5-00:00:00      2   idle c[1-2]
```

## Submitting Jobs

The local `jobs` directory is mounted on each Slurm container as `/jobs`. The
`/jobs` directory is owned by the "slurm" user in each Slurm container. Since
the `slurmctld` and `slurmd` daemons run under the slurm  user, and since the
`/jobs` folder is the only folder in the slurm containers with the right
user permissions, the `srun` and `sbatch` commands need to be run from the
`/jobs` folder under the "slurm" user. Alternaively, the
`#SBATCH --output=/jobs/slurm-%j.out` directive can be used in `sbatch`
scripts.

```console
# docker exec -u slurm -it slurmctld bash
[slurm@slurmctld /]# cd /jobs
[slurm@slurmctld jobs]# sbatch test-bb.lua
Submitted batch job 2
[slurm@slurmctld jobs]# ls
slurm-2.out
```

## Stopping and Restarting the Cluster

```console
docker-compose stop
docker-compose start
```

## Deleting the Cluster

To remove all containers and volumes, run:

```console
docker-compose stop
docker-compose rm -f
docker volume rm slurm-docker-cluster_etc_munge slurm-docker-cluster_var_lib_mysql slurm-docker-cluster_var_log_slurm
rm jobs/slurm*.out
```
