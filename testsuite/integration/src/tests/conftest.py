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

import os
import pytest
import secrets

from .slurmctld import Slurmctld
from kubernetes import client, config
from pytest_bdd import (
    given,
    scenarios,
    parsers,
    then,
    when,
)

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
    """a simple job script: <script>"""
    path = "/jobs/" + secrets.token_hex(5) + "-job.sh"
    with open(path, "w") as file:
        file.write(script)

    yield path

    os.remove(path)

@when('the job is run', target_fixture="jobId")
def _(slurmctld, script_path):
    """the job is run."""
    jobId,outputFilePath = slurmctld.submit_job(script_path)
    print("submitted job: " + str(jobId))

    yield jobId

    # remove the slurm output from the jobs folder
    slurmctld.remove_job_output(outputFilePath)

@then('the job completes successfully')
def _(slurmctld, jobId):
    """the job completes successfully."""
    state = slurmctld.get_final_job_state(jobId)
    assert state=="COMPLETED", "Unexpected Job State: " + state

