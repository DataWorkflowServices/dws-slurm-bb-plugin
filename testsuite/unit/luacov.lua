-- This file will be copied to a ".luacov" file before testing with busted.
--
-- Refer to the following link for more information on configuraing Luacov.
-- https://github.com/lunarmodules/luacov#configuration
include = {
   "burst_buffer$"
}

-- luacov-multiple allows two different outputs for coverage results. In this
-- case, coverage ouput is in an HTML report and a cobertura file.
-- See: https://github.com/to-kr/luacov-multiple
reporter = "multiple"
runreport = true
reportfile = "luacov.report.out"

multiple = {
    -- The luacov-multiple HTML report tool is not used. Instead, the report
    -- tool is replaced by luacov-html, which provides better reports that
    -- include source code coverage.
    -- See: https://wesen1.github.io/luacov-html/
    reporters = {"default", "multiple.cobertura", "html"},
    cobertura = {
        reportfile = 'cobertura.xml'
    }
}
