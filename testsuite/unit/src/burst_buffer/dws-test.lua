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

require("burst_buffer/dws")

math.randomseed(os.time())

local IS_LIVE = false
local IS_NOT_LIVE = true
if os.getenv("RUN_LIVE") ~= nil then
  -- Expect to be running against a live K8s environment, with kubectl and DWS operator.
  print("Running live")
  IS_LIVE = true
  IS_NOT_LIVE = false
end

local CRDFILE = os.getenv("CRDFILE")
if CRDFILE == nil and IS_NOT_LIVE then
	-- The CRD location in the container image.
	CRDFILE = "/dws/config/crd/bases/dws.cray.hpe.com_workflows.yaml"
end

local VALIDATOR = os.getenv("VALIDATOR")
if VALIDATOR == nil and IS_NOT_LIVE then
	-- The validator tool's location in the container image.
	VALIDATOR = "/bin/validate"
end

describe("The dws library test", function()
	local yaml_name
	local yaml_name_exists
	local workflow_name
	local wlmID
	local jobID
	local userID
	local groupID
	local workflow
	local status_check_count -- simulated delay in dws operator

	local get_workflow_obj = function()
		workflow = DWS()
		local wf_yaml = workflow.yaml
		assert.is_not_nil(string.find(wf_yaml, "kind: Workflow"))
		assert.is_not_nil(string.find(wf_yaml, "name: WF_NAME"))
	end

	local fill_template = function()
		workflow:initialize(workflow_name, wlmID, jobID, userID, groupID)
		local wf_yaml = workflow.yaml
		assert.is_not_nil(string.find(wf_yaml, "name: " .. workflow_name))
		assert.is_not_nil(string.find(wf_yaml, [[wlmID: "]] .. wlmID .. [["]]))
		assert.is_not_nil(string.find(wf_yaml, "jobID: " .. jobID))
		assert.is_not_nil(string.find(wf_yaml, "userID: " .. userID))
		assert.is_not_nil(string.find(wf_yaml, "groupID: " .. groupID))
	end

	local make_workflow_yaml = function()
		get_workflow_obj()
		fill_template()
	end

	before_each(function()
		status_check_count = 3

		workflow_name = "check" .. math.random(1000)
		wlmID = "5f239" .. math.random(1000)
		jobID = math.random(1000)
		userID = math.random(1000)
		groupID = math.random(1000)

		yaml_name = os.tmpname()
		yaml_name_exists = false
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
			yaml_name_exists = done
			assert.is_true(done, err)

			if IS_NOT_LIVE then
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
			if IS_NOT_LIVE then
				io.popen:revert()
			end
		end)

		it("can apply and delete a workflow resource", function()
			local result_wanted = [[workflow.dws.cray.hpe.com/]] .. workflow_name .. [[ created
]]

			workflow.mock_io_popen.ret = true
			workflow.mock_io_popen.result = result_wanted
			local done, err = workflow:apply(yaml_name)
			resource_exists = done
			assert.is_true(done, err)
			if IS_NOT_LIVE then
				assert.stub(io.popen).was_called()
				io.popen:clear()
			end
			assert.is_equal(err, result_wanted)

			result_wanted = [[workflow.dws.cray.hpe.com "]] .. workflow_name .. [[" deleted
]]

			workflow.mock_io_popen.ret = true
			workflow.mock_io_popen.result = result_wanted
			done, err = workflow:delete()
			resource_exists = done
			if IS_NOT_LIVE then
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

		-- Save the YAML for the resource.  Initialize some bools.
		-- Setup a stub for io.popen if not running live.
		before_each(function()
			resource_exists = false
			expect_exists = true

			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			yaml_name_exists = done
			assert.is_true(done, err)

			if IS_NOT_LIVE then
				stub(io, "popen")
			end
		end)

		-- Create the resource.
		before_each(function()
			local result_wanted = [[workflow.dws.cray.hpe.com/]] .. workflow_name .. [[ created
]]

			workflow.mock_io_popen.ret = true
			workflow.mock_io_popen.result = result_wanted
			local done, err = workflow:apply(yaml_name)
			resource_exists = done
			if IS_NOT_LIVE then
				assert.stub(io.popen).was_called()
				io.popen:clear()
			end
			assert.is_true(done, err)
		end)

		-- Delete the resource.
		after_each(function()
			if resource_exists and expect_exists then
				local result_wanted = [[workflow.dws.cray.hpe.com "]] .. workflow_name .. [[" deleted
]]

				workflow.mock_io_popen.ret = true
				workflow.mock_io_popen.result = result_wanted
				local done, err = workflow:delete()
				resource_exists = done
				if IS_NOT_LIVE then
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
			if IS_NOT_LIVE then
				io.popen:revert()
			end
		end)

		-- Progress the resource to the desired state.  Attempt to set
		-- the hurry flag on the state, if indicated.
		local set_desired_state = function(new_state, hurry)
			local ret_wanted = true
			local result_wanted = [[workflow.dws.cray.hpe.com/]] .. workflow_name .. [[ patched
]]

			if skip_state == true then
				result_wanted = [[Error from server (states cannot be skipped): admission webhook "vworkflow.kb.io" denied the request: states cannot be skipped
]]
				ret_wanted = false
			end

			workflow.mock_io_popen.ret = ret_wanted
			workflow.mock_io_popen.result = result_wanted

			local done, err = workflow:set_desired_state(new_state, hurry)
			if IS_NOT_LIVE then
				assert.stub(io.popen).was_called()
			end
			assert.is_equal(done, ret_wanted)
			assert.is_equal(err, result_wanted)
		end

		-- Wait for the resource state to progress to "Completed" state.
		local wait_for_state = function(state)
			local result_wanted = "desiredState=" .. state .. "\ncurrentState=" .. state .. "\nstatus=Completed\n"

			workflow.mock_io_popen.ret = true
			workflow.mock_io_popen.result = result_wanted
			local done, err = workflow:wait_for_status_complete(60)
			if IS_NOT_LIVE then
				assert.stub(io.popen).was_called()
			end
			assert.is_true(done, err)
			assert.is_equal(err["desiredState"], state)
			assert.is_equal(err["currentState"], state)
			assert.is_equal(err["status"], "Completed")
		end

		-- Check that the resource's hurry flag is as desired.
		local check_hurry = function(desired_hurry)
			local result_wanted = [[false]]
			if desired_hurry == true then
				result_wanted = [[true]]
			end

			workflow.mock_io_popen.ret = true
			workflow.mock_io_popen.result = result_wanted
			local done, hurry = workflow:get_hurry()
			if IS_NOT_LIVE then
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
			wait_for_state("proposal")
		end)

		it("progresses from proposal to setup state", function()
			wait_for_state("proposal")

			set_desired_state_and_wait("setup")
		end)

		it("progresses from proposal to teardown state", function()
			wait_for_state("proposal")

			set_desired_state_and_wait("teardown")
			check_hurry(false)
		end)

		it("progresses from proposal to teardown state in a hurry", function()
			wait_for_state("proposal")

			set_desired_state("teardown", true)
			wait_for_state("teardown")
			check_hurry(true)
		end)

		it("progresses from proposal through all states", function()
			wait_for_state("proposal")

			local states = {
				"setup",
				"data_in",
				"pre_run",
				"post_run",
				"data_out",
				"teardown",
			}

			for i in pairs(states) do
				print("Next state", states[i])
				set_desired_state_and_wait(states[i])
			end
			check_hurry(false)
		end)

		context("negative cases for state order", function()

			before_each(function()
				skip_state = true
				expect_exists = false
			end)

			it("can detect an invalid state transition error", function()
				wait_for_state("proposal")

				set_desired_state("pre_run")
			end)
		end)
	end)

	context("negative file save cases", function()

		before_each(function()
			make_workflow_yaml()
			yaml_name = "/nosuchdir/tmpfile"
		end)

		it("cannot save a file to nonexistent directory", function()
			local done, err = workflow:save(yaml_name)
			yaml_name_exists = done
			assert.is_not_true(done)
		end)
	end)

	context("negative yaml cases", function()

		local resource_exists

		-- The error from k8s has a lot of content, so let's
		-- just look for the beginning of it.
		local result_wanted = [[Error from server]]

		before_each(function()
			resource_exists = false

			if IS_NOT_LIVE then
				stub(io, "popen")
			end
		end)

		after_each(function()
			workflow.mock_io_popen.ret = false
			workflow.mock_io_popen.result = result_wanted
			local done, err = workflow:apply(yaml_name)
			resource_exists = done
			assert.is_not_true(done)
			if IS_NOT_LIVE then
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
			if IS_NOT_LIVE then
				io.popen:revert()
			end
		end)

		it("cannot apply an invalid jobID", function()

			jobID = "bad job"
			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			yaml_name_exists = done
			assert.is_true(done, err)
		end)

		it("cannot apply an invalid userID", function()
			userID = "bad user"
			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			yaml_name_exists = done
			assert.is_true(done, err)
		end)

		it("cannot apply an invalid groupID", function()
			groupID = "bad group"
			make_workflow_yaml()
			local done, err = workflow:save(yaml_name)
			yaml_name_exists = done
			assert.is_true(done, err)
		end)
	end)
end)

