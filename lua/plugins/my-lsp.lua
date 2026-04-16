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
      },
    },
  },
}
