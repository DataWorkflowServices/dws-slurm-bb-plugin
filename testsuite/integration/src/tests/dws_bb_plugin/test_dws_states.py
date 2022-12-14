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

from .workflow import Workflow
from pytest_bdd import (
    given,
    parsers,
    scenarios,
    then,
    when,
)

"""Data Workflow Services State Progression feature tests."""
scenarios("test_dws_states.feature")

@when('a Workflow is created for the job')
def _(k8s, jobId):
    """a Workflow is created for the job."""
    workflow = Workflow(k8s, jobId)
    assert workflow.data != None, "Workflow for Job: " + str(jobId) + " not found"

@when('the job is canceled with the hurry flag set to <hurry_flag>')
def _():
    """the job is canceled with the hurry flag set to <hurry_flag>."""
    raise NotImplementedError

@when('the job\'s temporary Workflow is not found')
def _():
    """the job's temporary Workflow is not found."""
    raise NotImplementedError

@then(parsers.parse('the Workflow and job progress to the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow and job progress to the <state> state."""
    workflow = Workflow(k8s, jobId)
    workflow.wait_until(
        "the state the workflow is transitioning to",
        lambda wf: wf.data["status"]["state"], state
    )

    jobStatus = slurmctld.get_job_status(jobId)
    assert jobStatus["desiredState"] == state, "Incorrect desired state: " + str(jobStatus)
    assert jobStatus["currentState"] == state, "Incorrect current state: " + str(jobStatus)
    assert jobStatus["status"] == "DriverWait", "Incorrect status: " + str(jobStatus)

    # Set driver status to completed so the workflow can progress to the next state
    for driverStatus in workflow.data["status"]["drivers"]:
        if driverStatus["driverID"] == "tester" and state in driverStatus["watchState"]:
            driverStatus["completed"] = True
            driverStatus["status"] = "Completed"

    workflow.save_driver_statuses()


@then('the Workflow\'s hurry flag is set to <hurry_flag>')
def _():
    """the Workflow's hurry flag is set to <hurry_flag>."""
    raise NotImplementedError

@then('the job shows an error with message "{message}"')
def _():
    """the job shows an error with message "{message}"}"."""
    raise NotImplementedError