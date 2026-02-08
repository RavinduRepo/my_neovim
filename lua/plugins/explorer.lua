return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- 1. Define the custom action (The "What to do")
        actions = {
          cd_to_folder = function(picker, item)
            -- Safety check: ensure an item is selected
            if not item then
              return
            end

            -- 'item.file' contains the full path of the selected row
            local path = item.file

            -- Check if the selected item is actually a directory
            if vim.fn.isdirectory(path) == 1 then
              -- Execute the change directory command
              vim.cmd("cd " .. path)
              -- Notify you so you know it happened
              vim.notify("Changed directory to: " .. path, vim.log.levels.INFO)
            else
              -- If you press gx on a file, warn the user
              vim.notify("Not a folder. Cannot cd into it.", vim.log.levels.WARN)
            end
          end,
        },

        sources = {
          explorer = {
            -- Your existing layout config (Right side)
            layout = {
              layout = {
                position = "right",
              },
            },
            -- 2. Map the key (The "Trigger")
            win = {
              list = {
                keys = {
                  -- Map 'gx' to the custom action we defined above
                  ["gx"] = "cd_to_folder",
                },
              },
            },
          },
        },
      },
    },
  },
}
