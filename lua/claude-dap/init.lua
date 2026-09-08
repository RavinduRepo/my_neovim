-- claude-dap: exposes the running nvim-dap session to an external agent over
-- Neovim's msgpack-RPC socket, so a Claude Code MCP bridge can read debugger
-- state, drive execution, and steer the user's cursor.
local M = {}

M.config = {
  -- Extra RPC socket dedicated to the bridge. Deterministic per-cwd so the
  -- bridge can find the right Neovim instance without configuration.
  socket_dir = vim.fn.stdpath("cache") .. "/claude-dap",
  register = true,
}

local state = {
  socket = nil,
  registry = nil,
}

local function is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local function cwd_key()
  local cwd = vim.loop.cwd() or vim.fn.getcwd()
  return vim.fn.sha256(cwd):sub(1, 12), cwd
end

local function socket_path()
  local key = cwd_key()
  if is_windows() then
    return [[\\.\pipe\claude-dap-]] .. key
  end
  return M.config.socket_dir .. "/" .. key .. ".sock"
end

local function registry_path()
  return M.config.socket_dir .. "/sessions.json"
end

local function read_registry()
  local f = io.open(registry_path(), "r")
  if not f then
    return {}
  end
  local raw = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return {}
end

-- The registry lets the bridge map its own working directory to a socket.
-- Stale entries (dead Neovim instances) are pruned on every write.
local function write_registry(entry)
  local reg = read_registry()
  local key, cwd = cwd_key()

  for k, v in pairs(reg) do
    if type(v) == "table" and tonumber(v.pid) then
      local alive = pcall(vim.loop.kill, tonumber(v.pid), 0)
      if not alive then
        reg[k] = nil
      end
    end
  end

  if entry then
    reg[key] = {
      cwd = cwd,
      socket = entry,
      pid = vim.fn.getpid(),
      servername = vim.v.servername,
      updated = os.time(),
    }
  else
    reg[key] = nil
  end

  local f = io.open(registry_path(), "w")
  if f then
    f:write(vim.json.encode(reg))
    f:close()
  end
end

function M.setup(opts)
  if state.socket then
    return -- already set up in this instance; a second serverstart would fail
  end
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  vim.fn.mkdir(M.config.socket_dir, "p")

  local path = socket_path()
  if not is_windows() then
    -- A socket left behind by a crashed instance blocks serverstart.
    pcall(vim.loop.fs_unlink, path)
  end

  local ok, sock = pcall(vim.fn.serverstart, path)
  if ok then
    state.socket = sock
    if M.config.register then
      write_registry(sock)
    end
  else
    vim.notify("claude-dap: could not start RPC socket: " .. tostring(sock), vim.log.levels.WARN)
  end

  vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
    callback = function()
      if M.config.register then
        pcall(write_registry, nil)
      end
      if state.socket then
        pcall(vim.fn.serverstop, state.socket)
      end
    end,
  })

  -- Keep the registry pointed at the current project after :cd.
  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      if state.socket and M.config.register then
        pcall(write_registry, state.socket)
      end
    end,
  })

  vim.api.nvim_create_user_command("ClaudeDapInfo", function()
    print(vim.inspect({
      socket = state.socket,
      registry = registry_path(),
      bridge = M.bridge_dir(),
    }))
  end, { desc = "Show the claude-dap bridge socket" })

  vim.api.nvim_create_user_command("ClaudeDapInstall", function()
    M.install()
  end, { desc = "Install bridge deps and register the MCP server on this machine" })
end

--- The bridge lives next to this config, not in a fixed path, so the whole
--- thing travels with whatever machine clones the nvim repo.
function M.bridge_dir()
  local this = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(this, ":p:h:h:h") .. "/claude-dap-bridge"
end

--- Everything a fresh machine needs, in one command: bridge dependencies,
--- debug adapters, and MCP registration. Safe to re-run.
function M.install()
  local dir = M.bridge_dir()
  local steps = {}

  local function step(name, ok, detail)
    table.insert(steps, (ok and "  ok    " or "  FAIL  ") .. name .. (detail and ("  - " .. detail) or ""))
    return ok
  end

  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("claude-dap: bridge not found at " .. dir, vim.log.levels.ERROR)
    return
  end

  vim.notify("claude-dap: installing…", vim.log.levels.INFO)

  -- 1. Bridge dependencies.
  if vim.fn.executable("npm") == 0 then
    step("npm install", false, "npm is not on PATH - install Node first")
  else
    local npm = vim.system({ "npm", "install" }, { cwd = dir, text = true }):wait()
    step("npm install", npm.code == 0, npm.code ~= 0 and vim.trim(npm.stderr or "") or nil)
  end

  -- 2. Debug adapters, through the registry API rather than :MasonInstall,
  -- which opens a UI and blocks. Installs run in the background.
  local adapters = { "codelldb", "js-debug-adapter", "php-debug-adapter" }
  local reg_ok, registry = pcall(require, "mason-registry")
  if not reg_ok then
    step("debug adapters", false, "mason.nvim not available")
  else
    local queued, present = {}, {}
    for _, name in ipairs(adapters) do
      local pkg_ok, pkg = pcall(registry.get_package, name)
      if not pkg_ok then
        table.insert(queued, name .. " (unknown package)")
      elseif pkg:is_installed() then
        table.insert(present, name)
      else
        pcall(function() pkg:install() end)
        table.insert(queued, name)
      end
    end
    local detail = {}
    if #present > 0 then
      table.insert(detail, #present .. " already installed")
    end
    if #queued > 0 then
      table.insert(detail, "installing " .. table.concat(queued, ", "))
    end
    step("debug adapters", true, table.concat(detail, "; "))
  end

  -- 3. Register the MCP server with Claude Code, pointing at this machine's path.
  if vim.fn.executable("claude") == 0 then
    step("claude mcp add", false, "`claude` not on PATH; run manually:\n"
      .. "        claude mcp add claude-dap --scope user -- node " .. dir .. "/index.js")
  else
    -- Remove first: re-registering is how a stale path gets corrected.
    vim.system({ "claude", "mcp", "remove", "claude-dap", "--scope", "user" }, { text = true }):wait()
    local add = vim.system({
      "claude", "mcp", "add", "claude-dap", "--scope", "user",
      "--", "node", dir .. "/index.js",
    }, { text = true }):wait()
    step("claude mcp add", add.code == 0, add.code ~= 0 and vim.trim(add.stderr or "") or nil)
  end

  local failed = #vim.tbl_filter(function(l) return l:match("^  FAIL") end, steps)
  vim.notify(
    "claude-dap install\n" .. table.concat(steps, "\n")
      .. (failed == 0 and "\n\nDone. Restart any running `claude` session." or ""),
    failed == 0 and vim.log.levels.INFO or vim.log.levels.WARN
  )
end

function M.socket()
  return state.socket
end

return M
