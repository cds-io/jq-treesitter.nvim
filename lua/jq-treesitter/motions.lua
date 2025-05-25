local M = {}
local api = vim.api
local ts = vim.treesitter

-- Get all navigable positions in the buffer
function M.get_navigable_positions(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local positions = {}

  -- Use the treesitter-nav module to get navigable items
  local nav = require 'jq-treesitter.treesitter-nav'
  local structure = nav.parse_json_structure(bufnr)

  -- Convert navigable items to positions
  for _, item in ipairs(structure.navigable_items) do
    table.insert(positions, {
      row = item.line - 1, -- Convert to 0-based
      col = 0, -- Start of line
      item = item,
    })
  end

  -- For arrays, add positions for each element
  if structure.type == 'array' then
    -- Elements are already in navigable_items
  end

  return positions
end

-- Jump to next navigable item
function M.goto_next_navigable(bufnr)
  local positions = M.get_navigable_positions(bufnr)
  if #positions == 0 then
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  local current_row = cursor[1] - 1
  local current_col = cursor[2]

  -- Find next position
  for _, pos in ipairs(positions) do
    if pos.row > current_row or (pos.row == current_row and pos.col > current_col) then
      api.nvim_win_set_cursor(0, { pos.row + 1, pos.col })
      return
    end
  end

  -- Wrap to first
  api.nvim_win_set_cursor(0, { positions[1].row + 1, positions[1].col })
end

-- Jump to previous navigable item
function M.goto_prev_navigable(bufnr)
  local positions = M.get_navigable_positions(bufnr)
  if #positions == 0 then
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  local current_row = cursor[1] - 1
  local current_col = cursor[2]

  -- Find previous position
  for i = #positions, 1, -1 do
    local pos = positions[i]
    if pos.row < current_row or (pos.row == current_row and pos.col < current_col) then
      api.nvim_win_set_cursor(0, { pos.row + 1, pos.col })
      return
    end
  end

  -- Wrap to last
  local last = positions[#positions]
  api.nvim_win_set_cursor(0, { last.row + 1, last.col })
end

-- Setup motion mappings
function M.setup_motions(bufnr)
  local opts = { buffer = bufnr, silent = true }

  -- Navigation motions
  vim.keymap.set('n', ']j', function()
    M.goto_next_navigable(bufnr)
  end, vim.tbl_extend('force', opts, { desc = 'Next JSON navigable item' }))
  vim.keymap.set('n', '[j', function()
    M.goto_prev_navigable(bufnr)
  end, vim.tbl_extend('force', opts, { desc = 'Previous JSON navigable item' }))
end

return M
