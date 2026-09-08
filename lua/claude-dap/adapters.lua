-- Adapter + launch-configuration definitions for the languages this setup
-- teaches: C/C++ (codelldb), JS/React (vscode-js-debug), PHP (Xdebug).
local M = {}

local function mason_bin(name)
  local exe = vim.fn.stdpath("data") .. "/mason/bin/" .. name
  if vim.fn.has("win32") == 1 then
    exe = exe .. ".cmd"
  end
  return exe
end

local function have(name)
  return vim.fn.executable(mason_bin(name)) == 1
end

function M.setup()
  local dap = require("dap")

  ---------------------------------------------------------------- C / C++ ----
  if have("codelldb") then
    dap.adapters.codelldb = {
      type = "server",
      port = "${port}",
      executable = {
        command = mason_bin("codelldb"),
        args = { "--port", "${port}" },
      },
    }
  end

  local cpp_config = {
    {
      name = "Launch executable",
      type = "codelldb",
      request = "launch",
      program = function()
        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/build/", "file")
      end,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
      args = {},
    },
    {
      name = "Attach to process",
      type = "codelldb",
      request = "attach",
      pid = require("dap.utils").pick_process,
      cwd = "${workspaceFolder}",
    },
  }
  -- Each filetype gets its own copy; sharing one table means a later
  -- table.insert shows up several times over.
  for _, ft in ipairs({ "cpp", "c", "rust" }) do
    dap.configurations[ft] = vim.deepcopy(cpp_config)
  end

  ------------------------------------------------------ JavaScript / React ----
  if have("js-debug-adapter") then
    for _, adapter in ipairs({ "pwa-node", "pwa-chrome", "node-terminal" }) do
      dap.adapters[adapter] = {
        type = "server",
        host = "localhost",
        port = "${port}",
        executable = {
          command = mason_bin("js-debug-adapter"),
          args = { "${port}" },
        },
      }
    end
  end

  local js_config = {
    {
      name = "Chrome: attach to dev server",
      type = "pwa-chrome",
      request = "launch",
      url = "http://localhost:5173",
      webRoot = "${workspaceFolder}",
      sourceMaps = true,
      userDataDir = false,
    },
    {
      name = "Node: launch current file",
      type = "pwa-node",
      request = "launch",
      program = "${file}",
      cwd = "${workspaceFolder}",
      sourceMaps = true,
    },
    {
      name = "Node: attach to port 9229",
      type = "pwa-node",
      request = "attach",
      processId = require("dap.utils").pick_process,
      cwd = "${workspaceFolder}",
      sourceMaps = true,
    },
  }
  for _, ft in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
    dap.configurations[ft] = vim.deepcopy(js_config)
  end

  -------------------------------------------------------------------- PHP ----
  if have("php-debug-adapter") then
    dap.adapters.php = {
      type = "executable",
      command = mason_bin("php-debug-adapter"),
    }
  end

  dap.configurations.php = {
    {
      name = "Xdebug: listen for connection",
      type = "php",
      request = "launch",
      port = 9003,
      -- Local project root. Override per-project via .nvim-dap.lua or
      -- a launch.json when the code actually runs inside a container.
      pathMappings = {
        ["${workspaceFolder}"] = "${workspaceFolder}",
      },
    },
    {
      name = "Xdebug: launch current script",
      type = "php",
      request = "launch",
      program = "${file}",
      cwd = "${workspaceFolder}",
      port = 9003,
      runtimeArgs = {
        "-dxdebug.start_with_request=yes",
        "-dxdebug.mode=debug",
        "-dxdebug.client_port=9003",
      },
    },
  }

  ---------------------------------------------------------------- project ----
  -- Optional per-project overrides: a .nvim-dap.lua at the project root gets
  -- the `dap` module and can add or replace configurations.
  -- Searched upward, so opening nvim in a subdirectory still finds the
  -- project root's configuration.
  local found = vim.fs.find(".nvim-dap.lua", {
    upward = true,
    type = "file",
    path = vim.loop.cwd(),
    stop = vim.loop.os_homedir(),
  })
  local project = found[1]
  if project then
    local chunk, err = loadfile(project)
    if chunk then
      local ok, lerr = pcall(chunk, dap)
      if not ok then
        vim.notify("claude-dap: .nvim-dap.lua failed: " .. tostring(lerr), vim.log.levels.WARN)
      end
    else
      vim.notify("claude-dap: .nvim-dap.lua parse error: " .. tostring(err), vim.log.levels.WARN)
    end
  end
end

return M
