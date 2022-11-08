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


-- Routines to construct and manipulate a DWS Workflow resource through all
-- of its stages, from initial creation to proposal, and finally to teardown
-- and deletion.

-- See http://lua-users.org/wiki/ObjectOrientationTutorial
DWS = {
	-- The name of the Workflow resource.
	name = "",

	-- The YAML text of the Workflow resource.
	yaml = "",

	-- Used by the tests when stubbing io.popen.  These values will be
	-- returned by DWS:io_popen().
	mock_io_popen = {
		ret = false,
		result = "",
	},
}
DWS.__index = DWS

setmetatable(DWS, {
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		self:new()
		return self
	end,
})

function DWS:new()
	self.yaml = self:template()
	return self
end

-- DWS.template will return a string containing a template for a Workflow
-- resource with keywords that must be replaced by the caller.
function DWS:template()
	return [[
apiVersion: dws.cray.hpe.com/v1alpha1
kind: Workflow
metadata:
  name: WF_NAME
spec:
  desiredState: "proposal"
  dwDirectives: []
  wlmID: "WLMID"
  jobID: JOBID
  userID: USERID
  groupID: GROUPID
]]
end

-- DWS.initialize will replace keywords in a workflow template to turn
-- it into a completed workflow resource.
function DWS:initialize(wf_name, wlmID, jobID, userID, groupID)
	self.name = wf_name
	yaml = self.yaml
	yaml = string.gsub(yaml, "WF_NAME", wf_name)
	yaml = string.gsub(yaml, "WLMID", wlmID)
	yaml = string.gsub(yaml, "JOBID", jobID)
	yaml = string.gsub(yaml, "USERID", userID)
	yaml = string.gsub(yaml, "GROUPID", groupID)
	self.yaml = yaml
end

-- DWS.save will save the text of the Workflow resource into a file
-- of the given name.
-- On success this returns true.
-- On failure this returns false and an optional error message.
function DWS:save(fname)
	local f = io.open(fname, "w")
	if f == nil then
		local msg = "unable to open " .. fname
		return false, msg
	end
	f:write(self.yaml)
	local rc = {f:close()}
	-- Success or failure is a boolean in rc[1].
	return rc[1]
end

-- DWS.apply will apply the Workflow resource via kubectl.
-- On success this returns true.
-- On failure this returns false and the output of the kubectl command.
function DWS:apply(fname)
	return self:io_popen("kubectl apply -f " .. fname .. " 2>&1")
end

-- DWS.delete will delete the named Workflow resource via kubectl.
-- On success this returns true.
-- On failure this returns false and the output of the kubectl command.
function DWS:delete()
	return self:io_popen("kubectl delete workflow " .. self.name .. " 2>&1")
end

-- DWS.get_jsonpath will get the specified values from the Workflow resource.
-- On success this returns true and a string containing the result of the query.
-- On failure this returns false and the output of the kubectl command.
function DWS:get_jsonpath(path)
	local cmd = "kubectl get workflow " .. self.name .. " -o jsonpath='" .. path .. "' 2>&1"
	return self:io_popen(cmd)
end

-- DWS.get_current_state will get the status of the Workflow resource with
-- respect to its desired state.
-- On success this returns true and a table containing the desiredState,
-- the current state, and the status of the current state.
-- On failure this returns false and the output of the kubectl command.
function DWS:get_current_state()
	local ret, output = self:get_jsonpath([[desiredState={.spec.desiredState}{"\n"}currentState={.status.state}{"\n"}status={.status.status}{"\n"}]])
	if ret == false then
		return ret, output
	end
	local status = {}
	local idx = 0
	for line in output:gmatch("[^\n]+") do
		for k, v in string.gmatch(line, "(%w+)=([%w_]+)") do
			status[k] = v
		end
		idx = idx + 1
	end
	if idx == 1 and status["desiredState"] == "proposal" then
		-- DWS has not yet attached a status section to this new
		-- resource.  Fill out the table for our consumer.
		status["currentState"] = ""
		status["status"] = ""
	elseif idx ~= 3 then
		-- We should have had 3 lines.
		ret = false
	end
	return ret, status
end

-- DWS.get_hurry will get the hurry flag of the Workflow resource.
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

-- DWS.wait_for_status_complete will loop until the workflow reports that
-- its status is completed.
-- On success this returns true and the status text.
-- On failure this returns false and an error message.
function DWS:wait_for_status_complete(max_passes)
	while max_passes > 0 do
		local done, output = self:get_current_state()
		if done == false then
			return false, output
		end
		-- Wait for current state to reflect the desired state, and
		-- for the current state to be complete.
		if output["desiredState"] == output["currentState"] and output["status"] == "Completed" then
			return true, output
		elseif output["status"] == "Error" then
			return false, output
		end
		os.execute("sleep 1")
		max_passes = max_passes - 1
	end
	return false, "exceeded max wait time"
end


-- DWS.set_desired_state will attempt to patch the Workflow's desired
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
	local patch = [[kubectl patch workflow ]] .. self.name .. [[ --type=merge -p '{"spec":{]] .. new_spec .. [[}}' 2>&1]]
	return self:io_popen(patch)
end

-- DWS.io_popen will run the given command and collect its output.
-- On success this returns true.
-- On failure this returns false and the output of the command.
function DWS:io_popen(cmd)
	local handle = io.popen(cmd)
	if handle == nil then
		-- The io.popen was stubbed by a test.  Use the provided
		-- return values.
		return self.mock_io_popen.ret, self.mock_io_popen.result
	end
	local result = handle:read("*a")
	-- The exit status is an integer in rc[3].
	local rc = {handle:close()}
	if rc[3] ~= 0 then
		return false, result
	end
	return true, result
end

