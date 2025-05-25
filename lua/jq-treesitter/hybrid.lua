local M = {}

-- Check if jq is available
function M.check_jq()
  local handle = io.popen('which jq 2>/dev/null')
  local result = handle:read('*a')
  handle:close()
  return result ~= ''
end

-- Extract JSON subtree using treesitter, then apply jq expression
function M.execute_hybrid_query(expr, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Check if we have a simple path vs complex jq expression
  local simple_path = expr:match('^%.[%w_]+$')
  
  if simple_path then
    -- For simple paths like .abi, use treesitter to navigate directly
    return M.treesitter_navigate(simple_path:sub(2), bufnr)
  else
    -- For complex expressions, get the full buffer content and use jq
    if not M.check_jq() then
      vim.notify('jq is required for complex queries', vim.log.levels.ERROR)
      return nil
    end
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    
    -- Use jq to process the expression
    local cmd = string.format('echo %s | jq %s 2>&1', vim.fn.shellescape(content), vim.fn.shellescape(expr))
    local handle = io.popen(cmd)
    local result = handle:read('*a')
    local success = handle:close()
    
    if not success then
      vim.notify('jq error: ' .. result, vim.log.levels.ERROR)
      return nil
    end
    
    return result
  end
end

-- Use treesitter to navigate to a specific key
function M.treesitter_navigate(key, bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok then
    return nil
  end
  
  local tree = parser:parse()[1]
  local root = tree:root()
  local lang = parser:lang()
  
  if lang ~= 'json' and lang ~= 'yaml' then
    return nil
  end
  
  local query_string
  if lang == 'json' then
    query_string = string.format([[
      (object
        (pair
          key: (string (string_content) @key (#eq? @key "%s"))
          value: (_) @value
        )
      )
    ]], key)
  else
    query_string = string.format([[
      (block_mapping_pair
        key: (flow_node) @key (#eq? @key "%s")
        value: (_) @value
      )
    ]], key)
  end
  
  local query = vim.treesitter.query.parse(lang, query_string)
  
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == 'value' then
      return vim.treesitter.get_node_text(node, bufnr)
    end
  end
  
  return nil
end

-- Get treesitter node at cursor position for contextual queries
function M.get_node_at_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  
  local parser = vim.treesitter.get_parser(bufnr)
  local tree = parser:parse()[1]
  
  return tree:root():descendant_for_range(row, col, row, col)
end

-- Extract the JSON path to current cursor position
function M.get_path_to_cursor(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok then
    return nil
  end
  
  local lang = parser:lang()
  if lang ~= 'json' and lang ~= 'yaml' then
    return nil
  end
  
  local node = M.get_node_at_cursor(bufnr)
  if not node then return nil end
  
  local path = {}
  local current = node
  
  while current do
    local parent = current:parent()
    if not parent then break end
    
    -- Check if this is a key-value pair
    if parent:type() == 'pair' then
      local key_node = parent:field('key')[1]
      if key_node then
        local key = vim.treesitter.get_node_text(key_node, bufnr)
        key = key:gsub('^"', ''):gsub('"$', '')
        table.insert(path, 1, key)
      end
    elseif parent:type() == 'array' then
      -- Find index in array
      local index = 0
      for child in parent:iter_children() do
        if child == current then
          break
        end
        if child:type() ~= ',' and child:type() ~= '[' and child:type() ~= ']' then
          index = index + 1
        end
      end
      table.insert(path, 1, '[' .. index .. ']')
    end
    
    current = parent
  end
  
  return '.' .. table.concat(path, '.')
end

return M