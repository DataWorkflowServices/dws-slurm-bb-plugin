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
import time
import docker
from tenacity import *

# Submitting jobs can fail, occasionally, when the DWS webhook rejects the
# mutating webhook connection. This has only been observed using the
# directive rules included with  the dws-test-driver in a local kind
# environment.
class JobSubmissionError(Exception):
    pass

class JobCancelError(Exception):
    pass

class JobNotCompleteError(Exception):
    pass

class Slurmctld:
    def __init__(self):
        self.slurmctld = docker.from_env().containers.get("slurmctld")

    def exec_run(self, cmd):
        print("Slurmctld exec_run: " + cmd)
        exec_cmd = cmd.split()
        rc,out = self.slurmctld.exec_run(
            exec_cmd, 
            user="slurm",
            workdir="/jobs"
        )
        return rc,str(out, 'utf-8')
    
    def submit_job(self, scriptPath):
        # The --wait option could be used here. However, other tests need to
        # asynchronously track the job status
        cmd = f"sbatch --output={scriptPath}.out --error={scriptPath}.error.out {scriptPath}"
        rc, out = self.exec_run(cmd)
        if rc != 0:
            raise JobSubmissionError(out)
        jobId = int(out.split()[-1])
        return jobId, scriptPath + ".out", scriptPath + ".error.out"

    def cancel_job(self, jobId, hurry_flag=False):
        print("cancel job" + str(jobId))
        cmd = "scancel --hurry %s" % str(jobId)
        rc, out = self.exec_run(cmd)
        if rc != 0:
            raise JobCancelError(out)

    def remove_job_output(self, jobId, outputFilePath, errorFilePath):
        """
        The creation of the job's output file will sometimes lag behind the
        job's completion. This is a cleanup step, so retry the operation, but
        don't raise a test error.
        """
        if os.path.exists(errorFilePath):
            with open(errorFilePath, "r", encoding="utf-8") as errorFile:
                print(errorFile.read())
            os.remove(errorFilePath)
        if os.path.exists(outputFilePath):
            os.remove(outputFilePath)

    @retry(
        wait=wait_fixed(2),
        stop=stop_after_attempt(30)
    )
    def wait_until_workflow_is_gone(self, jobId):
        _, out = self.exec_run("scontrol show bbstat workflow " + str(jobId))
        # We'd prefer to check that rc==0, but the scontrol command does not
        # exit non-zero when slurm_bb_get_status() in burst_buffer.lua returns
        # slurm.ERROR.
        if 'Error running slurm_bb_get_status' not in out:
            print(f"Workflow {jobId} still exists: " + out)
            raise JobNotCompleteError()

    @retry(
        wait=wait_fixed(2),
        stop=stop_after_attempt(30),
        retry=retry_if_result(lambda state: state[0] not in ["COMPLETED", "FAILED", "CANCELLED"]),
        retry_error_callback=lambda retry_state: retry_state.outcome.result()
    )
    def get_final_job_state(self, jobId, must_be_gone=True):
        # When the job is finished, the workflow should not exist.
        if must_be_gone:
            self.wait_until_workflow_is_gone(jobId)
        else:
            time.sleep(5) # wait for workflow info to be transferred to the job

        rc, out = self.exec_run("scontrol show job " + str(jobId))
        assert rc==0, "Could not get job state from Slurm:\n" + out

        job_prop_lines = out.split("\n")
        assert len(job_prop_lines) >= 4, "Could not find job: " + jobId + "\n" + out
        for job_prop_line in job_prop_lines:
            properties = job_prop_line.split()
            for prop in properties:
                keyVal = prop.split("=")
                assert len(keyVal) == 2, "Could not parse state from: " + out
                if keyVal[0] == "JobState":
                    print("JobState=" + keyVal[1])
                    return keyVal[1], out
        assert False, "Could not parse state from: " + out

    def get_workflow_status(self, jobId):
        rc, out = self.exec_run("scontrol show bbstat workflow " + str(jobId))
        assert rc == 0, "Could not get job status from Slurm:\n" + out
        # This next check is because the scontrol command does not exit non-zero
        # when slurm_bb_get_status() in burst_buffer.lua returns slurm.ERROR.
        assert 'Error running slurm_bb_get_status' not in out, f"Could not find workflow {jobId}:\n" + out

        status = {}
        properties = out.split()
        for prop in properties:
            keyVal = prop.split("=")
            assert len(keyVal) == 2, "Could not parse statuses from: " + out
            status[keyVal[0]] = keyVal[1]

        return status
