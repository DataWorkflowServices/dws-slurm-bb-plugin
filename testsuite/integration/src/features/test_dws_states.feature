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
        And a Workflow is created for the job
        #Then the job's temporary Workflow is not found
        Then the Workflow and job progress to the Proposal state
        And the Workflow and job progress to the Setup state
        And the Workflow and job progress to the DataIn state
        And the Workflow and job progress to the PreRun state
        And the Workflow and job progress to the PostRun state
        And the Workflow and job progress to the DataOut state
        And the Workflow and job progress to the Teardown state
        And the job is COMPLETED

    @todo
    Scenario: The DWS-BB Plugin can handle DWS driver errors
        Given a job script:
            #!/bin/bash

            #DW <state> action=error message=TEST_ERROR
            #DW Teardown action=wait
            /bin/hostname

        When the job is run
        And a Workflow is created for the job
        Then the Workflow and job progress to the Teardown state
        And the job shows an error with message "TEST ERROR"
        
        Examples:
            # *** HEADER ***
            | state    |
            # *** VALUES ***
            | Proposal |
            | Setup    |
            | DataIn   |
            | PreRun   |
            | PostRun  |
            | DataOut  |

    @todo
    Scenario: The DWS-BB Plugin can handle a DWS driver error during Teardown
        Given a job script:
            #!/bin/bash

            #DW Teardown action=error message=TEST_ERROR
            /bin/hostname

        When the job is run
        And a Workflow is created for the job
        Then the job shows an error with message "TEST ERROR"

    @todo
    Scenario: The DWS-BB Plugin can cancel jobs
        Given a job script:
            #!/bin/bash

            #DW <state> action=wait
            #DW Teardown action=wait
            /bin/hostname

        When the job is run
        And a Workflow is created for the job
        And the Workflow and job progress to the <state> state
        And the job is canceled with the hurry flag set to <hurry_flag>
        Then the Workflow and job progress to the Teardown state
        And the Workflow's hurry flag is set to <hurry_flag>

        Examples:
            # *** HEADER ***
            | state    | hurry_flag |
            # *** VALUES ***
            | Proposal | false      |
            | Setup    | false      |
            | DataIn   | false      |
            | PreRun   | false      |
            | PostRun  | false      |
            | DataOut  | false      |
            | Proposal | true       |
            | Setup    | true       |
            | DataIn   | true       |
            | PreRun   | true       |
            | PostRun  | true       |
            | DataOut  | true       |