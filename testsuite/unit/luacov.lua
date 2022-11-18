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

-- This file will be copied to a ".luacov" file before testing with busted.
--
-- Refer to the following link for more information on configuraing Luacov.
-- https://github.com/lunarmodules/luacov#configuration
include = {
   "burst_buffer$",
   "burst_buffer%/.+$",
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
