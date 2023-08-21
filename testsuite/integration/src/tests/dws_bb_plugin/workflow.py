#
# Copyright 2022-2023 Hewlett Packard Enterprise Development LP
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

from kubernetes import client, config
from tenacity import *

class WorkflowWaitError(Exception):
    def __init__(self, workflowName, description):
        super().__init__("TIMED OUT WAITING FOR: " + description + " for workflow[" + workflowName + "]")

class Workflow:
    def __init__(self, k8s, jobId):
        config.load_kube_config()
        self.k8s = k8s
        self.jobId = jobId
        self._data = None
        self._api_version = "v1alpha2"

    @property
    def name(self):
        return "bb" + str(self.jobId)

    @property
    def data(self):
        if self._data == None:
            self._data = self._get_data()
        return self._data

    @retry(
        wait=wait_fixed(2),
        stop=stop_after_attempt(30),
        reraise=True
    )
    def _get_data(self):
        workflowData = self.k8s.CustomObjectsApi().get_namespaced_custom_object(
            "dws.cray.hpe.com", self._api_version, "slurm", "workflows", self.name
        )

        return workflowData

    @retry(
        wait=wait_fixed(2),
        stop=stop_after_attempt(20),
        reraise=True
    )
    def wait_until(self, description, is_ready):
        """Wait until the wf_callable returns true"""
        wf = Workflow(self.k8s, self.jobId)
        if not is_ready(wf):
            print("not ready")
            raise WorkflowWaitError(self.name, description)
        print("ready")
        self._data = wf.data
    
    def save_driver_statuses(self):
        patchData = {
            "status": {
                "drivers": self.data["status"]["drivers"]
            }
        }
        self.k8s.CustomObjectsApi().patch_namespaced_custom_object(
            "dws.cray.hpe.com", self._api_version, "slurm", "workflows", self.name, patchData
        )
        
    def delete(self):
        self.k8s.CustomObjectsApi().delete_namespaced_custom_object(
            "dws.cray.hpe.com", self._api_version, "slurm", "workflows", self.name
        )
