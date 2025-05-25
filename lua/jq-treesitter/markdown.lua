local M = {}

-- Find the surrounding object node at cursor position
function M.find_surrounding_object(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok then
    return nil
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil
  end

  local tree = trees[1]
  if not tree then
    return nil
  end

  local root = tree:root()
  if not root then
    return nil
  end

  local node = root:descendant_for_range(row, col, row, col)

  -- Walk up the tree to find an object or array node
  while node do
    local node_type = node:type()
    if node_type == 'object' or node_type == 'array' or node_type == 'block_mapping' or node_type == 'block_sequence' then
      return node
    end
    node = node:parent()
  end

  return nil
end

-- Extract key-value pairs from an object node
function M.extract_object_data(node, bufnr)
  local lang = vim.treesitter.get_parser(bufnr):lang()
  local data = {}

  local query_string
  if lang == 'json' then
    query_string = [[
      (object
        (pair
          key: (string (string_content) @key)
          value: (_) @value
        )
      )
    ]]
  else
    query_string = [[
      (block_mapping
        (block_mapping_pair
          key: (flow_node) @key
          value: (_) @value
        )
      )
    ]]
  end

  local query = vim.treesitter.query.parse(lang, query_string)

  for id, capture_node in query:iter_captures(node, bufnr) do
    local name = query.captures[id]
    if name == 'key' then
      local key = vim.treesitter.get_node_text(capture_node, bufnr)
      key = key:gsub('^"', ''):gsub('"$', '') -- Remove quotes

      local parent = capture_node:parent()
      if parent then
        local value_nodes = parent:field 'value'
        if value_nodes and #value_nodes > 0 then
          local value_node = value_nodes[1]
          if value_node then
            local value = vim.treesitter.get_node_text(value_node, bufnr)

            -- Clean up value formatting
            value = value:gsub('^"', ''):gsub('"$', '') -- Remove quotes
            value = value:gsub('\n', ' ') -- Replace newlines with spaces

            table.insert(data, { key = key, value = value })
          end
        end
      end
    end
  end

  return data
end

-- Extract array of objects data
function M.extract_array_data(node, bufnr)
  local lang = vim.treesitter.get_parser(bufnr):lang()
  local rows = {}
  local headers = {}
  local headers_set = {}

  -- First pass: collect all unique keys
  for child in node:iter_children() do
    if child:type() == 'object' then
      local obj_data = M.extract_object_data(child, bufnr)
      for _, kv in ipairs(obj_data) do
        if not headers_set[kv.key] then
          headers_set[kv.key] = true
          table.insert(headers, kv.key)
        end
      end
    end
  end

  -- Second pass: build rows
  for child in node:iter_children() do
    if child:type() == 'object' then
      local obj_data = M.extract_object_data(child, bufnr)
      local row = {}

      -- Create a map for quick lookup
      local data_map = {}
      for _, kv in ipairs(obj_data) do
        data_map[kv.key] = kv.value
      end

      -- Build row with all headers
      for _, header in ipairs(headers) do
        row[header] = data_map[header] or ''
      end

      table.insert(rows, row)
    end
  end

  return headers, rows
end

-- Convert object to markdown table
function M.object_to_markdown_table(data)
  if #data == 0 then
    return ''
  end

  local lines = {}

  -- Header
  table.insert(lines, '| Key | Value |')
  table.insert(lines, '|-----|-------|')

  -- Data rows
  for _, kv in ipairs(data) do
    local value = kv.value:gsub('|', '\\|') -- Escape pipes
    table.insert(lines, string.format('| %s | %s |', kv.key, value))
  end

  return table.concat(lines, '\n')
end

-- Convert array of objects to markdown table
function M.array_to_markdown_table(headers, rows)
  if #headers == 0 or #rows == 0 then
    return ''
  end

  local lines = {}

  -- Header
  local header_line = '| ' .. table.concat(headers, ' | ') .. ' |'
  table.insert(lines, header_line)

  -- Separator
  local separator = '|'
  for _, _ in ipairs(headers) do
    separator = separator .. '-----|'
  end
  table.insert(lines, separator)

  -- Data rows
  for _, row in ipairs(rows) do
    local values = {}
    for _, header in ipairs(headers) do
      local value = row[header] or ''
      value = value:gsub('|', '\\|') -- Escape pipes
      table.insert(values, value)
    end
    table.insert(lines, '| ' .. table.concat(values, ' | ') .. ' |')
  end

  return table.concat(lines, '\n')
end

-- Main function to copy surrounding object as markdown table
function M.copy_as_markdown_table()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = M.find_surrounding_object(bufnr)

  if not node then
    vim.notify('No surrounding object or array found', vim.log.levels.WARN)
    return
  end

  local node_type = node:type()
  local markdown

  if node_type == 'object' or node_type == 'block_mapping' then
    local data = M.extract_object_data(node, bufnr)
    markdown = M.object_to_markdown_table(data)
  elseif node_type == 'array' or node_type == 'block_sequence' then
    local headers, rows = M.extract_array_data(node, bufnr)
    markdown = M.array_to_markdown_table(headers, rows)
  end

  if markdown and markdown ~= '' then
    vim.fn.setreg('+', markdown)
    vim.notify 'Copied as markdown table to clipboard'
  else
    vim.notify('Could not convert to markdown table', vim.log.levels.WARN)
  end
end

return M
