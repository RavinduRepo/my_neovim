---@diagnostic disable: undefined-global
-- =============================================================================
--  NEOVIM NATIVE ASSEMBLY VIEWER (Robust & Crash-Free)
-- =============================================================================

-- 1. GLOBAL STATE
_G.asm_state = {
  buf_cpp = nil,
  win_cpp = nil,
  buf_asm = nil,
  win_asm = nil,
  ns_id = vim.api.nvim_create_namespace("AsmHighlighter"),
  augroup = vim.api.nvim_create_augroup("AsmSyncGroup", { clear = true }),

  config = {
    opt_level = "-O3",
    std_ver = "-std=c++20",
    extra_flags = "",
    use_project_conf = true,
  },
}

-- 2. HELPER: Read compile_flags.txt
local function get_project_flags()
  if not _G.asm_state.config.use_project_conf then
    return {}
  end

  local flag_file = vim.fn.findfile("compile_flags.txt", ".;")
  if flag_file == "" then
    return {}
  end

  local lines = vim.fn.readfile(flag_file)
  local flags = {}
  for _, line in ipairs(lines) do
    if line ~= "" and not line:match("^%s*#") then
      table.insert(flags, line)
    end
  end
  return flags
end

-- 3. CONFIGURATION MENU (<leader>dz)
function _G.configure_asm()
  local options = {
    "1. Optimization Level (Current: " .. _G.asm_state.config.opt_level .. ")",
    "2. C++ Standard (Current: " .. _G.asm_state.config.std_ver .. ")",
    "3. Extra Flags (Current: '" .. _G.asm_state.config.extra_flags .. "')",
    "4. Toggle compile_flags.txt Auto-read (Current: " .. tostring(_G.asm_state.config.use_project_conf) .. ")",
  }

  vim.ui.select(options, { prompt = "Assembly Viewer Configuration:" }, function(choice, idx)
    if not idx then
      return
    end

    if idx == 1 then
      vim.ui.select({ "-O0", "-O1", "-O2", "-O3", "-Os", "-Ofast" }, { prompt = "Select Optimization:" }, function(opt)
        if opt then
          _G.asm_state.config.opt_level = opt
        end
      end)
    elseif idx == 2 then
      vim.ui.select(
        { "-std=c++11", "-std=c++14", "-std=c++17", "-std=c++20", "-std=c++23" },
        { prompt = "Select Standard:" },
        function(std)
          if std then
            _G.asm_state.config.std_ver = std
          end
        end
      )
    elseif idx == 3 then
      vim.ui.input(
        { prompt = "Enter flags (e.g. -I./src -Wall): ", default = _G.asm_state.config.extra_flags },
        function(input)
          if input then
            _G.asm_state.config.extra_flags = input
          end
        end
      )
    elseif idx == 4 then
      _G.asm_state.config.use_project_conf = not _G.asm_state.config.use_project_conf
      vim.notify("Auto-read project config: " .. tostring(_G.asm_state.config.use_project_conf), vim.log.levels.INFO)
    end
  end)
end

-- 4. CLEANUP FUNCTION (<leader>dX)
function _G.close_asm_view()
  vim.api.nvim_clear_autocmds({ group = _G.asm_state.augroup })

  if _G.asm_state.win_asm and vim.api.nvim_win_is_valid(_G.asm_state.win_asm) then
    vim.api.nvim_win_close(_G.asm_state.win_asm, true)
  end

  if _G.asm_state.buf_cpp and vim.api.nvim_buf_is_valid(_G.asm_state.buf_cpp) then
    vim.api.nvim_buf_clear_namespace(_G.asm_state.buf_cpp, _G.asm_state.ns_id, 0, -1)
  end

  _G.asm_state.buf_asm = nil
  _G.asm_state.win_asm = nil
  vim.notify("Assembly view closed.", vim.log.levels.INFO)
end

-- 5. SYNC LOGIC (CRASH FIXES APPLIED)
local function sync_cursor()
  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_get_current_buf()

  -- A. Moving in C++ -> Highlight ASM
  if cur_buf == _G.asm_state.buf_cpp and _G.asm_state.buf_asm and vim.api.nvim_buf_is_valid(_G.asm_state.buf_asm) then
    local cursor_line = vim.api.nvim_win_get_cursor(_G.asm_state.win_cpp)[1]
    local asm_lines = vim.api.nvim_buf_get_lines(_G.asm_state.buf_asm, 0, -1, false)

    -- Optimize: Check reasonable range around cursor or scan?
    -- For now, linear scan is fast enough for <10k lines
    for i, line in ipairs(asm_lines) do
      if line:match("%s*%.loc%s+%d+%s+" .. cursor_line .. "%s+") then
        if vim.api.nvim_win_is_valid(_G.asm_state.win_asm) then
          vim.api.nvim_win_set_cursor(_G.asm_state.win_asm, { i, 0 })
          vim.api.nvim_win_call(_G.asm_state.win_asm, function()
            vim.cmd("normal! zz")
          end)

          vim.api.nvim_buf_clear_namespace(_G.asm_state.buf_asm, _G.asm_state.ns_id, 0, -1)
          vim.api.nvim_buf_add_highlight(_G.asm_state.buf_asm, _G.asm_state.ns_id, "Visual", i - 1, 0, -1)
        end
        break
      end
    end

  -- B. Moving in ASM -> Highlight C++
  elseif
    cur_buf == _G.asm_state.buf_asm
    and _G.asm_state.buf_cpp
    and vim.api.nvim_buf_is_valid(_G.asm_state.buf_cpp)
  then
    local cursor_line = vim.api.nvim_win_get_cursor(_G.asm_state.win_asm)[1]
    local asm_lines = vim.api.nvim_buf_get_lines(_G.asm_state.buf_asm, 0, cursor_line, false)

    for i = #asm_lines, 1, -1 do
      local line = asm_lines[i]
      local match_line = line:match("%s*%.loc%s+%d+%s+(%d+)")

      if match_line then
        local target_line = tonumber(match_line)
        local total_lines = vim.api.nvim_buf_line_count(_G.asm_state.buf_cpp)

        -- SECURITY CHECK: Prevent crash if line is outside buffer
        -- (This happens if asm points to a header file line #500 but source is only 50 lines)
        if target_line > 0 and target_line <= total_lines then
          if vim.api.nvim_win_is_valid(_G.asm_state.win_cpp) then
            vim.api.nvim_buf_clear_namespace(_G.asm_state.buf_cpp, _G.asm_state.ns_id, 0, -1)
            vim.api.nvim_buf_add_highlight(_G.asm_state.buf_cpp, _G.asm_state.ns_id, "Visual", target_line - 1, 0, -1)
          end
        end
        break
      end
    end
  end
end

-- 6. COMPILER MAIN FUNCTION
function _G.open_asm_view(mode)
  local file = vim.fn.expand("%:p")
  if file == "" then
    return print("Save file first!")
  end

  _G.asm_state.buf_cpp = vim.api.nvim_get_current_buf()
  _G.asm_state.win_cpp = vim.api.nvim_get_current_win()

  -- Base Flags
  local flags = { "clang++", "-S", "-masm=intel", "-g", "-fno-asynchronous-unwind-tables" }

  -- Optimization
  if mode == "debug" then
    table.insert(flags, "-O0")
  else
    table.insert(flags, _G.asm_state.config.opt_level)
  end

  -- Add Standard & Extra Flags
  table.insert(flags, _G.asm_state.config.std_ver)
  for flag in _G.asm_state.config.extra_flags:gmatch("%S+") do
    table.insert(flags, flag)
  end

  -- Add Project Flags
  local project_flags = get_project_flags()
  for _, flag in ipairs(project_flags) do
    table.insert(flags, flag)
  end

  -- Output
  table.insert(flags, file)
  table.insert(flags, "-o")
  table.insert(flags, "-")

  local cmd_str = table.concat(flags, " ")
  vim.notify("Compiling: " .. cmd_str, vim.log.levels.INFO)

  vim.fn.jobstart(flags, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data or #data < 2 then
        return
      end

      -- 1. Create Split
      vim.cmd("vsplit")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_create_buf(true, true)

      -- 2. Attach Buffer (CRITICAL)
      vim.api.nvim_win_set_buf(win, buf)

      -- 3. Fill Content
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, data)
      vim.api.nvim_buf_set_option(buf, "filetype", "asm")
      vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
      vim.api.nvim_buf_set_option(buf, "modifiable", false)
      vim.api.nvim_buf_set_name(buf, "ASM: " .. mode)

      _G.asm_state.win_asm = win
      _G.asm_state.buf_asm = buf

      -- 4. Sync
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = _G.asm_state.augroup,
        callback = sync_cursor,
      })

      -- 5. Focus back on C++
      vim.api.nvim_set_current_win(_G.asm_state.win_cpp)
    end,
    on_stderr = function(_, data)
      local err = table.concat(data, "\n")
      if #err > 1 then
        vim.notify("Error:\n" .. err, vim.log.levels.ERROR)
      end
    end,
  })
end

-- 7. KEYMAPS (Auto-set ONLY for C/C++ files)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function(event)
    local opts = { buffer = event.buf, silent = true, noremap = true }

    vim.keymap.set("n", "<leader>dxx", function()
      _G.open_asm_view("release")
    end, vim.tbl_extend("force", opts, { desc = "ASM: Synced Release" }))

    vim.keymap.set("n", "<leader>dxd", function()
      _G.open_asm_view("debug")
    end, vim.tbl_extend("force", opts, { desc = "ASM: Synced Debug" }))

    vim.keymap.set("n", "<leader>dX", function()
      _G.close_asm_view()
    end, vim.tbl_extend("force", opts, { desc = "ASM: Close View" }))

    vim.keymap.set("n", "<leader>dz", function()
      _G.configure_asm()
    end, vim.tbl_extend("force", opts, { desc = "ASM: Configure Flags" }))
  end,
})
