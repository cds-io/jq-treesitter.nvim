local M = {}

-- Parse jq expression into components
function M.parse_jq_expression(expr)
  -- Check for pipe and object construction
  local path, filter = expr:match '^(.-)%s*|%s*(.+)$'
  if not path then
    path = expr
  end

  local construct_fields = nil
  if filter and filter:match '^{.-}$' then
    -- Extract field names from {name,type} format
    local fields_str = filter:match '^{(.-)}$'
    construct_fields = vim.split(fields_str, ',', { trimempty = true })
    for i, field in ipairs(construct_fields) do
      construct_fields[i] = vim.trim(field)
    end
  end

  return path, construct_fields
end

-- Convert jq-style path to treesitter query
-- Examples:
-- .foo -> root object key "foo"
-- .foo.bar -> nested path
-- .[0] -> array index
-- .[] -> all array elements
-- .abi | {name,type} -> get abi field and construct objects with name,type
function M.jq_to_treesitter_query(jq_path, lang)
  local parts = vim.split(jq_path, '.', { plain = true, trimempty = true })

  if lang == 'json' then
    return M.build_json_query(parts)
  else
    return M.build_yaml_query(parts)
  end
end

function M.build_json_query(parts)
  if #parts == 0 then
    return '(object) @value'
  end

  local query = ''

  for i, part in ipairs(parts) do
    if part:match '^%[%d+%]$' then
      -- Array index
      local index = part:match '%[(%d+)%]'
      query = query .. ' (pair value: (array (_) @element))'
    elseif part == '[]' then
      -- All array elements (handled separately in execute_query)
      -- Just get the array itself
      query = query .. ' @value'
    else
      -- Object key
      if i == 1 then
        query = string.format('(object (pair key: (string (string_content) @key (#eq? @key "%s")) value: (_) @value))', part)
      else
        -- For nested queries, we need to wrap the previous query
        query = string.format('(object (pair key: (string (string_content) @key (#eq? @key "%s")) value: %s))', part, query)
      end
    end
  end

  return query
end

function M.build_yaml_query(parts)
  -- Similar implementation for YAML
  local query = ''
  for i, part in ipairs(parts) do
    if i == 1 then
      query = string.format('(block_mapping_pair key: (flow_node) @key (#eq? @key "%s") value: (_) @value)', part)
    else
      -- Nested queries for YAML
      query = string.format('(block_mapping_pair key: (flow_node) @key (#eq? @key "%s") value: %s)', part, query)
    end
  end
  return query
end

-- Extract specific fields from an object node
function M.extract_object_fields(node, bufnr, fields, lang)
  local result = {}

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

      for _, field in ipairs(fields) do
        if key == field then
          local value_node = capture_node:parent():field('value')[1]
          local value = vim.treesitter.get_node_text(value_node, bufnr)
          result[field] = value
        end
      end
    end
  end

  -- Construct JSON-like output
  local parts = {}
  for _, field in ipairs(fields) do
    if result[field] then
      table.insert(parts, string.format('"%s": %s', field, result[field]))
    end
  end

  return '{' .. table.concat(parts, ', ') .. '}'
end

-- Execute a jq-style query on the current buffer
function M.execute_query(expr)
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(bufnr)
  local tree = parser:parse()[1]
  local root = tree:root()
  local lang = parser:lang()

  local path, construct_fields = M.parse_jq_expression(expr)

  -- Handle array access .[] at the end
  local array_access = false
  if path:match '%[%]$' then
    array_access = true
    path = path:gsub('%[%]$', '')
  end

  local query_string = M.jq_to_treesitter_query(path, lang)
  local ok, query = pcall(vim.treesitter.query.parse, lang, query_string)

  if not ok then
    vim.notify('Invalid query: ' .. expr, vim.log.levels.ERROR)
    return nil
  end

  local results = {}
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == 'value' or name == 'element' or name == 'elements' then
      if array_access and node:type() == 'array' then
        -- Process array elements
        for child in node:iter_children() do
          if child:type() ~= ',' and child:type() ~= '[' and child:type() ~= ']' then
            if construct_fields and child:type() == 'object' then
              -- Extract specific fields from each object in array
              local obj_result = M.extract_object_fields(child, bufnr, construct_fields, lang)
              table.insert(results, obj_result)
            else
              local text = vim.treesitter.get_node_text(child, bufnr)
              table.insert(results, text)
            end
          end
        end
      elseif construct_fields and node:type() == 'object' then
        -- Extract specific fields from object
        local obj_result = M.extract_object_fields(node, bufnr, construct_fields, lang)
        table.insert(results, obj_result)
      else
        local text = vim.treesitter.get_node_text(node, bufnr)
        table.insert(results, text)
      end
    end
  end

  return results
end

return M
