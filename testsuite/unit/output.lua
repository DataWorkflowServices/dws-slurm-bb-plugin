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

-- The path to this script is provided to Busted using the "-o/--output" flag,
-- allowing busted to output execution results in the junit and terminal
-- format.
--
-- Refer to the following link for more information on Busted output.
-- https://lunarmodules.github.io/busted/#output-handlers
local output = function(options)
    local busted = require("busted")
    local handler = require("busted.outputHandlers.base")()
  
    local junitHandler = require("busted.outputHandlers.junit")
    junitHandler(options):subscribe(options)

    options.arguments = {}
    local utfTerminalHandler = require("busted.outputHandlers.utfTerminal")
    utfTerminalHandler(options):subscribe(options)
  
    return handler
  end
  
  return output