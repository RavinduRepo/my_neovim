return {
  "HakonHarnes/img-clip.nvim",
  event = "VeryLazy",
  keys = {
    -- Lowercase 'p': Paste to your global Notes directory
    {
      "<leader>p",
      function()
        require("img-clip").paste_image({
          -- vim.fn.expand translates the '~' to your actual home directory path
          dir_path = vim.fn.expand("~/Notes/assets"),
          use_absolute_path = true,
        })
      end,
      desc = "Paste image to Global Notes",
    },

    -- Uppercase 'P': Paste to the local project directory
    {
      "<leader>P",
      function()
        require("img-clip").paste_image({
          -- Creates an 'assets' folder relative to the current file
          dir_path = "assets",
          use_absolute_path = false,
        })
      end,
      desc = "Paste image to Local Project",
    },
  },
}
