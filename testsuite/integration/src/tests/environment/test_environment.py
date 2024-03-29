#
# Copyright 2022-2024 Hewlett Packard Enterprise Development LP
# Other additional copyright holders may be indicated within.
#
# The entirety of this work is licensed under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
#
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

"""Integration test environment feature tests."""

import json
import os
from pytest_bdd import (
    given,
    scenarios,
    parsers,
    then,
    when,
)

scenarios("test_environment.feature")

@given('the kubernetes cluster kube-system UID', target_fixture="kube_system_uid")
def _(k8s):
    """the kubernetes cluster kube-system UID."""
    ns_list = k8s.CoreV1Api().list_namespace(field_selector="metadata.name==kube-system")
    assert len(ns_list.items) == 1, "kube-system namespace not found"
    return ns_list.items[0].metadata.uid

@when('kubernetes cluster nodes are queried', target_fixture="k8s_nodes")
def _(k8s):
    """kubernetes cluster nodes are queried."""
    return k8s.CoreV1Api().list_node().items

@when('the DataWorkflowServices deployment is queried', target_fixture="dws_deployment_list")
def _(k8s):
    """the DataWorkflowServices deployment is queried."""
    return k8s.AppsV1Api().list_namespaced_deployment(
        namespace="dws-system",
        field_selector="metadata.name=dws-controller-manager"
    )

@when('the kube-system UID is queried from slurmctld container', target_fixture="kube_system_uid_from_slurmctld")
def _(slurmctld):
    """the kube-system UID is queried from slurmctld container."""
    rc,out = slurmctld.exec_run("kubectl --kubeconfig /etc/slurm/slurm-dws.kubeconfig get namespace -o=json kube-system")
    assert rc==0, "non-zero return code: \n" + out
    return json.loads(out)["metadata"]["uid"]

@then('one or more kubernetes nodes are available')
def _(k8s_nodes):
    """one or more kubernetes nodes are available."""
    assert len(k8s_nodes) > 0

@then('the DataWorkflowServices deployment is found')
def _(dws_deployment_list):
    """the DataWorkflowServices deployment is found."""
    assert len(dws_deployment_list.items) == 1, \
        "An incorrect number of DWS deployments was found"

@then('the UIDs match and the cluster is the same')
def _(kube_system_uid, kube_system_uid_from_slurmctld):
    """the UIDs match and the cluster is the same."""
    assert kube_system_uid == kube_system_uid_from_slurmctld
