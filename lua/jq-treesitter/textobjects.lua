local M = {}
local api = vim.api
local ts = vim.treesitter

-- Get the JSON/YAML node at cursor
function M.get_node_at_cursor(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local parser = ts.get_parser(bufnr)
  local tree = parser:parse()[1]

  return tree:root():descendant_for_range(row, col, row, col)
end

-- Find the value node for a given position
function M.find_value_node(node)
  if not node then
    return nil
  end

  local node_type = node:type()

  -- If we're on a value, return it
  if
    node_type == 'object'
    or node_type == 'array'
    or node_type == 'string'
    or node_type == 'number'
    or node_type == 'true'
    or node_type == 'false'
    or node_type == 'null'
  then
    return node
  end

  -- If we're in a pair, get the value
  local parent = node:parent()
  while parent do
    if parent:type() == 'pair' then
      local value = parent:field('value')[1]
      if value then
        return value
      end
    end
    parent = parent:parent()
  end

  return nil
end

-- Find the pair node (key-value) at cursor
function M.find_pair_node(node)
  if not node then
    return nil
  end

  while node do
    if node:type() == 'pair' or node:type() == 'block_mapping_pair' then
      return node
    end
    node = node:parent()
  end

  return nil
end

-- Select a node's range
function M.select_node(node)
  if not node then
    return
  end

  local start_row, start_col, end_row, end_col = node:range()

  -- Enter visual mode and select
  vim.cmd 'normal! v'
  api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  vim.cmd 'normal! o'
  api.nvim_win_set_cursor(0, { end_row + 1, end_col - 1 })
end

-- Text object: inner JSON value (vij, dij, cij)
function M.select_inner_value()
  local bufnr = api.nvim_get_current_buf()
  local node = M.get_node_at_cursor(bufnr)
  local value_node = M.find_value_node(node)

  if value_node then
    -- For strings, select content without quotes
    if value_node:type() == 'string' then
      local content = value_node:field('content')[1]
      if content then
        M.select_node(content)
        return
      end
    end

    -- For objects/arrays, select content without brackets
    if value_node:type() == 'object' or value_node:type() == 'array' then
      local start_row, start_col, end_row, end_col = value_node:range()
      vim.cmd 'normal! v'
      api.nvim_win_set_cursor(0, { start_row + 1, start_col + 1 })
      vim.cmd 'normal! o'
      api.nvim_win_set_cursor(0, { end_row + 1, end_col - 2 })
      return
    end

    M.select_node(value_node)
  end
end

-- Text object: around JSON value (vaj, daj, caj)
function M.select_around_value()
  local bufnr = api.nvim_get_current_buf()
  local node = M.get_node_at_cursor(bufnr)
  local value_node = M.find_value_node(node)

  if value_node then
    M.select_node(value_node)
  end
end

-- Text object: inner JSON pair (vip, dip, cip)
function M.select_inner_pair()
  local bufnr = api.nvim_get_current_buf()
  local node = M.get_node_at_cursor(bufnr)
  local pair_node = M.find_pair_node(node)

  if pair_node then
    M.select_node(pair_node)
  end
end

-- Text object: around JSON pair (vap, dap, cap)
function M.select_around_pair()
  local bufnr = api.nvim_get_current_buf()
  local node = M.get_node_at_cursor(bufnr)
  local pair_node = M.find_pair_node(node)

  if pair_node then
    -- Include trailing comma if present
    local end_row, end_col = pair_node:end_()
    local line = api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
    if line and line:sub(end_col + 1, end_col + 1) == ',' then
      end_col = end_col + 1
    end

    local start_row, start_col = pair_node:start()
    vim.cmd 'normal! v'
    api.nvim_win_set_cursor(0, { start_row + 1, start_col })
    vim.cmd 'normal! o'
    api.nvim_win_set_cursor(0, { end_row + 1, end_col })
  end
end

-- Setup text object mappings
function M.setup_textobjects(bufnr)
  local opts = { buffer = bufnr, silent = true }

  -- Inner value
  vim.keymap.set({ 'x', 'o' }, 'ij', function()
    M.select_inner_value()
  end, vim.tbl_extend('force', opts, { desc = 'inner JSON value' }))

  -- Around value
  vim.keymap.set({ 'x', 'o' }, 'aj', function()
    M.select_around_value()
  end, vim.tbl_extend('force', opts, { desc = 'around JSON value' }))

  -- Inner pair
  vim.keymap.set({ 'x', 'o' }, 'ik', function()
    M.select_inner_pair()
  end, vim.tbl_extend('force', opts, { desc = 'inner JSON key-value pair' }))

  -- Around pair
  vim.keymap.set({ 'x', 'o' }, 'ak', function()
    M.select_around_pair()
  end, vim.tbl_extend('force', opts, { desc = 'around JSON key-value pair' }))
end

return M
