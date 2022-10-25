require("burst_buffer/burst_buffer")

CRDFILE="/dws/config/crd/bases/dws.cray.hpe.com_clientmounts.yaml"

describe("The burst buffer test script", function()
	describe("should import burst_buffer.lua", function()
		it("and allow function calls", function()
			_G.HelloWorld()
		end)
		it("and validate Custom Resources", function()
			local goodCr = _G.GetGoodCR()
			local out = io.popen("echo \"" .. goodCr  .. "\" | /bin/validate " .. CRDFILE)
			local rc = {out:close()}
			assert.are.equals(0, rc[3])
		end)
		it("and identify mistakes in Custom Resources", function()
			local badCr = _G.GetBadCR()
			local out = io.popen("echo \"" .. badCr  .. "\" | /bin/validate " .. CRDFILE)
			local rc = {out:close()}
			assert.are.equals(1, rc[3])
		end)
	end)
end)
