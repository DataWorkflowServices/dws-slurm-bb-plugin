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

@when(parsers.parse('the Workflow status becomes {status:l}'))
def _(slurmctld, jobId, status):
    """the Workflow status becomes <status>"""
    workflowStatus = slurmctld.get_workflow_status(jobId)
    assert workflowStatus["status"] == status

@then('the job is canceled')
def _(slurmctld, jobId):
    """the job is canceled"""
    time.sleep(2) # Sleep long enough for bb plugin to poll workflow once or twice
    slurmctld.cancel_job(jobId, False)
    time.sleep(2) # Sleep long enough for the workflow to be deleted

def verify_job_status(slurmctld, jobId, state, status):
    jobStatus = slurmctld.get_workflow_status(jobId)
    assert jobStatus["desiredState"] == state, "Incorrect desired state: " + str(jobStatus)
    assert jobStatus["currentState"] == state, "Incorrect current state: " + str(jobStatus)
    assert jobStatus["status"] == status, "Incorrect status: " + str(jobStatus)

@then(parsers.parse('the Workflow and job progress to the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow and job progress to the <state> state."""

    expectedStatus = "DriverWait"

    workflow = Workflow(k8s, jobId)
    workflow.wait_until(
        f"the workflow transitions to {state}/{expectedStatus}",
        lambda wf: wf.data["status"]["state"] == state and wf.data["status"]["status"] == expectedStatus
    )
    print("job %s progressed to state %s" % (str(jobId),state))

    verify_job_status(slurmctld, jobId, state, expectedStatus)

    # Set driver status to completed so the workflow can progress to the next state
    foundPendingDriverStatus = False
    for driverStatus in workflow.data["status"]["drivers"]:
        if driverStatus["driverID"] == "tester" and driverStatus["watchState"] == state and driverStatus["status"] == "Pending":
            print("updating workflow %s to complete state %s" % (str(jobId), state))
            driverStatus["completed"] = True
            driverStatus["status"] = "Completed"
            foundPendingDriverStatus = True
            break

    assert foundPendingDriverStatus, "Driver not found with \"Pending\" status"
    workflow.save_driver_statuses()

@then(parsers.parse('the Workflow error is cleared from the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow error is cleared from the <state> state."""

    workflow = Workflow(k8s, jobId)

    # Set driver status to completed so the workflow can progress to the next state
    foundPendingDriverStatus = False
    for driverStatus in workflow.data["status"]["drivers"]:
        if driverStatus["driverID"] == "tester" and driverStatus["watchState"] == state and driverStatus["status"] == "Error":
            print(f"updating workflow %s to complete state %s" % (str(jobId), state))
            driverStatus["completed"] = True
            driverStatus["status"] = "Completed"
            # The DWS webhook requires that the error message be cleared as well.
            del driverStatus["error"]
            foundPendingDriverStatus = True
            break

    assert foundPendingDriverStatus, "Driver not found with \"Error\" status"
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

@then(parsers.parse('the Workflow and job report fatal errors at the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow and job report errors at the <state> state."""

    expected_status = "Error"

    def driver_check(workflow):
        return driver_state_check(workflow, state, expected_status)

    workflow = Workflow(k8s, jobId)
    workflow.wait_until(
        f"the workflow {state} state shows a status of {expected_status}",
        lambda wf: driver_check(wf) is True
    )

    verify_job_status(slurmctld, jobId, state, expected_status)

@then(parsers.parse('the Workflow reports a fatal error in the {state:l} state'))
def _(k8s, slurmctld, jobId, state):
    """the Workflow reports a fatal error in the <state> state."""

    expected_status = "Error"

    def driver_check(workflow):
        return driver_state_check(workflow, state, expected_status)

    workflow = Workflow(k8s, jobId)
    workflow.wait_until(
        f"the workflow {state} state shows a status of {expected_status}",
        lambda wf: driver_check(wf) is True
    )

@then(parsers.parse("the job's {disposition:l} system comment contains the following:\n{message}"))
def _(slurmctld, jobId, disposition, message):
    assert disposition in ["final", "intermediate"], f"unknown disposition: {disposition}"
    must_be_gone = True if disposition == "final" else False
    _,out = slurmctld.get_final_job_state(jobId, must_be_gone)
    m = re.search(r'\n\s+SystemComment=(.*)\n\s+StdErr=', out, re.DOTALL)
    assert m is not None, f"Could not find SystemComment in job state from Slurm\n{out}"
    if message in m.group(1):
        print(f"Found \"{message}\" in SystemComment")
    assert message in m.group(1)
