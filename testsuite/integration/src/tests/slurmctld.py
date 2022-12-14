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
from tenacity import *

# Submitting jobs can fail, occasionally, wen the DWS webhook rejects the
# mutating webhook connection. This has only been observed using the
# directive rulese included with  the dws-test-driver in a local kind
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
        cmd = "sbatch --output=%s.out %s " % (scriptPath, scriptPath)
        rc, out = self.exec_run(cmd)
        if rc != 0:
            raise JobSubmissionError(out)
        jobId = int(out.split()[-1])
        return jobId, scriptPath + ".out"

    @retry(
        wait=wait_fixed(6),
        stop=stop_after_attempt(10),
        reraise=True
    )
    def remove_job_output(self, outputFilePath):
        os.remove(outputFilePath)

    @retry(
        wait=wait_fixed(6),
        stop=stop_after_attempt(10),
        retry=retry_if_result(lambda state: state == "RUNNING"),
        retry_error_callback=lambda retry_state: retry_state.outcome.result()
    )
    def get_final_job_state(self, jobId):
        rc, out = self.exec_run("sacct -b -j " + str(jobId))
        assert rc==0, "Could not get job state from Slurm:\n" + out
        # sacct returns a table. entries start on line 3
        job_table = out.split("\n")
        assert len(job_table) >= 3, "Could not find job: " + jobId
        # state is in second column
        state = job_table[3].split()[1]
        return state

    def get_job_status(self, jobId):
        rc, out = self.exec_run("scontrol show bbstat workflow " + str(jobId))
        assert rc ==0, "Could not get job status from Slurm:\n" + out
        
        status = {}
        properties = out.split()
        for prop in properties:
            keyVal = prop.split("=")
            assert len(keyVal) == 2, "Could not parse statuses from: " + out
            status[keyVal[0]] = keyVal[1]

        return status