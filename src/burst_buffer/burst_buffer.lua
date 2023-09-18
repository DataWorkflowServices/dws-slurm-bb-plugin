-- 
--  Copyright 2022-2023 Hewlett Packard Enterprise Development LP
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

lua_script_name="burst_buffer.lua"

-- The directive used in job scripts. This is the same value specified in the
--  burst_buffer.conf "Directive" configuration parameter.
local DIRECTIVE = "DW"

-- A placeholder for the WLM ID.  This value is not used by Slurm, but is
-- used by other WLMs, so the DWS library expects it.
WLMID_PLACEHOLDER = "slurm"

-- Indentation for labels within the YAML of a Workflow.
LABEL_INDENT = "    "

-- The default label that is applied to all Workflows.
DEFAULT_LABEL_KEY = "origin"
DEFAULT_LABEL_VAL = lua_script_name

-- The fully-qualified name of the DWS Workflow CRD.
local WORKFLOW_CRD = "workflows.dataworkflowservices.github.io"

KUBECTL_CACHE_DIR = "/tmp/burst_buffer_kubectl_cache"

math.randomseed(os.time())

-- Used by the tests when stubbing io.popen.  These values will be
-- returned by DWS:io_popen().
mock_io_popen = {
	ret = false,
	result = "",
}
mock_io_popen.__index = mock_io_popen

setmetatable(mock_io_popen, {
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		self:new(...)
		return self
	end,
})

function mock_io_popen:new(expected_ret, expected_result)
	self.ret = expected_ret
	self.result = expected_result
	return self
end

-- A table to act as a queue for mock_io_popen objects.
-- To enqueue:
--   table.insert(DwsMq, obj)
-- To dequeue:
--   obj = table.remove(DwsMq, 1)
DwsMq = {}

function dwsmq_reset()
	DwsMq = {}
end

function dwsmq_enqueue(expected_ret, expected_result)
	table.insert(DwsMq, mock_io_popen(expected_ret, expected_result))
end

function dwsmq_dequeue()
	local res = table.remove(DwsMq, 1)
	if res == nil then
		return nil, "empty mock queue"
	end
	return res.ret, res.result
end

-- Routines to construct and manipulate a DWS Workflow resource through all
-- of its stages, from initial creation to proposal, and finally to teardown
-- and deletion.

-- See http://lua-users.org/wiki/ObjectOrientationTutorial
DWS = {
	-- The name of the Workflow resource.
	name = "",

	-- The YAML text of the Workflow resource.
	yaml = "",
}
DWS.__index = DWS

setmetatable(DWS, {
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		self:new(...)
		return self
	end,
})

function DWS:new(workflow_name)
	self.name = workflow_name
	self.yaml = self:template()
	return self
end

-- DWS:template will return a string containing a template for a Workflow
-- resource with keywords that must be replaced by the caller.
function DWS:template()
	return [[
apiVersion: dataworkflowservices.github.io/v1alpha2
kind: Workflow
metadata:
  name: WF_NAME
  labels:
THE_LABELS
spec:
  desiredState: "Proposal"
  DWDIRECTIVES
  wlmID: "WLMID"
  jobID: "JOBID"
  userID: USERID
  groupID: GROUPID
]]
end

-- DWS:initialize will replace keywords in a workflow template to turn
-- it into a completed workflow resource.
function DWS:initialize(wlmID, jobID, userID, groupID, dw_directives, labels)
	yaml = self.yaml
	yaml = string.gsub(yaml, "WF_NAME", self.name)
	yaml = string.gsub(yaml, "WLMID", wlmID)
	yaml = string.gsub(yaml, "JOBID", jobID)
	yaml = string.gsub(yaml, "USERID", userID)
	yaml = string.gsub(yaml, "GROUPID", groupID)

	local new_labels = LABEL_INDENT .. DEFAULT_LABEL_KEY .. ": " .. DEFAULT_LABEL_VAL .. "\n"
	if labels ~= nil then
		for k, v in pairs(labels) do
			new_labels = new_labels .. LABEL_INDENT .. k .. ": " .. v .. "\n"
		end
	end
	yaml = string.gsub(yaml, "THE_LABELS", new_labels)

	local dwd_count = 0
	if dw_directives ~= nil then
		for k in ipairs(dw_directives) do
			dwd_count = dwd_count + 1
		end
	end
	if dwd_count == 0 then
		yaml = string.gsub(yaml, "DWDIRECTIVES", "dwDirectives: []")
	else
		dwd_block = "dwDirectives:\n"
		for k, v in ipairs(dw_directives) do
			dwd_block = dwd_block .. "  - \"" .. dw_directives[k] .. "\"\n"
		end
		yaml = string.gsub(yaml, "DWDIRECTIVES", dwd_block)
	end

	self.yaml = yaml
end

-- DWS:save will save the text of the Workflow resource into a file
-- of the given name.
-- On success this returns true.
-- On failure this returns false and an optional error message.
function DWS:save(fname)
	local f = io.open(fname, "w")
	if f == nil then
		local msg = "unable to open " .. fname
		return false, msg
	end
	slurm.log_info(self.yaml)
	f:write(self.yaml)
	local rc = {f:close()}
	-- Success or failure is a boolean in rc[1].
	return rc[1]
end

-- DWS:apply will apply the Workflow resource via kubectl.
-- On success this returns true.
-- On failure this returns false and the output of the kubectl command.
function DWS:apply(fname)
	return self:kubectl("apply -f " .. fname .. " 2>&1")
end

-- DWS:delete will delete the named Workflow resource via kubectl.
-- On success this returns true and the output of the kubectl command.
-- On failure this returns false and the output of the kubectl command.
function DWS:delete()
	return self:kubectl("delete " .. WORKFLOW_CRD .. " " .. self.name .. " 2>&1")
end

-- DWS:get_jsonpath will get the specified values from the Workflow resource.
-- On success this returns true and a string containing the result of the query.
-- On failure this returns false and the output of the kubectl command.
function DWS:get_jsonpath(path)
	local cmd = "get " .. WORKFLOW_CRD .. " " .. self.name .. " -o jsonpath='" .. path .. "' 2>&1"
	return self:kubectl(cmd)
end

-- DWS:get_current_state will get the status of the Workflow resource with
-- respect to its desired state.
-- On success this returns true and a table containing the desiredState,
-- the current state, and the status of the current state.
-- On failure this returns false, an empty table, and the output of the
-- kubectl command.
function DWS:get_current_state()
	local status = {}
	local ret, output = self:get_jsonpath([[desiredState={.spec.desiredState}{"\n"}currentState={.status.state}{"\n"}status={.status.status}{"\n"}]])
	if ret == false then
		return ret, status, output
	end
	local idx = 0
	for line in output:gmatch("[^\n]+") do
		for k, v in string.gmatch(line, "([a-z]%w+)=([A-Z]%w+)") do
			status[k] = v
			idx = idx + 1
		end
	end
	if idx == 1 and status["desiredState"] == "Proposal" then
		-- DWS has not yet attached a status section to this new
		-- resource.  Fill out the table for our consumer.
		status["currentState"] = ""
		status["status"] = ""
	elseif idx ~= 3 then
		-- We should have had 3 lines.
		return false, status, string.format("found %d items, wanted 3: %s", idx, output)
	end
	return ret, status
end

function _parse_driver_statuses(text, iterator, status_list, status_info)
	if iterator == nil then
		iterator = text:gmatch("[^\n]+")
	end

	if status_list == nil then
		status_list = {}
	end

	local line = iterator()
	if line == nil  and status_info ~= nil then
		table.insert(status_list, status_info)
		return status_list
	elseif line == nil then
		return status_list
	end

	if line == "===" then
		if status_info ~= nil then
			table.insert(status_list, status_info)
		end

		status_info = {}
		status_info["status"] = iterator()
		status_info["driverID"] = iterator()
		status_info["error"] = ""
		return _parse_driver_statuses(text, iterator, status_list, status_info)
	end

	if status_info ~= nil then
		status_info["error"] = status_info["error"] .. line .. "\n"
		return _parse_driver_statuses(text, iterator, status_list, status_info)
	end
		
	return status_list
end

-- DWS:get_driver_errors will collect driver errors from the Workflow resource
-- with respect to the given state.
function DWS:get_driver_errors(state)
	local error_list = {}
	local jsonpath = [[{range .status.drivers[?(@.watchState=="]].. state ..[[")]}==={"\n"}{@.status}{"\n"}{@.driverID}{"\n"}{@.error}{"\n"}{end}]]
	local ret, output = self:get_jsonpath(jsonpath)
	if ret == false then
		return ret, "", "could not get driver errors: " .. output
	end

	driver_statuses = _parse_driver_statuses(output)

	errors = ""
	for _, driver_status in ipairs(driver_statuses) do
		if driver_status["status"] == "Error" then
			if errors ~= "" then
				errors = errors .. "\n"
			end

			errors = errors .. driver_status["driverID"] .. ": " .. driver_status["error"]
		end
	end

	return true, errors
end

-- DWS:get_hurry will get the hurry flag of the Workflow resource.
-- On success this returns true and a boolean for the value of the hurry flag.
-- On failure this returns false and the output of the kubectl command.
function DWS:get_hurry()
	local ret, result = self:get_jsonpath("{.spec.hurry}")
	if ret ~= true then
		return ret, result
	end
	local hurry = false
	if result == "true" then
		hurry = true
	end
	return true, hurry
end

-- DWS:wait_for_status_complete will loop until the workflow reports that
-- its status is completed.  If the max_passes == -1 then this will loop
-- without limit until the state is complete or an error is encountered.
-- On success this returns true and a table containing the status.
-- On failure this returns false, an empty table, and an error message.
function DWS:wait_for_status_complete(max_passes)
	local empty = {}
	while max_passes > 0 or max_passes == -1 do
		local done, status, err = self:get_current_state()
		if done == false then
			return false, empty, err
		end
		-- Wait for current state to reflect the desired state, and
		-- for the current state to be complete.
		if status["desiredState"] == status["currentState"] and status["status"] == "Completed" then
			return true, status
		elseif status["status"] == "Error" then
			local ret, driver_errors, err = self:get_driver_errors(status["desiredState"])
			if ret ~= true then
				return ret, empty, err
			end
			return false, empty, "DWS driver error(s):\n" .. driver_errors
		end
		os.execute("sleep 1")
		if max_passes > 0 then
			max_passes = max_passes - 1
		end
	end
	return false, empty, "exceeded max wait time"
end


-- DWS:set_desired_state will attempt to patch the Workflow's desired
-- state.
-- If the hurry flag is present and set to true then it will be set in the
-- Workflow patch along with the new desired state.
-- On success this returns true.
-- On failure this returns false and an error message.
function DWS:set_desired_state(new_state, hurry)
	local spec_tbl = {}
	table.insert(spec_tbl, [["desiredState":"]] .. new_state .. [["]])
	if hurry == true then
		table.insert(spec_tbl, [["hurry":true]])
	end
	local new_spec = table.concat(spec_tbl, ",")
	local patch = "patch " .. WORKFLOW_CRD .. " " .. self.name .. [[ --type=merge -p '{"spec":{]] .. new_spec .. [[}}' 2>&1]]
	return self:kubectl(patch)
end

-- DWS:set_workflow_state_and_wait updates the Workflow to the desired state
-- and waits for the state be completed.
-- On success this returns true.
-- On failure this returns false and an error message.
function DWS:set_workflow_state_and_wait(new_state, hurry)
	local done, err = self:set_desired_state(new_state, hurry)
	if done == false then
		return done, "set_desired_state: " .. err
	end

	local done, status, err = self:wait_for_status_complete(-1)
	if done == false then
		return done, "wait_for_status_complete: " .. err
	end

	return true
end

-- DWS:kubectl_cache_home will determine where the kubectl discovery cache
-- and http cache may be located.
-- If the user's HOME dir exists then kubectl expects to use that and this does
-- nothing and returns true and an empty string.
-- Otherwise, this will create a dir in /tmp and will return true and a string
-- that defines the HOME variable with the new dir.
-- If there is an error creating the dir this will return false and a string
-- containing an error message.
function DWS:kubectl_cache_home()

	local dir_exists = function(dname)
		local cmd = "test -d " .. dname
		local done, _ = self:io_popen(cmd)
		return done
	end

	if dir_exists(os.getenv("HOME")) == false then
		if dir_exists(KUBECTL_CACHE_DIR) == false then
			local cmd = "mkdir " .. KUBECTL_CACHE_DIR
			local done, result = self:io_popen(cmd)
			if done == false then
				return false, "Unable to create " .. KUBECTL_CACHE_DIR .. " cache dir for kubectl: " .. result
			end
		end
		return true, "HOME=" .. KUBECTL_CACHE_DIR
	end

	return true, ""
end

-- DWS:token will find a ServiceAccount token and return a --token argument
-- for the kubectl command.  If we're not inside the slurm pod, maybe in a test
-- env, then this will return an empty string.
function DWS:token()
	local tok = ""
	local file = io.open("/var/run/secrets/kubernetes.io/serviceaccount/token")
	if file ~= nil then
		local content = file:read("*a")
		file:close()
		tok = '--token="' .. content .. '"'
	end
	return tok
end

-- DWS:kubectl will run the given kubectl command and collect its output.
-- On success this returns true and the output of the command.
-- On failure this returns false and the output of the command.
function DWS:kubectl(cmd)
	local done, homedir_msg = self:kubectl_cache_home()
	if done ~= true then
		return false, homedir_msg
	end
	local kcmd = homedir_msg .. " kubectl " .. self:token() .. " " .. cmd
	return self:io_popen(kcmd)
end

-- DWS:io_popen will run the given command and collect its output.
-- On success this returns true and the output of the command.
-- On failure this returns false and the output of the command.
function DWS:io_popen(cmd)
	local handle = io.popen(cmd)
	if handle == nil then
		-- The io.popen was stubbed by a test.  Use the provided
		-- return values.
		return dwsmq_dequeue()
	end
	local result = handle:read("*a")
	-- The exit status is an integer in rc[3].
	local rc = {handle:close()}
	if rc[3] ~= 0 then
		return false, result
	end
	return true, result
end

-- find_dw_directives will search for any requested directive lines in the job
-- script and return them in a table.
function find_dw_directives(job_script)
	local dw_directives = {}
	local idx = 1
	local bb
	local line

	io.input(job_script)
	local content = io.read("*all")

	local mline = "^#" .. DIRECTIVE .. " [^\n]+"
	for line in content:gmatch("[^\n]+") do
		bb = line:match(mline)
		if bb ~= nil then
			dw_directives[idx] = bb
			idx = idx + 1
		end
	end
	return dw_directives
end

-- make_workflow populates a workflow resource and submits it to DWS.
-- On success this returns true and a nil error message.
-- On failure this returns false and an error message.
function make_workflow(workflow, job_script, jobid, userid, groupid, labels)
	local dwd = find_dw_directives(job_script)
	workflow:initialize(WLMID_PLACEHOLDER, jobid, userid, groupid, dwd, labels)

	local msg
	local yaml_name = os.tmpname()
	local done, err = workflow:save(yaml_name)
	if done == false then
		msg = "unable to save yaml: " .. err
		return done, msg
	end

	done, err = workflow:apply(yaml_name)
	os.remove(yaml_name)
	if done == false then
		msg = "unable to apply workflow: " .. err
		return done, msg
	end

	return true, nil
end

-- make_workflow_name constructs a workflow name with the given job ID.
function make_workflow_name(job_id)
	return "bb" .. job_id
end

--[[
--slurm_bb_job_process
--
--WARNING: This function is called synchronously from slurmctld and must
--return quickly.
--
--This function is called on job submission.
--
--Slurm has just created a job ID and created the job script file.  We're now
--asked to validate the script.  In DWS-speak, this means we have to define a
--Workflow resource and submit it to DWS where the validation steps occur.  If
--the validation steps succeed then a Workflow resource will exist and will be
--in DWS's "Proposal" state.
--
--Slurm does not give us the job ID, user ID, or group ID at this time, so
--placeholder values will be used.  Slurm will give us those values when it
--asks us to transition to setup state and we'll patch the Workflow resource
--at that time.
--
--We do not wait for the proposal state to transition to "Completed". If we did
--not get an error on the initial apply of the resource then we know it passed
--all validation steps. Any errors which may occur later to prevent the state's
--transition to "Completed" will be caught when we attempt to transition it to
--"Setup" state.
--
--If the DWS validation steps fail then the Workflow resource will not exist
--and there will be no need for cleanup.
--
--If this function returns an error, the job is rejected and the second return
--value (if given) is printed where salloc, sbatch, or srun was called.
--]]
function slurm_bb_job_process(job_script)
	slurm.log_info("%s: slurm_bb_job_process(). job_script=%s",
		lua_script_name, job_script)

	-- Note: In this version of Slurm, 22.05.[3-5], we do not have the job
	-- ID in this function, though it's coming in the 23.02 release.
	-- So we have no way to name the Workflow so that it can be found in a
	-- later step.
	-- In the 23.02 release of Slurm this function will also get a user ID
	-- and group ID.
	-- For now we will create the Workflow resource with a temporary name
	-- and with placeholder values for the user ID and group ID.  We will
	-- submit it, report on whether it was good, and then delete it.  The
	-- slurm_bb_setup() stage will have to re-create it using the job ID to
	-- name it.

	local workflow_name = "temp-" .. math.random(10000)
	local workflow = DWS(workflow_name)
	local labels = {["note"] = "temporary"}
	local done, err = make_workflow(workflow, job_script, 1, 1, 1, labels)
	if done == false then
		slurm.log_error("%s: slurm_bb_job_process(), workflow=%s, make_workflow: %s", lua_script_name, workflow_name, err)
		return slurm.ERROR, err
	end

	-- The job script's directives are good.
	-- Now throw away this temporary Workflow resource.
	-- In slurm_bb_setup() it'll be created again using the job ID for its
	-- name so it can be found in all other stages.

	done, err = workflow:delete()
	if done == false then
		slurm.log_error("%s: slurm_bb_job_process(), workflow=%s, make_workflow: unable to delete temporary workflow: %s", lua_script_name, workflow_name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end


--[[
--slurm_bb_pools
--
--WARNING: This function is called from slurmctld and must return quickly.
--
--This function is called on slurmctld startup, and then periodically while
--slurmctld is running.
--
--You may specify "pools" of resources here. If you specify pools, a job may
--request a specific pool and the amount it wants from the pool. Slurm will
--subtract the job's usage from the pool at slurm_bb_data_in and Slurm will
--add the job's usage of those resources back to the pool after
--slurm_bb_teardown.
--A job may choose not to specify a pool even you pools are provided.
--If pools are not returned here, Slurm does not track burst buffer resources
--used by jobs.
--
--If pools are desired, they must be returned as the second return value
--of this function. It must be a single JSON string representing the pools.
--]]
function slurm_bb_pools()

	--slurm.log_info("%s: slurm_bb_pools().", lua_script_name)

	-- Pools are not being used with DWS.
	return slurm.SUCCESS
end

--[[
--slurm_bb_job_teardown
--
--This function is called asynchronously and is not required to return quickly.
--This function is normally called after the job completes (or is cancelled).
--]]
function slurm_bb_job_teardown(job_id, job_script, hurry)
	slurm.log_info("%s: slurm_bb_job_teardown(). job id:%s, job script:%s, hurry:%s",
		lua_script_name, job_id, job_script, hurry)

	local hurry_flag = false
	if hurry == "true" then
		hurry_flag = true
	end
	local workflow = DWS(make_workflow_name(job_id))
	local done, err = workflow:set_workflow_state_and_wait("Teardown", hurry_flag)
	if done == false then
		if string.find(err, [["]] .. workflow.name .. [[" not found]]) then
			-- It's already gone, and that's what we wanted anyway.
			return slurm.SUCCESS
		else
			slurm.log_error("%s: slurm_bb_job_teardown(), workflow=%s: %s", lua_script_name, workflow.name, err)
			return slurm.ERROR, err
		end
	end

	done, err = workflow:delete()
	if done == false then
		slurm.log_error("%s: slurm_bb_job_teardown(), workflow=%s, delete: %s", lua_script_name, workflow.name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end

--[[
--slurm_bb_setup
--
--This function is called asynchronously and is not required to return quickly.
--This function is called while the job is pending.
--]]
function slurm_bb_setup(job_id, uid, gid, pool, bb_size, job_script)
	slurm.log_info("%s: slurm_bb_setup(). job id:%s, uid: %s, gid:%s, pool:%s, size:%s, job script:%s",
		lua_script_name, job_id, uid, gid, pool, bb_size, job_script)

	-- See the notes in slurm_bb_process() for an explanation about why we
	-- create the Workflow resource here rather than look up an existing
	-- resource.

	local workflow_name = make_workflow_name(job_id)
	local workflow = DWS(workflow_name)
	local done, err = make_workflow(workflow, job_script, job_id, uid, gid)
	if done == false then
		slurm.log_error("%s: slurm_bb_setup(), workflow=%s, make_workflow: %s", lua_script_name, workflow_name, err)
		return slurm.ERROR, err
	end

	-- Wait for proposal state to complete, or pick up any error that may
	-- be waiting in the Workflow.
	local done, status, err = workflow:wait_for_status_complete(-1)
	if done == false then
		slurm.log_error("%s: slurm_bb_setup(), workflow=%s, waiting for Proposal state to complete: %s", lua_script_name, workflow_name, err)
		return slurm.ERROR, err
	end

	local done, err = workflow:set_desired_state("Setup")
	if done == false then
		slurm.log_error("%s: slurm_bb_setup(), workflow=%s, setting state to Setup: %s", lua_script_name, workflow_name, err)
		return slurm.ERROR, err
	end

	done, status, err = workflow:wait_for_status_complete(-1)
	if done == false then
		slurm.log_error("%s: slurm_bb_setup(), workflow=%s, waiting for Setup state to complete: %s", lua_script_name, workflow_name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end

--[[
--slurm_bb_data_in
--
--This function is called asynchronously and is not required to return quickly.
--This function is called immediately after slurm_bb_setup while the job is
--pending.
--]]
function slurm_bb_data_in(job_id, job_script)
	slurm.log_info("%s: slurm_bb_data_in(). job id:%s, job script:%s",
		lua_script_name, job_id, job_script)

	local workflow = DWS(make_workflow_name(job_id))
	local done, err = workflow:set_workflow_state_and_wait("DataIn")
	if done == false then
		slurm.log_error("%s: slurm_bb_data_in(), workflow=%s: %s", lua_script_name, workflow.name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end

--[[
--slurm_bb_real_size
--
--This function is called asynchronously and is not required to return quickly.
--This function is called immediately after slurm_bb_data_in while the job is
--pending.
--
--This function is only called if pools are specified and the job requested a
--pool. This function may return a number (surrounded by quotes to make it a
--string) as the second return value. If it does, the job's usage of the pool
--will be changed to this number. A commented out example is given.
--]]
function slurm_bb_real_size(job_id)
	--slurm.log_info("%s: slurm_bb_real_size(). job id:%s",
	--	lua_script_name, job_id)
	--return slurm.SUCCESS, "10000"
	return slurm.SUCCESS
end

--[[
--slurm_bb_paths
--
--WARNING: This function is called synchronously from slurmctld and must
--return quickly.
--This function is called after the job is scheduled but before the
--job starts running when the job is in a "running + configuring" state.
--
--The file specfied by path_file is an empty file. If environment variables are
--written to path_file, these environment variables are added to the job's
--environment. A commented out example is given.
--]]
function slurm_bb_paths(job_id, job_script, path_file)
	--slurm.log_info("%s: slurm_bb_paths(). job id:%s, job script:%s, path file:%s",
	--	lua_script_name, job_id, job_script, path_file)
	--io.output(path_file)
	--io.write("FOO=BAR")
	return slurm.SUCCESS
end

--[[
--slurm_bb_pre_run
--
--This function is called asynchronously and is not required to return quickly.
--This function is called after the job is scheduled but before the
--job starts running when the job is in a "running + configuring" state.
--]]
function slurm_bb_pre_run(job_id, job_script)
	slurm.log_info("%s: slurm_bb_pre_run(). job id:%s, job script:%s",
		lua_script_name, job_id, job_script)

	local workflow = DWS(make_workflow_name(job_id))
	local done, err = workflow:set_workflow_state_and_wait("PreRun")
	if done == false then
		slurm.log_error("%s: slurm_bb_pre_run(), workflow=%s: %s", lua_script_name, workflow.name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end

--[[
--slurm_bb_post_run
--
--This function is called asynchronously and is not required to return quickly.
--This function is called after the job finishes. The job is in a "stage out"
--state.
--]]
function slurm_bb_post_run(job_id, job_script)
	slurm.log_info("%s: slurm_post_run(). job id:%s, job script%s",
		lua_script_name, job_id, job_script)

	local workflow = DWS(make_workflow_name(job_id))
	local done, err = workflow:set_workflow_state_and_wait("PostRun")
	if done == false then
		slurm.log_error("%s: slurm_bb_post_run(), workflow=%s: %s", lua_script_name, workflow.name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end

--[[
--slurm_bb_data_out
--
--This function is called asynchronously and is not required to return quickly.
--This function is called after the job finishes immediately after
--slurm_bb_post_run. The job is in a "stage out" state.
--]]
function slurm_bb_data_out(job_id, job_script)
	slurm.log_info("%s: slurm_bb_data_out(). job id:%s, job script%s",
		lua_script_name, job_id, job_script)

	local workflow = DWS(make_workflow_name(job_id))
	local done, err = workflow:set_workflow_state_and_wait("DataOut")
	if done == false then
		slurm.log_error("%s: slurm_bb_data_out(), workflow=%s: %s", lua_script_name, workflow.name, err)
		return slurm.ERROR, err
	end

	return slurm.SUCCESS
end

--[[
--slurm_bb_get_status
--
--This function is called asynchronously and is not required to return quickly.
--
--This function is called when "scontrol show bbstat" is run. It receives a
--variable number of arguments - whatever arguments are after "bbstat".
--For example:
--
--  scontrol show bbstat foo bar
--
--This command will pass 2 arguments to this functions: "foo" and "bar".
--
--If this function returns slurm.SUCCESS, then this function's second return
--value will be printed where the scontrol command was run. If this function
--returns slurm.ERROR, then this function's second return value is ignored and
--an error message will be printed instead.
--]]
function slurm_bb_get_status(...)
	--slurm.log_info("%s: slurm_bb_get_status().", lua_script_name)

	local ret = slurm.ERROR
	local msg = "Usage: workflow <job-id>"

	-- Create a table from variable arg list
	-- NOTE: The args[] array index begins at 1.
	local args = {...}
	args.n = select("#", ...)

	local found_jid = false
	local jid = 0
	if args.n == 2 and args[1] == "workflow" then
		-- Slurm 22.05
		jid = args[2]
		found_jid = true
	elseif args.n == 4 and args[3] == "workflow" then
		-- Slurm 23.02
		jid = args[4]
		found_jid = true
	end
	if found_jid == true then
		local done = false
		local status = {}
		if string.find(jid, "^%d+$") == nil then
			msg = "A job ID must contain only digits."
		else
			local workflow = DWS(make_workflow_name(jid))
			done, status, msg = workflow:get_current_state()
		end
		if done == true then
			msg = "desiredState=" .. status["desiredState"] .. " currentState=" .. status["currentState"] .. " status=" .. status["status"]
			ret = slurm.SUCCESS
		end
	end

	if ret == slurm.ERROR then
		slurm.log_error("%s: slurm_bb_get_status(%s): %s", lua_script_name, table.concat(args, ", "), msg)
	end
	return ret, msg
end

