return {
  {
    "neovim/nvim-lspconfig",
    -- Note the addition of '(_, opts)' here to inherit LazyVim's defaults
    opts = function(_, opts)
      -- 1. Detect if we are on Windows
      local is_windows = vim.fn.has("win32") == 1

      -- 2. Define the base cross-platform clangd arguments
      local clangd_cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders",
        "--fallback-style=llvm",
      }

      -- 3. Append Windows-specific arguments only when necessary
      if is_windows then
        table.insert(clangd_cmd, "--extra-arg=--target=x86_64-w64-mingw32")
        table.insert(clangd_cmd, "--query-driver=C:/**/gcc.exe,C:/**/g++.exe")
      end

      -- 4. Safely inject your custom servers into the existing opts table
      opts.servers = opts.servers or {}

      opts.servers.clangd = {
        cmd = clangd_cmd,
      }

      opts.servers.intelephense = {
        settings = {
          intelephense = {
            files = {
              exclude = {
                "**/.git/**",
                "**/vendor/**",
                "**/node_modules/**",
                "**/storage/**",
                "**/cache/**",
              },
            },
            memory = {
              limit = 4096,
            },
          },
        },
      }

      -- Verilog / SystemVerilog LSP Configuration
      opts.servers.verible = {
        filetypes = { "verilog", "systemverilog" },
        root_dir = function(fname)
          local util = require("lspconfig.util")
          return util.root_pattern(".git")(fname) or vim.fs.dirname(fname)
        end,
      }
    end,
  },
}
