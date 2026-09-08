-- The functions the MCP bridge calls over RPC. Everything here returns plain
-- Lua tables that survive vim.json.encode, and never blocks longer than
-- `timeout_ms` waiting on the debug adapter.
local M = {}

local ns = vim.api.nvim_create_namespace("claude_dap_highlight")

local DEFAULTS = {
  timeout_ms = 4000,
  source_context = 12,
  max_children = 60,
  max_depth = 2,
  max_string = 400,
}

--- Runs an async nvim-dap request as if it were synchronous.
--- nvim-dap hands results to a callback; the RPC caller wants a return value.
local function await(fn, timeout)
  local done, result, err = false, nil, nil
  local ok, perr = pcall(fn, function(e, r)
    err, result, done = e, r, true
  end)
  if not ok then
    return nil, tostring(perr)
  end
  vim.wait(timeout or DEFAULTS.timeout_ms, function()
    return done
  end, 10)
  if not done then
    return nil, "timed out waiting for the debug adapter"
  end
  if err then
    return nil, (type(err) == "table" and (err.message or vim.inspect(err))) or tostring(err)
  end
  return result, nil
end

local function dap()
  return require("dap")
end

local function session()
  return dap().session()
end

local function truncate(s)
  if type(s) ~= "string" then
    return s
  end
  if #s > DEFAULTS.max_string then
    return s:sub(1, DEFAULTS.max_string) .. "…(truncated)"
  end
  return s
end

local function bufnr_for(path)
  local bufnr = vim.fn.bufadd(vim.fn.fnamemodify(path, ":p"))
  vim.fn.bufload(bufnr)
  return bufnr
end

local function read_lines(path, from, to)
  local bufnr = vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
  local lines
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    local ok, res = pcall(vim.fn.readfile, path)
    if not ok then
      return nil
    end
    lines = res
  end
  from = math.max(1, from or 1)
  to = math.min(#lines, to or #lines)
  local out = {}
  for i = from, to do
    table.insert(out, { line = i, text = lines[i] })
  end
  return out
end

-------------------------------------------------------------- breakpoints ----

--- All breakpoints, whoever set them: the user with <leader>db, or the agent.
--- nvim-dap keeps a single list, so there is no separate agent-owned state.
function M.breakpoints()
  local bps = require("dap.breakpoints").get()
  local out = {}
  for bufnr, buf_bps in pairs(bps) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    for _, bp in ipairs(buf_bps) do
      table.insert(out, {
        file = path,
        line = bp.line,
        condition = bp.condition,
        hit_condition = bp.hitCondition,
        log_message = bp.logMessage,
        state = bp.state,
        verified = bp.state == nil or bp.state.verified,
      })
    end
  end
  table.sort(out, function(a, b)
    if a.file == b.file then
      return a.line < b.line
    end
    return a.file < b.file
  end)
  return out
end

local function sync_breakpoints(bufnr)
  local s = session()
  if not s then
    return
  end
  local all = require("dap.breakpoints").get(bufnr)
  s:set_breakpoints({ [bufnr] = all[bufnr] or {} })
end

function M.set_breakpoint(opts)
  opts = opts or {}
  if not opts.file or not opts.line then
    return { ok = false, error = "file and line are required" }
  end
  local bufnr = bufnr_for(opts.file)
  local total = vim.api.nvim_buf_line_count(bufnr)
  if opts.line < 1 or opts.line > total then
    return { ok = false, error = ("line %d is outside %s (1-%d)"):format(opts.line, opts.file, total) }
  end
  require("dap.breakpoints").set({
    condition = opts.condition,
    hit_condition = opts.hit_condition,
    log_message = opts.log_message,
  }, bufnr, opts.line)
  sync_breakpoints(bufnr)
  return { ok = true, breakpoints = M.breakpoints() }
end

function M.remove_breakpoint(opts)
  opts = opts or {}
  if not opts.file or not opts.line then
    return { ok = false, error = "file and line are required" }
  end
  local bufnr = bufnr_for(opts.file)
  require("dap.breakpoints").remove(bufnr, opts.line)
  sync_breakpoints(bufnr)
  return { ok = true, breakpoints = M.breakpoints() }
end

function M.clear_breakpoints()
  dap().clear_breakpoints()
  return { ok = true, breakpoints = {} }
end

------------------------------------------------------------------ context ----

local function expand_variables(s, ref, depth, budget)
  if depth > DEFAULTS.max_depth or budget.n <= 0 then
    return nil
  end
  local res, err = await(function(cb)
    s:request("variables", { variablesReference = ref }, cb)
  end)
  if err or not res or not res.variables then
    return nil
  end
  local out = {}
  for _, v in ipairs(res.variables) do
    if budget.n <= 0 then
      break
    end
    budget.n = budget.n - 1
    local entry = {
      name = v.name,
      value = truncate(v.value),
      type = v.type,
    }
    if v.variablesReference and v.variablesReference > 0 then
      entry.children = expand_variables(s, v.variablesReference, depth + 1, budget)
    end
    table.insert(out, entry)
  end
  return out
end

local function frame_to_table(f)
  return {
    id = f.id,
    name = f.name,
    line = f.line,
    column = f.column,
    file = f.source and f.source.path or nil,
    source_name = f.source and f.source.name or nil,
  }
end

--- The single call the agent makes before answering anything about the
--- debugger. Never cached: the user may have stepped since the last question.
function M.context(opts)
  opts = opts or {}
  local s = session()
  if not s then
    return {
      running = false,
      stopped = false,
      message = "No debug session. Breakpoints below are set but nothing is running.",
      breakpoints = M.breakpoints(),
      cursor = M.cursor(),
    }
  end

  local out = {
    running = true,
    stopped = s.stopped_thread_id ~= nil,
    adapter = s.config and s.config.type,
    config_name = s.config and s.config.name,
    filetype = s.filetype,
    breakpoints = M.breakpoints(),
    cursor = M.cursor(),
  }

  if not out.stopped then
    out.message = "Session is running but not paused; no frame or variables available."
    return out
  end

  local frame = s.current_frame
  if not frame then
    out.message = "Stopped but no current frame reported yet."
    return out
  end

  out.frame = frame_to_table(frame)
  out.thread_id = s.stopped_thread_id

  local thread = s.threads[s.stopped_thread_id]
  if thread and thread.frames then
    out.stack = vim.tbl_map(frame_to_table, thread.frames)
  end

  if frame.source and frame.source.path then
    local ctx = opts.source_context or DEFAULTS.source_context
    out.source = read_lines(frame.source.path, frame.line - ctx, frame.line + ctx)
  end

  -- Scopes are requested by nvim-dap on stop, but re-request so a frame the
  -- user switched to by hand is also covered.
  local scopes_res = await(function(cb)
    s:request("scopes", { frameId = frame.id }, cb)
  end)
  local scopes = (scopes_res and scopes_res.scopes) or frame.scopes
  if scopes then
    local budget = { n = opts.max_children or DEFAULTS.max_children }
    out.scopes = {}
    for _, sc in ipairs(scopes) do
      -- Globals/registers are huge and rarely what the question is about.
      local skip = sc.expensive or (sc.name or ""):lower():match("global") or (sc.name or ""):lower():match("register")
      table.insert(out.scopes, {
        name = sc.name,
        expensive = sc.expensive or false,
        variables = (not skip) and expand_variables(s, sc.variablesReference, 1, budget) or nil,
        note = skip and "skipped (expensive scope) - use dap_eval to inspect specific names" or nil,
      })
    end
  end

  return out
end

function M.cursor()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local pos = vim.api.nvim_win_get_cursor(win)
  return {
    file = vim.api.nvim_buf_get_name(buf),
    line = pos[1],
    column = pos[2] + 1,
    filetype = vim.bo[buf].filetype,
  }
end

--------------------------------------------------------------- evaluation ----

function M.eval(opts)
  opts = opts or {}
  if not opts.expression then
    return { ok = false, error = "expression is required" }
  end
  local s = session()
  if not s then
    return { ok = false, error = "no debug session" }
  end
  if not s.stopped_thread_id then
    return { ok = false, error = "session is running, not paused - cannot evaluate" }
  end
  local frame_id = opts.frame_id or (s.current_frame and s.current_frame.id)
  local res, err = await(function(cb)
    s:request("evaluate", {
      expression = opts.expression,
      frameId = frame_id,
      -- "watch" evaluates as an expression in the frame. "repl" makes some
      -- adapters (codelldb) parse the input as a debugger command instead.
      context = opts.context or "watch",
    }, cb)
  end)
  if err then
    return { ok = false, error = err, expression = opts.expression }
  end
  local out = {
    ok = true,
    expression = opts.expression,
    result = truncate(res.result),
    type = res.type,
  }
  if res.variablesReference and res.variablesReference > 0 then
    out.children = expand_variables(s, res.variablesReference, 1, { n = DEFAULTS.max_children })
  end
  return out
end

------------------------------------------------------------------ control ----

local ACTIONS = {
  continue = function(d) d.continue() end,
  step_over = function(d) d.step_over() end,
  step_into = function(d) d.step_into() end,
  step_out = function(d) d.step_out() end,
  step_back = function(d) d.step_back() end,
  run_to_cursor = function(d) d.run_to_cursor() end,
  pause = function(d) d.pause() end,
  terminate = function(d) d.terminate() end,
  restart = function(d) d.restart() end,
  disconnect = function(d) d.disconnect() end,
}

--- Advances the debuggee. Separate from `goto_location`, which only moves the
--- user's cursor, so a request to "look at" code can never execute anything.
function M.control(opts)
  opts = opts or {}
  local action = opts.action
  local fn = ACTIONS[action]
  if not fn then
    return { ok = false, error = "unknown action: " .. tostring(action), valid = vim.tbl_keys(ACTIONS) }
  end
  local s = session()
  if not s and action ~= "continue" then
    return { ok = false, error = "no debug session (use dap_launch or action=continue to start one)" }
  end

  -- Remember where we were: "stopped with a frame" is already true when a step
  -- begins, so waiting on that alone returns the frame we just left.
  local before
  if s and s.current_frame then
    before = {
      id = s.current_frame.id,
      line = s.current_frame.line,
      path = s.current_frame.source and s.current_frame.source.path,
    }
  end

  fn(dap())

  local wait = opts.wait_ms or 4000
  vim.wait(wait, function()
    local cur = session()
    if not cur then
      return true
    end
    if action == "terminate" or action == "disconnect" then
      return false
    end
    local f = cur.current_frame
    if cur.stopped_thread_id == nil or f == nil then
      return false
    end
    if not before then
      return true
    end
    return f.id ~= before.id
      or f.line ~= before.line
      or (f.source and f.source.path) ~= before.path
  end, 20)

  return { ok = true, action = action, context = M.context({ source_context = opts.source_context }) }
end

------------------------------------------------------------------- launch ----

function M.configurations()
  local d = dap()
  local out = {}
  for ft, configs in pairs(d.configurations) do
    for i, c in ipairs(configs) do
      table.insert(out, { filetype = ft, index = i, name = c.name, type = c.type, request = c.request })
    end
  end
  return out
end

--- Starts a session. `name` matches a configured launch config; `config`
--- passes a raw DAP configuration table straight through.
function M.launch(opts)
  opts = opts or {}
  local d = dap()

  if opts.config then
    d.run(opts.config)
    return { ok = true, started = opts.config.name or "inline config" }
  end

  if not opts.name then
    return { ok = false, error = "name or config is required", available = M.configurations() }
  end

  for ft, configs in pairs(d.configurations) do
    if not opts.filetype or opts.filetype == ft then
      for _, c in ipairs(configs) do
        if c.name == opts.name then
          local merged = vim.deepcopy(c)
          -- Interactive pickers (vim.fn.input, pick_process) would hang an RPC
          -- call, so overrides must supply those values up front.
          for k, v in pairs(opts.overrides or {}) do
            merged[k] = v
          end
          for k, v in pairs(merged) do
            if type(v) == "function" then
              return {
                ok = false,
                error = ("config %q needs a value for %q (it prompts interactively); pass it in overrides"):format(opts.name, k),
              }
            end
          end
          d.run(merged)
          -- Wait for the program to actually hit a breakpoint (or run to
          -- completion), so the returned context is the paused state rather
          -- than a half-started session.
          vim.wait(opts.wait_ms or 10000, function()
            local s = session()
            return s == nil or (s.stopped_thread_id ~= nil and s.current_frame ~= nil)
          end, 50)
          return { ok = true, started = opts.name, context = M.context() }
        end
      end
    end
  end

  return { ok = false, error = "no configuration named " .. opts.name, available = M.configurations() }
end

--------------------------------------------------------------- navigation ----

--- Moves the user's cursor. Read-only with respect to the debuggee.
function M.goto_location(opts)
  opts = opts or {}
  if not opts.file then
    return { ok = false, error = "file is required" }
  end
  local path = vim.fn.fnamemodify(opts.file, ":p")
  if vim.fn.filereadable(path) == 0 then
    return { ok = false, error = "not readable: " .. path }
  end

  -- Prefer a window already showing a normal file over the dap-ui panes.
  local target_win
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    local bt = vim.bo[b].buftype
    if bt == "" and vim.api.nvim_win_get_config(win).relative == "" then
      target_win = target_win or win
      if vim.api.nvim_buf_get_name(b) == path then
        target_win = win
        break
      end
    end
  end
  target_win = target_win or vim.api.nvim_get_current_win()

  vim.api.nvim_win_call(target_win, function()
    vim.cmd.edit(vim.fn.fnameescape(path))
    local line = math.max(1, math.min(opts.line or 1, vim.api.nvim_buf_line_count(0)))
    vim.api.nvim_win_set_cursor(target_win, { line, (opts.column or 1) - 1 })
    vim.cmd("normal! zz")
  end)
  if opts.focus ~= false then
    vim.api.nvim_set_current_win(target_win)
  end

  return { ok = true, cursor = M.cursor(), source = read_lines(path, (opts.line or 1) - 8, (opts.line or 1) + 8) }
end

--- Highlights a line range while explaining it, with an optional inline note.
function M.highlight(opts)
  opts = opts or {}
  if opts.clear then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_clear_namespace, b, ns, 0, -1)
    end
    return { ok = true, cleared = true }
  end
  if not opts.file or not opts.start_line then
    return { ok = false, error = "file and start_line are required (or clear=true)" }
  end
  local bufnr = bufnr_for(opts.file)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local last = vim.api.nvim_buf_line_count(bufnr)
  local from = math.max(1, opts.start_line)
  local to = math.min(last, opts.end_line or opts.start_line)
  for l = from, to do
    vim.api.nvim_buf_set_extmark(bufnr, ns, l - 1, 0, {
      line_hl_group = opts.hl_group or "DiffAdd",
      virt_text = (l == from and opts.note) and { { "  " .. opts.note, "Comment" } } or nil,
      virt_text_pos = "eol",
    })
  end
  return { ok = true, file = opts.file, start_line = from, end_line = to }
end

function M.source(opts)
  opts = opts or {}
  if not opts.file then
    return { ok = false, error = "file is required" }
  end
  local lines = read_lines(vim.fn.fnamemodify(opts.file, ":p"), opts.start_line, opts.end_line)
  if not lines then
    return { ok = false, error = "could not read " .. opts.file }
  end
  return { ok = true, file = opts.file, lines = lines }
end

--- Switches which stack frame `context` and `eval` report on, and jumps the
--- user's cursor there too, so both sides are looking at the same frame.
function M.select_frame(opts)
  opts = opts or {}
  local s = session()
  if not s or not s.stopped_thread_id then
    return { ok = false, error = "not paused" }
  end
  local thread = s.threads[s.stopped_thread_id]
  local frames = thread and thread.frames or {}
  local target
  for _, f in ipairs(frames) do
    if f.id == opts.frame_id then
      target = f
      break
    end
  end
  if not target and opts.index then
    target = frames[opts.index]
  end
  if not target then
    return { ok = false, error = "frame not found", stack = vim.tbl_map(frame_to_table, frames) }
  end
  s:_frame_set(target)
  return { ok = true, context = M.context() }
end

function M.status()
  local s = session()
  return {
    nvim_pid = vim.fn.getpid(),
    cwd = vim.loop.cwd(),
    session = s ~= nil,
    stopped = s ~= nil and s.stopped_thread_id ~= nil,
    breakpoint_count = #M.breakpoints(),
  }
end

return M
