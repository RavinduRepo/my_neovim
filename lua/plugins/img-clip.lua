return {
  "HakonHarnes/img-clip.nvim",
  event = "VeryLazy",
  opts = {
    default = {
      -- Saves images to an 'assets' folder next to your markdown file
      dir_path = "assets",
      -- Keeps paths relative (e.g., ![](assets/image.png)) instead of absolute
      use_absolute_path = false,
      -- Set to true if you want to type a custom name for every pasted image
      prompt_for_file_name = false,
    },
  },
  keys = {
    -- Press <leader>p to paste the image
    { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from system clipboard" },
  },
}
