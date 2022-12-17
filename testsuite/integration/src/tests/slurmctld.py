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

import docker
import os
import warnings
from tenacity import *

# Submitting jobs can fail, occasionally, when the DWS webhook rejects the
# mutating webhook connection. This has only been observed using the
# directive rules included with  the dws-test-driver in a local kind
# environment. 
class JobSubmissionError(Exception):
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
    
    @retry(
        wait=wait_fixed(6),
        stop=stop_after_attempt(10),
        reraise=True
    )
    def submit_job(self,scriptPath):
        print("submit job")
        # The --wait option could be used here. However, other tests need to
        # asynchronously track the job status
        cmd = "sbatch --output=%(s)s.out --error=%(s)s.error.out %(s)s " % {"s": scriptPath}
        rc, out = self.exec_run(cmd)
        if rc != 0:
            print(str(rc), out)
            raise JobSubmissionError(out)
        jobId = int(out.split()[-1])
        return jobId, scriptPath + ".out", scriptPath + ".error.out"

    @retry(
        wait=wait_fixed(6),
        stop=stop_after_attempt(10),
        retry_error_callback=lambda retry_state: None
    )
    def remove_job_output(self, jobId, outputFilePath, errorFilePath):
        """
        The creation of the job's output file will sometimes lag behind the
        job's completion. This is a cleanup step, so retry the operation, but
        don't raise a test error.
        """
        if os.path.exists(errorFilePath):
            with open(errorFilePath, "r") as errorFile: print(errorFile.read())
            os.remove(errorFilePath)
        os.remove(outputFilePath)

    @retry(
        wait=wait_fixed(6),
        stop=stop_after_attempt(10),
        retry=retry_if_result(lambda state: state not in ["COMPLETED", "FAILED"]),
        retry_error_callback=lambda retry_state: retry_state.outcome.result()
    )
    def get_final_job_state(self, jobId):
        rc, out =self.exec_run("scontrol show job " + str(jobId))
        assert rc==0, "Could not get job state from Slurm:\n" + out
        job_prop_lines = out.split("\n")
        assert len(job_prop_lines) >= 4, "Could not find job: " + jobId + "\n" + out
        for job_prop_line in job_prop_lines:
            properties = job_prop_line.split()
            for prop in properties:
                keyVal = prop.split("=")
                assert len(keyVal) == 2, "Could not parse state from: " + out
                if keyVal[0] == "JobState":
                    return keyVal[1], out
        assert False, "Could not parse state from: " + out

    def get_workflow_status(self, jobId):
        rc, out = self.exec_run("scontrol show bbstat workflow " + str(jobId))
        assert rc ==0, "Could not get job status from Slurm:\n" + out
        status = {}
        properties = out.split()
        for prop in properties:
            keyVal = prop.split("=")
            assert len(keyVal) == 2, "Could not parse statuses from: " + out
            status[keyVal[0]] = keyVal[1]

        return status