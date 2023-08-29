# Debugging integration tests

Change to the `testsuite/integration` directory:

```console
cd testsuite/integration
```

Start the integration test environment.  This will start the KIND-based k8s
environment with DWS, dws-test-driver, and Slurm.  The slurm containers will
run alongside the k8s environment:

```console
make setup
```

Build a version of the integration test container using only the `testbase`
stage, so it has the test environment but doesn't automatically run the tests:

```console
docker build -t local/integration-test:test --target testbase --no-cache .
```

Start the integration test container and get a shell into it.  The tests from
`testsuite/integration/src` will be mounted into the container as `/tests` and
this will be set as your working directory.  The container will be hooked up to
the network that has the k8s cluster and the slurm containers. The `kubectl`
command will access the k8s cluster.

```console
docker run -it --rm -v $PWD/kubeconfig:/root/.kube/config -v $PWD/slurm/jobs:/jobs -v /var/run/docker.sock:/var/run/docker.sock -v $PWD/src:/tests -w /tests --network slurm_default local/integration-test:test bash
```

Basic usage of `pytest` from inside the integration-test container:

```console
pytest --gherkin-terminal-reporter -v .
```

To run only the "environment checkout" tests, specify the `@environment` marker
that is in `testsuite/integration/src/features/test_environment.feature`.  See
[Working with custom
markers](https://docs.pytest.org/en/7.1.x/example/markers.html) and [Organizing
your scenarios](https://pytest-bdd.readthedocs.io/en/stable/#organizing-your-scenarios).

```console
pytest --gherkin-terminal-reporter -v -m environment .
```

To shutdown and clean up the integration test environment, first exit the shell
you have in the integration-test container and then use the `clean` target in
the Makefile:

```console
make clean
```

