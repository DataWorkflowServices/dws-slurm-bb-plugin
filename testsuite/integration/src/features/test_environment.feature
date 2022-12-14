#
# Copyright 2022 Hewlett Packard Enterprise Development LP
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

Feature: Integration test environment
    Verify the integration test environment has been setup correctly

    Scenario: Kubernetes is available
        When kubernetes cluster nodes are queried
        Then one or more kubernetes nodes are available

    Scenario: The DataWorkflowServices deployment exists
        When the DataWorkflowServices deployment is queried
        Then the DataWorkflowServices deployment is found

    Scenario: Slurm is usable
        Given a job script:
            #!/bin/bash
            /bin/hostname
            srun -l /bin/hostname
            srun -l /bin/pwd
        When the job is run
        Then the job completes successfully

    Scenario: Kubernetes and slurm are connected
        Given the kubernetes cluster kube-system UID
        When the kube-system UID is queried from slurmctld
        Then the UIDs match and the cluster is the same
