#
# Copyright 2022-2024 Hewlett Packard Enterprise Development LP
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
import re
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

    def submit_job(self, script_path):
        # The --wait option could be used here. However, other tests need to
        # asynchronously track the job status
        cmd = f"sbatch -vv --output={script_path}.out --error={script_path}.error.out {script_path}"
        rc, out = self.exec_run(cmd)
        if rc != 0:
            print("BEGIN Job submission error")
            print(out + "\n")
            print("END Job submission error")
            raise JobSubmissionError(out)
        print("BEGIN Job submission")
        print(out + "\n")
        print("END Job submission")
        job_id = int(out.split()[-1])
        return job_id, script_path + ".out", script_path + ".error.out"

    def remove_job_output(self, output_file_path, error_file_path):
        """
        The creation of the job's output file will sometimes lag behind the
        job's completion. This is a cleanup step, so retry the operation, but
        don't raise a test error.
        """
        if os.path.exists(error_file_path):
            with open(error_file_path, "r", encoding="utf-8") as error_file:
                print(error_file.read())
            os.remove(error_file_path)
        if os.path.exists(output_file_path):
            os.remove(output_file_path)

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

    def scontrol_show_job(self, jobId):
        rc, out = self.exec_run("scontrol show job " + str(jobId))
        assert rc==0, "Could not get job state from Slurm:\n" + out

        job_prop_lines = out.split("\n")
        assert len(job_prop_lines) >= 4, "Could not find job: " + jobId + "\n" + out
        for job_prop_line in job_prop_lines:
            properties = job_prop_line.split()
            for prop in properties:
                key_val = prop.split("=")
                assert len(key_val) == 2, "Could not parse state from: " + out
                if key_val[0] == "JobState":
                    print("JobState=" + key_val[1])
                    return key_val[1], out
        assert False, "Could not parse state from: " + out

    def wait_until_job_has_been_x(self, jobId, job_state_wanted, script_path):
        cnt = 0
        while cnt < 5:
            job_state, out = self.scontrol_show_job(jobId)
            print(f"Found \"{job_state}\" in JobState")
            if job_state == job_state_wanted:
                break
            if job_state == "FAILED" and job_state_wanted == "COMPLETED":
                # We're in the weeds. Drop a clue.
                print("BEGIN scontrol show job")
                print(out)
                print("END scontrol show job")
                print("BEGIN get workflows")
                rc,out = self.exec_run("kubectl --kubeconfig /etc/slurm/slurm-dws.kubeconfig get workflows -A")
                print(f"rc = {rc}\n{out}")
                print("END get workflows")
                print("BEGIN job output file")
                rc,out = self.exec_run(f"cat {script_path}.out")
                print("END job output file")
                print("BEGIN job error output file")
                rc,out = self.exec_run(f"cat {script_path}.error.out")
                print("END job error output file")
                print("BEGIN slurmctld log")
                os.system("docker logs slurmctld 2>&1")
                print("END slurmctld log")
                assert job_state == job_state_wanted # stop looping now

            cnt += 1
            time.sleep(2)
        assert job_state == job_state_wanted

    @retry(
        wait=wait_fixed(2),
        stop=stop_after_attempt(5)
    )
    def wait_until_job_system_comment(self, jobId, message):
        _,out = self.scontrol_show_job(jobId)
        m = re.search(r'\n\s+SystemComment=(.*)\n\s+StdErr=', out, re.DOTALL)
        assert m is not None, f"Could not find SystemComment in job state from Slurm\n{out}"
        if message in m.group(1):
            print(f"Found \"{message}\" in SystemComment")
        assert message in m.group(1)

    def scontrol_show_bbstat(self, jobId):
        rc, out = self.exec_run("scontrol show bbstat workflow " + str(jobId))
        assert rc == 0, "Could not get job status from Slurm:\n" + out
        # This next check is because the scontrol command does not exit non-zero
        # when slurm_bb_get_status() in burst_buffer.lua returns slurm.ERROR.
        assert 'Error running slurm_bb_get_status' not in out, f"Could not find workflow {jobId}:\n" + out

        status = {}
        properties = out.split()
        for prop in properties:
            key_val = prop.split("=")
            assert len(key_val) == 2, "Could not parse statuses from: " + out
            status[key_val[0]] = key_val[1]

        return status
