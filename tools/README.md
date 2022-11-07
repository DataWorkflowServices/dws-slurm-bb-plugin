# Using KIND to create a Kubernetes environment for DWS

See https://kind.sigs.k8s.io for KIND docs.

## Install KIND

```bash
$ brew install kind
```

## Start a cluster

This will create a simple one-node k8s cluster that has a node label for DWS and has a cert-manager installed for the DWS webhook.

```bash
$ tools/kind.sh
```

### Delete a cluster

When your testing with DWS is complete you may delete the cluster.

```bash
$ kind delete cluster
```

## Build DWS

Build a container image for DWS.

```bash
$ git clone git@github.com:HewlettPackard/dws.git
$ cd dws
$ make docker-build
```

## Deploy DWS in K8s

Push the DWS container into the KIND environment.  This relies on the node label we applied with the `tools/kind.sh` tool above.

```bash
$ make kind-push
```

Install the DWS CRDs, service accounts, roles, rolebindings, deployment, and other necessary pieces.

```bash
$ make deploy
```

Wait for DWS to be ready.

```bash
$ kubectl get pods -n dws-operator-system -w
```

# The DWS API 

## State: Proposal

For proposal state, the Lua script will create the initial workflow resource, with desiredState=proposal.  The Lua script would add the BB_LUA lines to the dwDirectives array, and fill in the wlmID, jobID, userID, and groupID prior to submitting this resource.  For now we're using an empty dwDirectives array because we don't have a mock conduit driver and ruleset.

Create a basic Workflow resource.

```bash
$ cat << END > silver_workflow_proposal.yaml
apiVersion: dws.cray.hpe.com/v1alpha1
kind: Workflow
metadata:
  name: silver
spec:   
  desiredState: "proposal"
  dwDirectives: []
  wlmID: "23423-sdf0239-324lkj"
  jobID: 100
  userID: 100
  groupID: 100
END
```

```bash
$ kubectl apply -f silver_workflow_proposal.yaml
workflow.dws.cray.hpe.com/silver created
```

The Lua script must wait and confirm that the workflow completes the proposal state.  We're using an empty dwDirectives array, so DWS will automatically transition this to a completed state.  If we had a dwDirectives array, with BB_LUA lines, then we'd expect a mock conduit driver and ruleset to transition this to a completed state for us.

```bash
$ kubectl get workflow silver
NAME     STATE      READY   STATUS      AGE
silver   proposal   true    Completed   39s

$ kubectl get workflow silver -o jsonpath='{.status.status}'
Completed
```

To get current state so it can be compared to desiredState:

```bash
$ kubectl get workflow silver -o jsonpath='{.spec.desiredState}{"\n"}{.status.state}{"\n"}{.status.status}{"\n"}'                 
setup
setup
Completed
```

## State: Setup

For setup state, the Lua script will first confirm that proposal state has completed, then it will patch the spec to changed the desiredState to setup.

```bash
$ kubectl patch workflow silver --type=merge -p '{"spec":{"desiredState": "setup"}}'
workflow.dws.cray.hpe.com/silver patched
```

The Lua script must wait and confirm that the workflow completes the setup state.

```bash
$ kubectl get workflow silver
NAME     STATE   READY   STATUS      AGE
silver   setup   true    Completed   23m

$ kubectl get workflow silver -o jsonpath='{.status.status}'
Completed
```

## State: others

Same as above.

## State: Teardown

For teardown state there is an option to set the "hurry" flag.

```bash
$ kubectl patch workflow silver --type=merge -p '{"spec":{"desiredState": "teardown","hurry":true}}'
workflow.dws.cray.hpe.com/silver patched
```

