local M = {}
local api = vim.api

M.preview_win = nil
M.preview_buf = nil
M.preview_timer = nil

-- Show preview of value under cursor
function M.show_preview()
  -- Get current navigation context
  local nav = require 'jq-treesitter.treesitter-nav'
  local bufnr = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Check if there's a navigable item on this line
  local extmarks = api.nvim_buf_get_extmarks(bufnr, nav.ns_id, { line - 1, 0 }, { line - 1, -1 }, { details = true })

  local key = nil
  for _, mark in ipairs(extmarks) do
    local virt_text = mark[4].virt_text
    if virt_text and virt_text[1] then
      local text = virt_text[1][1]
      key = text:match '%[(.+)%]'
      break
    end
  end

  if not key then
    M.close_preview()
    return
  end

  -- Build path for preview
  local preview_path
  if inline_nav.current_path == '' then
    if tonumber(key) then
      preview_path = '.[' .. key .. ']'
    else
      preview_path = '.' .. key
    end
  else
    if tonumber(key) then
      preview_path = inline_nav.current_path .. '[' .. key .. ']'
    else
      preview_path = inline_nav.current_path .. '.' .. key
    end
  end

  -- Get content for preview
  local temp_file = vim.fn.tempname() .. '.json'
  vim.fn.writefile(vim.split(inline_nav.original_content or '', '\n'), temp_file)

  local cmd = string.format('cat %s | jq %s 2>&1', vim.fn.shellescape(temp_file), vim.fn.shellescape(preview_path))
  local handle = io.popen(cmd)
  local content = handle:read '*a'
  handle:close()
  os.remove(temp_file)

  if content and not content:match 'error' then
    M.create_preview_window(content, preview_path)
  end
end

-- Create or update preview window
function M.create_preview_window(content, path)
  -- Create buffer if needed
  if not M.preview_buf or not api.nvim_buf_is_valid(M.preview_buf) then
    M.preview_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(M.preview_buf, 'filetype', 'json')
    api.nvim_buf_set_option(M.preview_buf, 'bufhidden', 'wipe')
  end

  -- Set content
  local lines = vim.split(content, '\n')
  table.insert(lines, 1, '── Preview: ' .. path .. ' ──')
  table.insert(lines, 2, '')
  api.nvim_buf_set_lines(M.preview_buf, 0, -1, false, lines)

  -- Create window if needed
  if not M.preview_win or not api.nvim_win_is_valid(M.preview_win) then
    local width = math.min(60, math.floor(vim.o.columns * 0.4))
    local height = math.min(20, #lines + 2)

    -- Position near cursor
    local cursor_pos = api.nvim_win_get_cursor(0)
    local win_pos = api.nvim_win_get_position(0)
    local win_width = api.nvim_win_get_width(0)

    M.preview_win = api.nvim_open_win(M.preview_buf, false, {
      relative = 'win',
      win = 0,
      width = width,
      height = height,
      col = win_width + 2,
      row = cursor_pos[1] - 1,
      style = 'minimal',
      border = 'rounded',
      focusable = false,
      noautocmd = true,
    })

    api.nvim_win_set_option(M.preview_win, 'winhl', 'Normal:Pmenu,FloatBorder:Pmenu')
  end
end

-- Close preview window
function M.close_preview()
  if M.preview_timer then
    vim.loop.timer_stop(M.preview_timer)
    M.preview_timer = nil
  end

  if M.preview_win and api.nvim_win_is_valid(M.preview_win) then
    api.nvim_win_close(M.preview_win, true)
    M.preview_win = nil
  end

  if M.preview_buf and api.nvim_buf_is_valid(M.preview_buf) then
    api.nvim_buf_delete(M.preview_buf, { force = true })
    M.preview_buf = nil
  end
end

-- Setup hover preview
function M.setup_preview(bufnr)
  local group = api.nvim_create_augroup('JqTreesitterPreview' .. bufnr, { clear = true })

  -- Show preview on cursor hold
  api.nvim_create_autocmd('CursorHold', {
    group = group,
    buffer = bufnr,
    callback = function()
      M.show_preview()
    end,
  })

  -- Hide preview on cursor move
  api.nvim_create_autocmd('CursorMoved', {
    group = group,
    buffer = bufnr,
    callback = function()
      M.close_preview()
    end,
  })

  -- Clean up on buffer leave
  api.nvim_create_autocmd('BufLeave', {
    group = group,
    buffer = bufnr,
    callback = function()
      M.close_preview()
    end,
  })

  -- Manual preview toggle
  vim.keymap.set('n', '<leader>jh', function()
    if M.preview_win and api.nvim_win_is_valid(M.preview_win) then
      M.close_preview()
    else
      M.show_preview()
    end
  end, { buffer = bufnr, desc = '[J]son [H]over preview toggle' })
end

return M
