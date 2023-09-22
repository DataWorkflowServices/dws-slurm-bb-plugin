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

import time
import re
from pytest_bdd import (
    parsers,
    scenarios,
    then,
    when,
)
from kubernetes import client as k8sclient
from .workflow import Workflow

# Data Workflow Services State Progression feature tests.
scenarios("test_dws_states.feature")

@then('a Workflow has been created for the job')
@then('the workflow still exists')
def _(k8s, jobId):
    """a Workflow has been created for the job."""
    workflow = Workflow(k8s, jobId)
    assert workflow.data is not None, "Workflow for Job: " + str(jobId) + " not found"

    yield

    # attempt to delete workflow if it still exists
    try:
        workflow.delete()
    except k8sclient.exceptions.ApiException:
        pass

@when('some Workflow has been created for the job')
def _(k8s, jobId):
    """some Workflow has been created for the job."""
    workflow = Workflow(k8s, jobId)
    assert workflow.data is not None, "Workflow for Job: " + str(jobId) + " not found"

@then('the Workflow has eventually been deleted')
def _(slurmctld, jobId):
    """the Workflow has eventually been deleted"""
    slurmctld.wait_until_workflow_is_gone(jobId)

def verify_job_bbstat(slurmctld, jobId, state, status):
    jobStatus = slurmctld.scontrol_show_bbstat(jobId)
    assert jobStatus["desiredState"] == state, "Incorrect desired state: " + str(jobStatus)
    assert jobStatus["currentState"] == state, "Incorrect current state: " + str(jobStatus)
    assert jobStatus["status"] == status, "Incorrect status: " + str(jobStatus)

@then(parsers.parse('the Workflow and job progress to the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow and job progress to the <state> state."""

    expectedStatus = "DriverWait"

    workflow = Workflow(k8s, jobId)
    workflow.wait_until(
        f"the workflow transitioned to {state}/{expectedStatus}",
        lambda wf: wf.data["status"]["state"] == state and wf.data["status"]["status"] == expectedStatus
    )
    print(f"job {jobId} progressed to state {state}")

    verify_job_bbstat(slurmctld, jobId, state, expectedStatus)

    # Set driver status to completed so the workflow can progress to the next state
    foundPendingDriverStatus = False
    for driverStatus in workflow.data["status"]["drivers"]:
        if driverStatus["driverID"] == "tester" and driverStatus["watchState"] == state and driverStatus["status"] == "Pending":
            print(f"updating workflow {jobId} to complete state {state}")
            driverStatus["completed"] = True
            driverStatus["status"] = "Completed"
            foundPendingDriverStatus = True
            break

    assert foundPendingDriverStatus, "Driver not found with \"Pending\" status"
    workflow.save_driver_statuses()

def driver_state_check(workflow, state, expected_status):
    found_it = False
    print(f"check drivers for state {state} with status {expected_status}")
    for driver in workflow.data["status"]["drivers"]:
        if driver["driverID"] == "tester" and driver["watchState"] == state:
            if driver["status"] == expected_status:
                print(f"found driver state {state} with {expected_status}")
                found_it = True
            else:
                print(f"found driver state {state}/{driver['status']}")
            break
    return found_it

@when(parsers.parse('the Workflow reports fatal errors at the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow reports fatal errors at the <state> state."""

    expected_status = "Error"

    def driver_check(workflow):
        return driver_state_check(workflow, state, expected_status)

    workflow = Workflow(k8s, jobId)
    workflow.wait_until(
        f"the workflow {state} state shows a status of {expected_status}",
        lambda wf: driver_check(wf) is True
    )

@then(parsers.parse("the job's system comment eventually contains the following:\n{message}"))
def _(slurmctld, jobId, message):
    print(f"looking for system comment with: {message}")
    slurmctld.wait_until_job_system_comment(jobId, message)
