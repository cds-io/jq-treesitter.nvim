-- Debug helper for jq-treesitter
local M = {}

function M.test_list()
  local bufnr = vim.api.nvim_get_current_buf()
  print("Current buffer:", bufnr)
  print("Buffer name:", vim.api.nvim_buf_get_name(bufnr))
  
  local ft = vim.bo[bufnr].filetype
  print("Filetype:", ft)
  
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if ok then
    print("Treesitter parsers loaded")
    local lang = parsers.get_buf_lang(bufnr)
    print("Detected language:", lang)
    
    if lang == 'json' or lang == 'yaml' then
      -- Get parser and check tree
      local parser = parsers.get_parser(bufnr)
      local tree = parser:parse()[1]
      local root = tree:root()
      print("Root node type:", root:type())
      print("Root node child count:", root:child_count())
      
      -- Debug first few children
      for i = 0, math.min(3, root:child_count() - 1) do
        local child = root:child(i)
        print("  Child " .. i .. " type:", child:type())
      end
      
      -- Test the query directly
      local query_string = [[
        (object
          (pair
            key: (string (string_content) @key)
            value: (_) @value
          ) @pair
        )
      ]]
      
      local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
      if ok_query then
        print("Query parsed successfully")
        local capture_count = 0
        for id, node in query:iter_captures(root, bufnr, 0, -1) do
          capture_count = capture_count + 1
          if capture_count <= 5 then
            local name = query.captures[id]
            local text = vim.treesitter.get_node_text(node, bufnr):sub(1, 50)
            print("  Capture:", name, "->", text)
          end
        end
        print("Total captures:", capture_count)
      else
        print("Query parse failed")
      end
      
      local init = require('jq-treesitter')
      local keys = init.extract_json_keys(bufnr)
      print("Found keys:", #keys)
      for i, key in ipairs(keys) do
        print("  Key " .. i .. ":", key.key, "at line", key.line)
      end
    else
      print("Not a JSON/YAML file")
    end
  else
    print("Failed to load treesitter parsers")
  end
end

vim.api.nvim_create_user_command('JqtDebug', M.test_list, {})

return M