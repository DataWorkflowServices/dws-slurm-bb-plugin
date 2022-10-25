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