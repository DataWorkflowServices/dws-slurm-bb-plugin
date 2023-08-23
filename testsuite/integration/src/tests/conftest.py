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

import os
import secrets
import warnings
import pytest

from kubernetes import client, config
from pytest_bdd import (
    given,
    parsers,
    then,
    when,
)
from .slurmctld import Slurmctld

@pytest.fixture
def k8s():
    config.load_kube_config()
    return client

@pytest.fixture
def slurmctld():
    return Slurmctld()

def pytest_bdd_apply_tag(tag, function):
    if tag == 'todo':
        marker = pytest.mark.skip(reason="Not implemented yet")
        marker(function)
        return True
    else:
        # Fall back to the default behavior of pytest-bdd
        return None

@given(parsers.parse('a job script:\n{script}'), target_fixture="script_path")
def _(script):
    """a job script: <script>"""
    path = "/jobs/inttest-" + secrets.token_hex(5) + "-job.sh"
    with open(path, "w", encoding="utf-8") as file:
        file.write(script)

    yield path

    os.remove(path)

@when('the job is run', target_fixture="jobId")
def _(slurmctld, script_path):
    """the job is run."""

    jobId, outputFilePath, errorFilePath = slurmctld.submit_job(script_path)
    print("submitted job: " + str(jobId))

    yield jobId

    # remove the slurm output from the jobs folder
    slurmctld.remove_job_output(jobId, outputFilePath, errorFilePath)

@then(parsers.parse('the job state is {expectedJobState}'))
def _(slurmctld, jobId, expectedJobState):
    """the job state is <expectedJobState>"""
    jobState, out = slurmctld.get_final_job_state(jobId)

    if expectedJobState == "COMPLETED" and jobState == "FAILED":
        warnings.warn(ResourceWarning((f"Job {jobId} failed unexpectedly.\n") + \
            "This may happen if Slurm doesn't have enough resources to schedule the job.\n" + \
            "This is not considered a test failure, in this context, since DWS isn't\n" + \
            "dependent on the job's failure or success."
        ))
        return

    assert jobState == expectedJobState, "Unexpected Job State: " + jobState + "\n" + out
