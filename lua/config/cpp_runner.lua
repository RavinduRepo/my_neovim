---@diagnostic disable: undefined-global
-- =============================================================================
--  NATIVE C++ RUNNER (Compact Version)
-- =============================================================================

_G.cpp_runner = {
  buf = nil,
  win = nil,
  config = {
    compiler = "clang++",
    std = "-std=c++20",
    opt = "-O2",
    flags = "-Wall",
    use_project_conf = true,
  },
}

-- 1. HELPER: Read compile_flags.txt
local function get_runner_flags()
  if not _G.cpp_runner.config.use_project_conf then
    return ""
  end
  local file = vim.fn.findfile("compile_flags.txt", ".;")
  if file == "" then
    return ""
  end

  local lines = vim.fn.readfile(file)
  local flags = {}
  for _, line in ipairs(lines) do
    if line ~= "" and not line:match("^%s*#") then
      table.insert(flags, line)
    end
  end
  return table.concat(flags, " ")
end

-- 2. CONFIG MENU (<leader>z)
function _G.cpp_runner_config()
  local options = {
    "1. Compiler (Current: " .. _G.cpp_runner.config.compiler .. ")",
    "2. Standard (Current: " .. _G.cpp_runner.config.std .. ")",
    "3. Optimization (Current: " .. _G.cpp_runner.config.opt .. ")",
    "4. Extra Flags (Current: '" .. _G.cpp_runner.config.flags .. "')",
    "5. Auto-read compile_flags.txt (Current: " .. tostring(_G.cpp_runner.config.use_project_conf) .. ")",
  }

  vim.ui.select(options, { prompt = "C++ Runner Config" }, function(choice, idx)
    if not idx then
      return
    end

    if idx == 1 then
      vim.ui.input({ prompt = "Compiler:", default = _G.cpp_runner.config.compiler }, function(input)
        if input then
          _G.cpp_runner.config.compiler = input
        end
      end)
    elseif idx == 2 then
      vim.ui.select(
        { "-std=c++11", "-std=c++14", "-std=c++17", "-std=c++20", "-std=c++23" },
        { prompt = "Standard" },
        function(s)
          if s then
            _G.cpp_runner.config.std = s
          end
        end
      )
    elseif idx == 3 then
      vim.ui.select({ "-O0", "-O1", "-O2", "-O3", "-Ofast" }, { prompt = "Optimization" }, function(o)
        if o then
          _G.cpp_runner.config.opt = o
        end
      end)
    elseif idx == 4 then
      vim.ui.input({ prompt = "Flags:", default = _G.cpp_runner.config.flags }, function(input)
        if input then
          _G.cpp_runner.config.flags = input
        end
      end)
    elseif idx == 5 then
      _G.cpp_runner.config.use_project_conf = not _G.cpp_runner.config.use_project_conf
      vim.notify("Auto-read project config: " .. tostring(_G.cpp_runner.config.use_project_conf), vim.log.levels.INFO)
    end
  end)
end

-- 3. INTERNAL CLOSE (Used to reset before running again)
local function close_runner_internal()
  if _G.cpp_runner.win and vim.api.nvim_win_is_valid(_G.cpp_runner.win) then
    if #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(_G.cpp_runner.win, true)
    else
      vim.api.nvim_buf_delete(_G.cpp_runner.buf, { force = true })
    end
  end
  _G.cpp_runner.win = nil
  _G.cpp_runner.buf = nil
end

-- 4. COMPILE AND RUN (<leader>r)
function _G.cpp_runner_run()
  -- Save file
  vim.cmd("silent! w")

  local file = vim.fn.expand("%:p")
  if file == "" then
    return print("File not saved!")
  end

  local output_bin = vim.fn.expand("%:p:r") .. ".out"

  -- Build Command
  local cmd_parts = {
    _G.cpp_runner.config.compiler,
    _G.cpp_runner.config.std,
    _G.cpp_runner.config.opt,
    _G.cpp_runner.config.flags,
    get_runner_flags(),
    vim.fn.shellescape(file),
    "-o",
    vim.fn.shellescape(output_bin),
    "&&",
    vim.fn.shellescape(output_bin),
  }

  local full_cmd = table.concat(cmd_parts, " ")

  -- Auto-close old window if it exists
  close_runner_internal()

  -- Create fresh window (botright 15new)
  vim.cmd("botright 15new")

  _G.cpp_runner.win = vim.api.nvim_get_current_win()
  _G.cpp_runner.buf = vim.api.nvim_get_current_buf()

  -- Configure buffer
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.swapfile = false

  -- Run
  vim.fn.termopen(full_cmd)
  vim.cmd("startinsert")
  vim.api.nvim_buf_set_name(_G.cpp_runner.buf, "Run: " .. vim.fn.expand("%:t"))
end

-- 5. KEYMAPS (Only r and z)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function(event)
    local opts = { buffer = event.buf, silent = true, noremap = true }

    -- Run Code
    vim.keymap.set("n", "<leader>r", function()
      _G.cpp_runner_run()
    end, vim.tbl_extend("force", opts, { desc = "Run Code (Terminal)" }))

    -- Configure
    vim.keymap.set("n", "<leader>z", function()
      _G.cpp_runner_config()
    end, vim.tbl_extend("force", opts, { desc = "Configure Runner" }))
  end,
})
