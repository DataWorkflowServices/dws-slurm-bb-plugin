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