-- 
--  Copyright 2022 Hewlett Packard Enterprise Development LP
--  Other additional copyright holders may be indicated within.
-- 
--  The entirety of this work is licensed under the Apache License,
--  Version 2.0 (the "License"); you may not use this file except
--  in compliance with the License.
-- 
--  You may obtain a copy of the License at
-- 
--      http://www.apache.org/licenses/LICENSE-2.0
-- 
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

require("burst_buffer/burst_buffer")

math.randomseed(os.time())

local IS_REAL_K8S = false
local IS_NOT_K8S = true
if os.getenv("REAL_K8S") ~= nil then
	-- Expect to be running against a live K8s environment, with kubectl
	-- and DWS operator.
	print("Running live")
	IS_REAL_K8s = true
	IS_NOT_K8S = false
end

local REAL_SLURM = true
if os.getenv("MOCK_SLURM") ~= nil then
	-- Provide a few logging functions and variables that would have been
	-- provided by a live slurm environment.
	REAL_SLURM = false
	_G.slurm = {
		ERROR = -1,
		SUCCESS = 0,
		log_info = function(...) print(string.format(...)) end,
		log_error = function(...) print(string.format(...)) end,
	}
end

local CRDFILE = os.getenv("CRDFILE")
if CRDFILE == nil and IS_NOT_K8S then
	-- The CRD location in the container image.
	CRDFILE = "/dws/config/crd/bases/dws.cray.hpe.com_workflows.yaml"
end

local VALIDATOR = os.getenv("VALIDATOR")
if VALIDATOR == nil and IS_NOT_K8S then
	-- The validator tool's location in the container image.
	VALIDATOR = "/bin/validate"
end

-- get_workflow_obj will instantiate a DWS object with the given name.
local function get_workflow_obj(workflow_name)
	local workflow = DWS(workflow_name)
	local wf_yaml = workflow.yaml
	assert.is_not_nil(string.find(wf_yaml, "kind: Workflow"))
	assert.is_not_nil(string.find(wf_yaml, "name: WF_NAME"))
	return workflow
end

-- verify_filled_template verifies fields in the DWS template.
local function verify_filled_template(workflow, wlmID, jobID, userID, groupID)
	local wf_yaml = workflow.yaml
	assert.is_not_nil(string.find(wf_yaml, "name: " .. workflow.name))
	assert.is_not_nil(string.find(wf_yaml, [[wlmID: "]] .. wlmID .. [["]]))
	assert.is_not_nil(string.find(wf_yaml, "jobID: " .. jobID))
	assert.is_not_nil(string.find(wf_yaml, "userID: " .. userID))
	assert.is_not_nil(string.find(wf_yaml, "groupID: " .. groupID))
end

-- fill_template fills the DWS template with a 'dwd' parameter.
local function fill_template(workflow, wlmID, jobID, userID, groupID, dwd)
	workflow:initialize(wlmID, jobID, userID, groupID, dwd)
	verify_filled_template(workflow, wlmID, jobID, userID, groupID)
	local wf_yaml = workflow.yaml
	-- Our caller will verify the dwDirectives value.
end

-- write_job_script will write the text of a job's script to a specified file.
local function write_job_script(job_script_name, job_text)
	local file = io.open(job_script_name, "w")
	file:write(job_text)
	file:close()
end

describe("The dws library initializer", function()

	local workflow
	local workflow_name
	local wlmID
	local jobID
	local userID
	local groupID

	before_each(function()
		workflow_name = "check" .. math.random(1000)
		workflow = get_workflow_obj(workflow_name)
		wlmID = "5f239" .. math.random(1000)
		jobID = math.random(1000)
		userID = math.random(1000)
		groupID = math.random(1000)
	end)

	it("can handle a nil value for dwd", function()
		fill_template(workflow, wlmID, jobID, userID, groupID, nil)
		assert.is_not_nil(string.find(workflow.yaml, "dwDirectives: %[%]"))
	end)

	it("can handle an empty array value for dwd", function()
		local dwd = {}
		fill_template(workflow, wlmID, jobID, userID, groupID, dwd)
		assert.is_not_nil(string.find(workflow.yaml, "dwDirectives: %[%]"))
	end)

	it("can handle a non-empty array value for dwd", function()
		local dwd = {}
		dwd[1] = "#BB_LUA line 1"
		dwd[2] = "#BB_LUA line 2"
		fill_template(workflow, wlmID, jobID, userID, groupID, dwd)
		assert.is_not_nil(string.find(workflow.yaml, "dwDirectives:\n  %- " .. dwd[1] .. "\n" .. "  %- " .. dwd[2] .. "\n"))
	end)
end)

describe("The dws library", function()
	local yaml_name
	local yaml_name_exists
	local workflow_name
	local wlmID
	local jobID
	local userID
	local groupID
	local workflow
	local status_check_count -- simulated delay in dws operator
	local dwd

	local make_workflow_yaml = function()
		workflow = get_workflow_obj(workflow_name)
		fill_template(workflow, wlmID, jobID, userID, groupID, dwd)
	end

	before_each(function()
		status_check_count = 3

		workflow_name = "check" .. math.random(1000)
		wlmID = "5f239" .. math.random(1000)
		jobID = math.random(1000)
		userID = math.random(1000)
		groupID = math.random(1000)
		dwd = {}

		yaml_name = os.tmpname()
		yaml_name_exists = true

		dwsmq_reset()
	end)

	after_each(function()
		if yaml_name_exists == true then
			os.remove(yaml_name)
			yaml_name_exists = false
		end
	end)

	context("simple create/delete cases", function()

		local resource_exists

		before_each(function()
			resource_exists = false

			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			assert.is_true(done, err)

			if IS_NOT_K8S then
				stub(io, "popen")
			end
		end)

		after_each(function()
			if resource_exists then
				-- If resource_exists is still true here then
				-- we already have an error condition.  Try
				-- to clean it up but don't bother checking for
				-- more errors.
				workflow:delete()
			end
		end)

		after_each(function()
			if IS_NOT_K8S then
				io.popen:revert()
			end
		end)

		it("can apply and delete a workflow resource", function()
			local result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " created\n"

			dwsmq_enqueue(true, result_wanted)
			local done, err = workflow:apply(yaml_name)
			resource_exists = done
			assert.is_true(done, err)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
				io.popen:clear()
			end
			assert.is_equal(err, result_wanted)

			result_wanted = 'workflow.dws.cray.hpe.com "' .. workflow_name .. '" deleted\n'

			dwsmq_enqueue(true, result_wanted)
			if IS_NOT_K8S then
				io.popen:clear()
			end
			done, err = workflow:delete()
			resource_exists = done
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			assert.is_true(done, err)
			assert.is_equal(err, result_wanted)
		end)
	end)

	context("state progression cases", function()

		-- If true then the resource is expected to exist. (Creation is expected to succeed.)
		local expect_exists 

		-- If true then the resource does exist. (Creation was successful.)
		local resource_exists

		-- If true then expect errors that indicate a state was skipped.
		local skip_state

		-- If true then expect errors that indicate an invalid state name.
		local invalid_state

		-- Save the YAML for the resource.  Initialize some bools.
		-- Setup a stub for io.popen if not running live.
		before_each(function()
			resource_exists = false
			expect_exists = true
			skip_state = false
			invalid_state = false

			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			assert.is_true(done, err)

			if IS_NOT_K8S then
				stub(io, "popen")
			end
		end)

		-- Create the resource.
		before_each(function()
			local result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " created\n"

			dwsmq_enqueue(true, result_wanted)
			local done, err = workflow:apply(yaml_name)
			resource_exists = done
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
				io.popen:clear()
			end
			assert.is_true(done, err)
		end)

		-- Delete the resource.
		after_each(function()
			if resource_exists and expect_exists then
				local result_wanted = 'workflow.dws.cray.hpe.com "' .. workflow_name .. '" deleted\n'

				dwsmq_reset()
				dwsmq_enqueue(true, result_wanted)
				if IS_NOT_K8S then
					io.popen:clear()
				end
				local done, err = workflow:delete()
				resource_exists = done
				if IS_NOT_K8S then
					assert.stub(io.popen).was_called()
				end
				assert.is_true(done, err)
				assert.is_equal(err, result_wanted)
			elseif resource_exists then
				-- We didn't expect to create a resource, but
				-- we got one. So we're already in an error
				-- condition.  Just try to clean up the mess.
				workflow:delete()
			end
		end)

		-- Undo the stub for io.popen, if appropriate.
		after_each(function()
			if IS_NOT_K8S then
				io.popen:revert()
			end
		end)

		-- Progress the resource to the desired state.  Attempt to set
		-- the hurry flag on the state, if indicated.
		local set_desired_state = function(new_state, hurry)
			local ret_wanted = true
			local result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " patched\n"

			if skip_state == true then
				result_wanted = 'Error from server (Spec.DesiredState: Invalid value: "' .. new_state .. '": states cannot be skipped): admission webhook "vworkflow.kb.io" denied the request: Spec.DesiredState: Invalid value: "' .. new_state .. '": states cannot be skipped\n'

				ret_wanted = false
			elseif invalid_state == true then
				result_wanted = 'The Workflow "' .. workflow_name .. '" is invalid: spec.desiredState: Unsupported value: "' .. new_state .. '": supported values: "Proposal", "Setup", "DataIn", "PreRun", "PostRun", "DataOut", "Teardown"\n'
				ret_wanted = false
			end

			dwsmq_enqueue(ret_wanted, result_wanted)

			local done, err = workflow:set_desired_state(new_state, hurry)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			assert.is_equal(done, ret_wanted)
			assert.is_equal(err, result_wanted)
		end

		-- Wait for the resource state to progress to "Completed" state.
		local wait_for_state = function(state)
			local result_wanted = "desiredState=" .. state .. "\ncurrentState=" .. state .. "\nstatus=Completed\n"

			dwsmq_enqueue(true, result_wanted)
			local done, status, err = workflow:wait_for_status_complete(60)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			assert.is_true(done, err)
			assert.is_equal(status["desiredState"], state)
			assert.is_equal(status["currentState"], state)
			assert.is_equal(status["status"], "Completed")
		end

		-- Check that the resource's hurry flag is as desired.
		local check_hurry = function(desired_hurry)
			local result_wanted = "false"
			if desired_hurry == true then
				result_wanted = "true"
			end

			dwsmq_enqueue(true, result_wanted)
			local done, hurry = workflow:get_hurry()
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			assert.is_true(done, hurry)
			assert.is_equal(desired_hurry, hurry)
		end

		-- Helper to wrap setting the state with waiting for the state.
		local set_desired_state_and_wait = function(new_state)
			set_desired_state(new_state)
			wait_for_state(new_state)
		end


		it("completes proposal state", function()
			wait_for_state("Proposal")
		end)

		it("progresses from proposal to setup state", function()
			wait_for_state("Proposal")

			set_desired_state_and_wait("Setup")
		end)

		it("progresses from proposal to teardown state", function()
			wait_for_state("Proposal")

			set_desired_state_and_wait("Teardown")
			check_hurry(false)
		end)

		it("progresses from proposal to teardown state in a hurry", function()
			wait_for_state("Proposal")

			set_desired_state("Teardown", true)
			wait_for_state("Teardown")
			check_hurry(true)
		end)

		it("progresses from proposal through all states", function()
			wait_for_state("Proposal")

			local states = {
				"Setup",
				"DataIn",
				"PreRun",
				"PostRun",
				"DataOut",
				"Teardown",
			}

			for i in pairs(states) do
				print("Next state", states[i])
				set_desired_state_and_wait(states[i])
			end
			check_hurry(false)
		end)

		it("progresses to setup and waits in one step", function()
			wait_for_state("Proposal")

			local new_state = "Setup"

			local set_result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " patched\n"
			local wait_result_wanted = "desiredState=" .. new_state .. "\ncurrentState=" .. new_state .. "\nstatus=Completed\n"

			dwsmq_enqueue(true, set_result_wanted)
			dwsmq_enqueue(true, wait_result_wanted)

			expect_exists = true
			if IS_NOT_K8S then
				io.popen:clear()
			end
			local done, err = workflow:set_workflow_state_and_wait(new_state)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called(2)
			end
			assert.is_true(done, err)
		end)

		context("negative cases for state order", function()

			before_each(function()
				expect_exists = false
			end)

			it("can detect an invalid state transition error", function()
				wait_for_state("Proposal")

				skip_state = true
				set_desired_state("PreRun")
			end)

			it("can detect an invalid state name error", function()
				wait_for_state("Proposal")

				invalid_state = true
				set_desired_state("prerun")
			end)
		end)
	end)

	context("negative file save cases", function()

		before_each(function()
			make_workflow_yaml()
			-- Remove the one created by os.tmpname().
			os.remove(yaml_name)
			yaml_name_exists = false
			yaml_name = "/nosuchdir/tmpfile"
		end)

		it("cannot save a file to nonexistent directory", function()
			local done, err = workflow:save(yaml_name)
			assert.is_not_true(done, err)
		end)
	end)

	context("negative yaml cases", function()

		local resource_exists

		-- The error from k8s has a lot of content, so let's
		-- just look for the beginning of it.
		local result_wanted = "Error from server"

		before_each(function()
			resource_exists = false

			if IS_NOT_K8S then
				stub(io, "popen")
			end
		end)

		after_each(function()
			dwsmq_enqueue(false, result_wanted)
			local done, err = workflow:apply(yaml_name)
			resource_exists = done
			assert.is_not_true(done)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			assert.is_true(string.find(err, result_wanted) ~= nil, err)
		end)

		after_each(function()
			if resource_exists then
				-- If resource_exists is still true here then
				-- we already have an error condition.  Try
				-- to clean it up but don't bother checking for
				-- more errors.
				workflow:delete()
			end
		end)

		after_each(function()
			if IS_NOT_K8S then
				io.popen:revert()
			end
		end)

		it("cannot apply an invalid jobID", function()

			jobID = "bad job"
			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			assert.is_true(done, err)
		end)

		it("cannot apply an invalid userID", function()
			userID = "bad user"
			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			assert.is_true(done, err)
		end)

		it("cannot apply an invalid groupID", function()
			groupID = "bad group"
			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			assert.is_true(done, err)
		end)
	end)
end)

describe("Burst buffer helpers", function()

	local job_script_name
	local job_script_exists

	before_each(function()
		job_script_name = os.tmpname()
		job_script_exists = true
	end)

	after_each(function()
		if job_script_exists == true then
			os.remove(job_script_name)
			job_script_exists = false
		end
	end)

	context("find_dw_directives", function()
		it("handles lack of directives in job script", function()
			local job_script = "#!/bin/bash\nsrun application.sh\n"

			write_job_script(job_script_name, job_script)

			local out_dwd = find_dw_directives(job_script_name)
			assert.is_not_nil(out_dwd)

			local cnt = 0
			for k in ipairs(out_dwd) do
				cnt = cnt + 1
			end
			assert.is_equal(cnt, 0)
		end)

		it("finds directives in job script", function()
			local in_dwd = {}
			in_dwd[1] = "#BB_LUA pool=pool1 capacity=1K"
			in_dwd[2] = "#BB_LUA pool=pool2 capacity=1K"
			local job_script = "#!/bin/bash\n" .. in_dwd[1] .. "\n" .. in_dwd[2] .. "\nsrun application.sh\n"

			write_job_script(job_script_name, job_script)

			local out_dwd = find_dw_directives(job_script_name)
			assert.is_not_nil(out_dwd)

			local cnt = 0
			for k in ipairs(out_dwd) do
				cnt = cnt + 1
			end
			assert.is_equal(cnt, 2)
			assert.is_equal(in_dwd[1], out_dwd[1])
			assert.is_equal(in_dwd[2], out_dwd[2])
		end)
	end)

	context("make_workflow", function()
		local workflow
		local workflow_name
		local jobID
		local userID
		local groupID

		-- If true then the resource is expected to exist. (Creation is expected to succeed.)
		local expect_exists 

		-- If true then the resource does exist. (Creation was successful.)
		local resource_exists

		before_each(function()
			resource_exists = false
			expect_exists = false

			jobID = math.random(1000)
			userID = math.random(1000)
			groupID = math.random(1000)
			workflow_name = make_workflow_name(jobID)
			workflow = DWS(workflow_name)

			if IS_NOT_K8S then
				stub(io, "popen")
			end
		end)

		after_each(function()
			if resource_exists and expect_exists then
				local result_wanted = 'workflow.dws.cray.hpe.com "' .. workflow_name .. '" deleted\n'

				dwsmq_reset()
				dwsmq_enqueue(true, result_wanted)
				if IS_NOT_K8S then
					io.popen:clear()
				end
				local done, err = workflow:delete()
				resource_exists = done
				if IS_NOT_K8S then
					assert.stub(io.popen).was_called()
				end
				assert.is_true(done, err)
				assert.is_equal(err, result_wanted)

			elseif resource_exists then
				-- We didn't expect to create a resource, but
				-- we got one. So we're already in an error
				-- condition.  Just try to clean up the mess.
				workflow:delete()
			end
		end)

		after_each(function()
			if IS_NOT_K8S then
				io.popen:revert()
			end
		end)

		it("can create workflow from job script lacking directives", function()
			local job_script = "#!/bin/bash\nsrun application.sh\n"

			write_job_script(job_script_name, job_script)

			local result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " created\n"

			dwsmq_enqueue(true, result_wanted)

			local done, err = make_workflow(workflow, job_script_name, jobID, userID, groupID)
			resource_exists = done
			expect_exists = true
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			if err ~= nil then
				print(err)
			end
			assert.is_true(done, err)
			verify_filled_template(workflow, WLMID_PLACEHOLDER, jobID, userID, groupID)
			assert.is_not_nil(string.find(workflow.yaml, "dwDirectives: %[%]"))
		end)

		it("can create workflow from job script with directives", function()
			local in_dwd = {}
			in_dwd[1] = "#BB_LUA pool=pool1 capacity=1K"
			in_dwd[2] = "#BB_LUA pool=pool2 capacity=1K"
			local job_script = "#!/bin/bash\n" .. in_dwd[1] .. "\n" .. in_dwd[2] .. "\nsrun application.sh\n"

			write_job_script(job_script_name, job_script)

			-- The DWS environment does not have a ruleset for
			-- the BB_LUA directives, so we should expect an error.
			-- We'll look for only a small piece of the error
			-- message here.
			local result_wanted = "unable to find ruleset"
			dwsmq_enqueue(false, result_wanted)

			local done, err = make_workflow(workflow, job_script_name, jobID, userID, groupID)
			resource_exists = done
			expect_exists = false
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			print("Expect an error message here: " .. err)
			assert.is_not_true(done, err)
			assert.is_not_nil(string.find(err, result_wanted))

			-- Despite the error from DWS about the missing
			-- ruleset, we should still have a valid-looking
			-- Workflow YAML.
			verify_filled_template(workflow, WLMID_PLACEHOLDER, jobID, userID, groupID)
			assert.is_not_nil(string.find(workflow.yaml, "dwDirectives:\n  %- " .. in_dwd[1] .. "\n" .. "  %- " .. in_dwd[2] .. "\n"))
		end)
	end)
end)

describe("Slurm API", function()

	local job_script_name
	local job_script_exists
	local jobID
	local userID
	local groupID
	local workflow_name
	local workflow

	-- If true then the resource is expected to exist. (Creation is expected to succeed.)
	local expect_exists 

	-- If true then the resource does exist. (Creation was successful.)
	local resource_exists

	before_each(function()
		jobID = math.random(1000)
		userID = math.random(1000)
		groupID = math.random(1000)
		workflow_name = make_workflow_name(jobID)

		job_script_name = os.tmpname()
		job_script_exists = true

		resource_exists = false
		expect_exists = false

		if IS_NOT_K8S then
			stub(io, "popen")
		end
	end)

	after_each(function()
		if job_script_exists == true then
			os.remove(job_script_name)
			job_script_exists = false
		end
	end)

	after_each(function()
		if resource_exists and expect_exists then
			local result_wanted = 'workflow.dws.cray.hpe.com "' .. workflow_name .. '" deleted\n'

			dwsmq_reset()
			dwsmq_enqueue(true, result_wanted)
			if IS_NOT_K8S then
				io.popen:clear()
			end
			local done, err = workflow:delete()
			resource_exists = done
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called()
			end
			assert.is_true(done, err)
			assert.is_equal(err, result_wanted)

		elseif resource_exists then
			-- We didn't expect to create a resource, but
			-- we got one. So we're already in an error
			-- condition.  Just try to clean up the mess.
			workflow:delete()
		end

	end)

	after_each(function()
		if IS_NOT_K8S then
			io.popen:revert()
		end
	end)

	it("slurm_bb_job_process can validate a workflow from a job script lacking directives", function()
		local job_script = "#!/bin/bash\nsrun application.sh\n"

		write_job_script(job_script_name, job_script)

		-- slurm_bb_job_process() is creating a temp name for the
		-- resource and deleting it.  If it bails before it can delete
		-- the temp resource, we have no way of knowing where it bailed
		-- or how to find the name of the temp resource, so we are not
		-- able to do the cleanup ourselves.  This also means none of
		-- the work it performs can be carried over to the next stage.
		--
		-- In slurm_bb_setup() we will recreate the resource using the
		-- job ID in the name so it can be found in the remaining
		-- stages.
		--
		-- A future release of Slurm will include more args to the
		-- slurm_bb_job_process() function and we'll be able to change
		-- all of this.

		local ret, err = slurm_bb_job_process(job_script_name)
		if IS_NOT_K8S then
			assert.stub(io.popen).was_called(2)
		end
		assert.is_equal(ret, slurm.SUCCESS)
		assert.is_nil(err, err)
	end)

	it("slurm_bb_job_process can validate workflow from job script with directives", function()
		local in_dwd = {}
		in_dwd[1] = "#BB_LUA pool=pool1 capacity=1K"
		in_dwd[2] = "#BB_LUA pool=pool2 capacity=1K"
		local job_script = "#!/bin/bash\n" .. in_dwd[1] .. "\n" .. in_dwd[2] .. "\nsrun application.sh\n"
		write_job_script(job_script_name, job_script)

		-- The DWS environment does not have a ruleset for
		-- the BB_LUA directives, so we should expect an error.
		-- We'll look for only a small piece of the error
		-- message here.
		local result_wanted = "unable to find ruleset"
		dwsmq_enqueue(false, result_wanted)

		local ret, err = slurm_bb_job_process(job_script_name)
		if IS_NOT_K8S then
			assert.stub(io.popen).was_called(1)
		end
		print("Expect an error message here: " .. err)
		assert.is_equal(ret, slurm.ERROR)
		assert.is_not_nil(string.find(err, result_wanted))
	end)

	local call_bb_setup = function()
		local job_script = "#!/bin/bash\nsrun application.sh\n"
		write_job_script(job_script_name, job_script)

		local apply_result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " created\n"
		local proposal_status_complete_result_wanted = "desiredState=Proposal\ncurrentState=Proposal\nstatus=Completed\n"
		local set_state_result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " patched\n"
		local setup_status_complete_result_wanted = "desiredState=Setup\ncurrentState=Setup\nstatus=Completed\n"

		dwsmq_enqueue(true, apply_result_wanted)
		dwsmq_enqueue(true, proposal_status_complete_result_wanted)
		dwsmq_enqueue(true, set_state_result_wanted)
		dwsmq_enqueue(true, setup_status_complete_result_wanted)

		local ret, err = slurm_bb_setup(jobID, userID, groupID, "pool1", 1, job_script_name)
		expect_exists = true
		if ret == slurm.SUCCESS then
			resource_exists = true
			workflow = DWS(workflow_name)
		end
		if IS_NOT_K8S then
			assert.stub(io.popen).was_called(4)
		end
		assert.is_equal(ret, slurm.SUCCESS)
		assert.is_nil(err, err)
	end

	local call_bb_teardown = function(hurry)
		local set_state_result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " patched\n"
		local teardown_status_complete_result_wanted = "desiredState=Teardown\ncurrentState=Teardown\nstatus=Completed\n"
		local delete_result_wanted = 'workflow.dws.cray.hpe.com "' .. workflow_name .. '" deleted\n'

		dwsmq_enqueue(true, set_state_result_wanted)
		dwsmq_enqueue(true, teardown_status_complete_result_wanted)
		dwsmq_enqueue(true, delete_result_wanted)

		if IS_NOT_K8S then
			io.popen:clear()
		end
		local ret, err = slurm_bb_job_teardown(jobID, job_script_name, hurry)
		expect_exists = false
		if ret == slurm.SUCCESS then
			resource_exists = false
		end
		if IS_NOT_K8S then
			assert.stub(io.popen).was_called(3)
		end
		assert.is_equal(ret, slurm.SUCCESS)
		assert.is_nil(err, err)
	end

	-- For DataIn, PreRun, PostRun, and DataOut.
	-- Call the appropriate slurm_bb_* function to change the state then
	-- call slurm_bb_get_status() to confirm the change.
	local call_bb_state = function(new_state)
		local set_state_result_wanted = "workflow.dws.cray.hpe.com/" .. workflow_name .. " patched\n"
		local status_complete_result_wanted = "desiredState=" .. new_state .. "\ncurrentState=" .. new_state .. "\nstatus=Completed\n"

		dwsmq_enqueue(true, set_state_result_wanted)
		dwsmq_enqueue(true, status_complete_result_wanted)

		if IS_NOT_K8S then
			io.popen:clear()
		end
		local funcs = {
			["DataIn"] = slurm_bb_data_in,
			["PreRun"] = slurm_bb_pre_run,
			["PostRun"] = slurm_bb_post_run,
			["DataOut"] = slurm_bb_data_out,
		}
		local ret, err = funcs[new_state](jobID, job_script_name)
		if IS_NOT_K8S then
			assert.stub(io.popen).was_called(2)
		end
		assert.is_equal(ret, slurm.SUCCESS)
		assert.is_nil(err, err)

		dwsmq_enqueue(true, status_complete_result_wanted)
		local bb_status_wanted = "desiredState=" .. new_state .. " currentState=" .. new_state .. " status=Completed"
		if IS_NOT_K8S then
			io.popen:clear()
		end
		local ret, msg = slurm_bb_get_status("workflow", jobID)
		if IS_NOT_K8S then
			assert.stub(io.popen).was_called()
		end
		print(msg)
		assert.is_equal(ret, slurm.SUCCESS)
		assert.is_equal(msg, bb_status_wanted)
	end

	it("slurm_bb_setup and slurm_bb_teardown with hurry flag can setup and destroy a workflow", function()
		call_bb_setup()
		call_bb_teardown("true")
	end)

	it("slurm_bb_setup through all other states", function()
		call_bb_setup()
		call_bb_state("DataIn")
		call_bb_state("PreRun")
		call_bb_state("PostRun")
		call_bb_state("DataOut")
		call_bb_teardown()
	end)

	context("negatives for slurm_bb_get_status validation", function()

		local call_bb_status_negative = function(someID)
			local status_wanted = "A job ID must contain only digits."
			if IS_NOT_K8S then
				io.popen:clear()
			end
			local ret, msg = slurm_bb_get_status("workflow", someID)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_not_called()
			end
			print(msg)
			assert.is_equal(ret, slurm.ERROR)
			assert.is_equal(msg, status_wanted)
		end

		it("detects invalid job names", function()
			local cases = {
				"a21",
				"; $(nefarious stuff)",
				"B21",
			}
			for k in ipairs(cases) do
				call_bb_status_negative(cases[k])
			end
		end)
	end)

	insulate("error messages from data_in through data_out", function()
		-- This is all about verifying the content of the error log
		-- message.

		local log_error_wanted

		-- Capture the output of slurm.log_error() and validate it.
		-- The 'insulate' context will revert this on completion of
		-- the context.
		_G.slurm.log_error = function(...)
			local errmsg = string.format(...)
			print("Message to validate: " .. errmsg)
			assert.is_equal(errmsg, log_error_wanted)
		end

		-- For DataIn, PreRun, PostRun, and DataOut.
		-- Call the appropriate slurm_bb_* function to induce an
		-- error condition.
		local call_bb_state_negative = function(new_state)
			local set_state_result_wanted = 'Error from server (NotFound): workflows.dws.cray.hpe.com "' .. workflow_name .. '" not found\n'
			dwsmq_enqueue(false, set_state_result_wanted)

			if IS_NOT_K8S then
				io.popen:clear()
			end
			local funcs = {
				["DataIn"] = {slurm_bb_data_in, "slurm_bb_data_in"},
				["PreRun"] = {slurm_bb_pre_run, "slurm_bb_pre_run"},
				["PostRun"] = {slurm_bb_post_run, "slurm_bb_post_run"},
				["DataOut"] = {slurm_bb_data_out, "slurm_bb_data_out"},
			}

			log_error_wanted = lua_script_name .. ": " .. funcs[new_state][2] .. "(), workflow=" .. workflow_name .. ": set_desired_state: " .. set_state_result_wanted

			local ret, err = funcs[new_state][1](jobID, job_script_name)
			if IS_NOT_K8S then
				assert.stub(io.popen).was_called(1)
			end
			assert.is_equal(ret, slurm.ERROR)
			assert.is_equal(err, "set_desired_state: " .. set_state_result_wanted)
		end

		it("slurm_bb_data_in through slurm_bb_data_out error messages", function()
			call_bb_state_negative("DataIn")
			call_bb_state_negative("PreRun")
			call_bb_state_negative("PostRun")
			call_bb_state_negative("DataOut")
		end)
	end)

	it("slurm_bb_pools is called", function()
		local ret, pools = slurm_bb_pools()
		assert.is_equal(ret, slurm.SUCCESS)
		assert.is_nil(pools, pools)
	end)

	it("slurm_bb_paths is called", function()
		local path_file = "/some/path/file"
		local ret = slurm_bb_paths(jobID, job_script_name, path_file)
		assert.is_equal(ret, slurm.SUCCESS)
	end)

	it("slurm_bb_real_size is called", function()
		local ret = slurm_bb_real_size(jobID)
		assert.is_equal(ret, slurm.SUCCESS)
	end)
end)

