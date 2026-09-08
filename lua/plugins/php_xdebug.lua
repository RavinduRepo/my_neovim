return {
  "mfussenegger/nvim-dap",
  config = function()
    local dap = require("dap")

    -- adapter (Mason already provides the binary)
    dap.adapters.php = {
      type = "executable",
      command = vim.fn.stdpath("data") .. "/mason/bin/php-debug-adapter",
    }

    -- launch configurations
    dap.configurations.php = {
      {
        type = "php",
        request = "launch",
        name = "Listen for Xdebug (Docker)",
        port = 9003,
        pathMappings = {
          -- Example: If you run `pwd` inside Docker and get `/home/ubuntu/cutanddry`,
          -- change the string below to "/home/ubuntu/cutanddry"
          ["/var/local/cut-dry/git"] = "${workspaceFolder}",
        },
      },
    }
  end,
}
