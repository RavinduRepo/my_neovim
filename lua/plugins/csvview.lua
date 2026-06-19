return {
  "hat0uma/csvview.nvim",
  ft = { "csv", "tsv" },
  keys = {
    -- Sets up the keybind and automatically adds a description for WhichKey
    { "<leader>uU", "<cmd>CsvViewToggle<CR>", desc = "Toggle CSV View" },
  },
  opts = {
    view = {
      display_mode = "border",
    },
  },
  config = function(_, opts)
    require("csvview").setup(opts)

    -- Enable immediately for the first CSV you open that triggers the plugin load
    vim.cmd("CsvViewEnable")

    -- Create an autocommand to ensure it automatically enables for any
    -- additional CSVs you open in the same Neovim session
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "csv", "tsv" },
      callback = function()
        vim.cmd("CsvViewEnable")
      end,
    })
  end,
}
