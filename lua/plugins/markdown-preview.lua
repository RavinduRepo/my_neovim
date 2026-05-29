return {
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }

      -- 1. Define the global Lua function to handle the browser launch
      _G.open_mkdp_window = function(url)
        local os_name = vim.loop.os_uname().sysname
        local cmd

        -- Pre-configured for Brave Browser
        local linux_win_browser = "brave-browser"
        local mac_browser = "Brave Browser"

        if os_name == "Darwin" then
          -- macOS: Uses the `open` command.
          -- `-n` forces a new instance, `--args` passes the window flag.
          cmd = { "open", "-n", "-a", mac_browser, "--args", "--new-window", url }
        elseif os_name == "Linux" then
          -- Linux: Standard execution with the window flag
          cmd = { linux_win_browser, "--new-window", url }
        elseif os_name == "Windows_NT" then
          -- Windows: Uses the `start` command via cmd
          cmd = { "cmd.exe", "/c", "start", linux_win_browser, "--new-window", url }
        end

        -- Execute the command asynchronously in the background
        if cmd then
          vim.fn.jobstart(cmd, { detach = true })
        end
      end

      -- 2. Create a Vimscript wrapper bridge
      -- This is required because the plugin's Vimscript engine cannot handle pure v:lua strings natively
      vim.cmd([[
        function! OpenMarkdownPreview(url)
          call v:lua.open_mkdp_window(a:url)
        endfunction
      ]])

      -- 3. Point the plugin to the Vimscript wrapper instead of the Lua function
      vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
    end,
    ft = { "markdown" },
    keys = {
      { "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Browser Preview", ft = "markdown" },
    },
  },
}
