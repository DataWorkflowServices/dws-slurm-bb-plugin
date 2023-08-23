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

@dws_states
Feature: Data Workflow Services State Progression
    Verify that the DWS-Slurm Burst Buffer Plugin progresses through Data
    Workflow Services states

    Scenario: The DWS-BB Plugin progresses through DWS states
        Given a job script:
            #!/bin/bash

            #DW Proposal action=wait
            #DW Setup action=wait
            #DW DataIn action=wait
            #DW PreRun action=wait
            #DW PostRun action=wait
            #DW DataOut action=wait
            #DW Teardown action=wait
            /bin/hostname

        When the job is run
        Then a Workflow has been created for the job
        And the Workflow and job progress to the Proposal state
        And the Workflow and job progress to the Setup state
        And the Workflow and job progress to the DataIn state
        And the Workflow and job progress to the PreRun state
        And the Workflow and job progress to the PostRun state
        And the Workflow and job progress to the DataOut state
        And the Workflow and job progress to the Teardown state
        And the job state is COMPLETED

    # DWS does not allow spaces in key/value pairs in directives. To skirt around this
    # constraint, the dws-test-driver replaces underscores ("_") in the message value with
    # spaces. This ensures that the dws-slurm-plugin can handle whitespace in error messages
    # It also makes it easier to check that the error is included in scontrol output.
    Scenario Outline: The DWS-BB Plugin can handle fatal driver errors before being canceled
        Given a job script:
            #!/bin/bash
            
            #DW <workflowState> action=error message=TEST_FATAL_ERROR severity=Fatal
            #DW Teardown action=wait
            /bin/hostname

        When the job is run
        Then a Workflow has been created for the job
        And the Workflow and job report fatal errors at the <workflowState> state
        And the job is canceled
        And the Workflow and job progress to the Teardown state
        And the job's final system comment contains the following:
            TEST FATAL ERROR
        
        Examples:
            # *** HEADER ***
            | workflowState |
            # *** VALUES ***
            | Proposal      |
            | Setup         |
            | DataIn        |
            | PostRun       | 
            | DataOut       | 

    # With the exception of PreRun, states will need to be canceled with the
    # "--hurry" flag to transition to the Teardown state. If 
    # "Flags=TeardownFailure" is set in burst_buffer.conf, then all states will
    # transition to Teardown without needing to be canceled
    Scenario Outline: The DWS-BB Plugin can handle fatal driver errors for PreRun
        Given a job script:
            #!/bin/bash
            
            #DW <workflowState> action=error message=TEST_FATAL_ERROR severity=Fatal
            #DW Teardown action=wait
            /bin/hostname

        When the job is run
        Then a Workflow has been created for the job
        And the Workflow reports a fatal error in the <workflowState> state
        And the Workflow and job progress to the Teardown state
        # Slurm moved it from PreRun/Error to Teardown without canceling
        # the job.  So the driver (this test) must cancel it.
        And the job is canceled
        And the job's final system comment contains the following:
            TEST FATAL ERROR
        
        Examples:
            # *** HEADER ***
            | workflowState |
            # *** VALUES ***
            | PreRun        |

    Scenario: The DWS-BB Plugin can handle fatal driver errors during Teardown
        Given a job script:
            #!/bin/bash
            
            #DW Teardown action=error message=TEST_FATAL_ERROR severity=Fatal
            /bin/hostname

        When the job is run
        Then a Workflow has been created for the job
        And the Workflow reports a fatal error in the Teardown state
        And the job's intermediate system comment contains the following:
            TEST FATAL ERROR
        # Eventually the driver (this test) must work through the Teardown
        # issues and complete that step.  Slurm has already marked the job
        # as completed and is now looping over slurm_bb_job_teardown() in
        # burst_buffer.lua.
        And the Workflow error is cleared from the Teardown state
