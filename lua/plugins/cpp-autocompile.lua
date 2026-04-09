return {
  "mfussenegger/nvim-dap",
  optional = true,
  opts = function()
    local dap = require("dap")
    -- This overrides the default C++ config to compile before running
    dap.configurations.cpp = {
      {
        name = "Compile & Debug (Auto)",
        type = "codelldb", -- or "lldb" if you strictly use native lldb
        request = "launch",
        program = function()
          -- 1. Get current file name
          local file = vim.fn.expand("%")
          local output = vim.fn.expand("%:r") -- Filename without extension (the binary)

          -- 2. Compile with clang and debug symbols (-g)
          -- 'os.execute' halts the UI momentarily to compile
          local cmd = "clang++ -g " .. file .. " -o " .. output
          print("Compiling: " .. cmd .. "...")
          local result = os.execute(cmd)

          -- 3. Check if compile worked
          if result == 0 then
            print("Compilation successful! Starting debugger...")
            return vim.fn.getcwd() .. "/" .. output
          else
            print("Compilation failed.")
            return dap.ABORT -- Stop the debugger if compile fails
          end
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }
    -- Apply same config to C
    dap.configurations.c = dap.configurations.cpp
  end,
}
