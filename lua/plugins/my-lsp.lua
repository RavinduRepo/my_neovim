return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--fallback-style=llvm",
            -- 1. Force Clangd to use the MinGW target instead of MSVC
            "--extra-arg=--target=x86_64-w64-mingw32",
            -- 2. Windows requires the .exe extension for the glob to work
            "--query-driver=C:/**/gcc.exe,C:/**/g++.exe",
          },
        },
        intelephense = {
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
        },
        -- Verilog / SystemVerilog LSP Configuration
        verible = {
          filetypes = { "verilog", "systemverilog" },
          root_dir = function(fname)
            local util = require("lspconfig.util")
            -- Updated to use native vim.fs.dirname to fix deprecation warning
            return util.root_pattern(".git")(fname) or vim.fs.dirname(fname)
          end,
        },
      },
    },
  },
}
