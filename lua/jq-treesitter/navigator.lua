local M = {}
local api = vim.api

-- Navigation state
M.nav_history = {}
M.current_path = ''
M.current_buf = nil
M.float_win = nil
M.source_bufnr = nil

-- Parse JSON value to extract keys for navigation
local function parse_json_keys(content)
  local keys = {}
  local unique = {}

  -- Try to parse as JSON object
  if content:match '^%s*{' then
    -- Find keys at the beginning of lines (more accurate for formatted JSON)
    for line in content:gmatch '[^\n]+' do
      local key = line:match '^%s*"([^"]+)"%s*:'
      if key and not unique[key] then
        unique[key] = true
        table.insert(keys, key)
      end
    end
  elseif content:match '^%s*%[' then
    -- Array - count elements more accurately
    local count = 0
    local depth = 0
    local in_string = false
    local escape = false

    for i = 1, #content do
      local char = content:sub(i, i)

      if not escape then
        if char == '"' and not in_string then
          in_string = true
        elseif char == '"' and in_string then
          in_string = false
        elseif not in_string then
          if char == '[' or char == '{' then
            depth = depth + 1
          elseif char == ']' or char == '}' then
            depth = depth - 1
          elseif char == ',' and depth == 1 then
            count = count + 1
          end
        end

        escape = (char == '\\' and in_string)
      else
        escape = false
      end
    end

    -- At least one element if we have content
    if content:match '%[%s*[^%s%]]' then
      count = count + 1
    end

    for i = 0, math.min(count - 1, 50) do -- Limit to first 50 elements
      table.insert(keys, '[' .. i .. ']')
    end
  end

  return keys
end

-- Create navigation content with keys highlighted
local function create_nav_content(content, path)
  local lines = vim.split(content, '\n')
  local nav_lines = {}
  local key_map = {} -- Maps line numbers to keys

  -- Add header with visual separator
  table.insert(nav_lines, '╭' .. string.rep('─', 78) .. '╮')
  table.insert(nav_lines, '│ Path: ' .. (path == '' and '(root)' or path) .. string.rep(' ', math.max(0, 71 - #path)) .. '│')
  table.insert(nav_lines, '│ Keys: X=drill down  <C-o>=back  <C-p>=copy path  q=close' .. string.rep(' ', 21) .. '│')
  table.insert(nav_lines, '╰' .. string.rep('─', 78) .. '╯')
  table.insert(nav_lines, '')

  -- Process content and mark navigable lines
  local keys = parse_json_keys(content)
  local line_offset = #nav_lines

  -- Track which lines we've already marked
  local marked_lines = {}

  -- Determine if we're looking at an object or array
  local is_array = content:match '^%s*%['
  local is_object = content:match '^%s*{'

  if is_object then
    -- For objects, mark all top-level keys
    for i, line in ipairs(lines) do
      for _, key in ipairs(keys) do
        if not key:match '^%[%d+%]$' then -- Skip array indices
          local pattern = '"' .. key:gsub('[%[%]]', '%%%1') .. '"%s*:'
          -- Only match if it's at the beginning of the line (top-level)
          if line:match('^%s*' .. pattern) then
            marked_lines[i] = key
            break
          end
        end
      end
    end
  elseif is_array then
    -- For arrays, mark the beginning of each element
    local element_count = 0
    local in_string = false
    local escape = false
    local depth = 0

    for i, line in ipairs(lines) do
      -- Simple approach: look for objects/values that start at the beginning of lines
      local trimmed = line:match '^%s*(.*)' or ''

      -- Count depth changes
      for j = 1, #line do
        local char = line:sub(j, j)
        if not escape and not in_string then
          if char == '{' or char == '[' then
            depth = depth + 1
          elseif char == '}' or char == ']' then
            depth = depth - 1
          elseif char == '"' then
            in_string = true
          end
        elseif in_string and not escape then
          if char == '"' then
            in_string = false
          end
        end
        escape = (char == '\\' and in_string and not escape)
      end

      -- Mark array elements (objects or values at the right depth)
      if depth == 1 and (trimmed:match '^{' or (trimmed:match '^"' and element_count < 20)) then
        marked_lines[i] = '[' .. element_count .. ']'
        element_count = element_count + 1
      end
    end
  end

  -- Create display lines with markers
  for i, line in ipairs(lines) do
    local key = marked_lines[i]
    local display_line = line

    if key then
      display_line = '→ ' .. line
      key_map[line_offset + i] = key
    end

    table.insert(nav_lines, display_line)
  end

  return nav_lines, key_map
end

-- Navigate to a specific key
function M.navigate_to_key(key)
  if not M.current_buf or not M.source_bufnr then
    return
  end

  -- Debug: Show what we're trying to navigate to
  -- vim.notify('Navigating from "' .. M.current_path .. '" to key "' .. key .. '"', vim.log.levels.INFO)

  -- Save current state to history
  table.insert(M.nav_history, {
    path = M.current_path,
    content = table.concat(api.nvim_buf_get_lines(M.current_buf, 0, -1, false), '\n'),
  })

  -- Build new path
  local new_path
  if M.current_path == '' then
    -- At root level
    if key:match '^%[%d+%]$' then
      -- Can't index root with array index
      new_path = '.'
    else
      new_path = '.' .. key
    end
  else
    -- Handle array indices differently
    if key:match '^%[%d+%]$' then
      new_path = M.current_path .. key
    else
      new_path = M.current_path .. '.' .. key
    end
  end

  -- Test the path with jq first
  local hybrid = require 'jq-treesitter.hybrid'
  local test_result = hybrid.execute_hybrid_query(new_path .. ' | type', M.source_bufnr)

  if not test_result or test_result:match 'error' then
    -- Path is invalid, revert
    table.remove(M.nav_history)
    vim.notify('Cannot navigate to: ' .. key .. ' (not a valid path)', vim.log.levels.WARN)
    return
  end

  -- Get new content
  local new_content = hybrid.execute_hybrid_query(new_path, M.source_bufnr)

  if new_content then
    M.current_path = new_path
    M.update_float_content(new_content)
  else
    -- Revert if query failed
    table.remove(M.nav_history)
    vim.notify('Failed to navigate to: ' .. key, vim.log.levels.WARN)
  end
end

-- Go back in navigation history
function M.navigate_back()
  if #M.nav_history == 0 then
    vim.notify('No navigation history', vim.log.levels.INFO)
    return
  end

  local prev = table.remove(M.nav_history)
  M.current_path = prev.path
  M.update_float_content(prev.content)
end

-- Update floating window content
function M.update_float_content(content)
  if not M.current_buf or not api.nvim_buf_is_valid(M.current_buf) then
    return
  end

  local nav_lines, key_map = create_nav_content(content, M.current_path)

  api.nvim_buf_set_option(M.current_buf, 'modifiable', true)
  api.nvim_buf_set_lines(M.current_buf, 0, -1, false, nav_lines)
  api.nvim_buf_set_option(M.current_buf, 'modifiable', false)

  -- Store key map for navigation
  vim.b[M.current_buf].jqt_key_map = key_map
end

-- Key handler for navigation
function M.handle_navigation()
  local line = vim.fn.line '.'
  local key_map = vim.b[M.current_buf].jqt_key_map or {}
  local key = key_map[line]

  -- Convert vim.NIL to nil
  if key == vim.NIL then
    key = nil
  end

  -- Debug output
  -- vim.notify('Line: ' .. line .. ', Key: ' .. vim.inspect(key) .. ', KeyMap entries: ' .. vim.inspect(vim.tbl_keys(key_map)), vim.log.levels.INFO)

  if key then
    M.navigate_to_key(key)
  else
    vim.notify('No navigable key on this line (line ' .. line .. ')', vim.log.levels.INFO)
  end
end

-- Create navigable floating window
function M.create_float_window(content, title, source_bufnr)
  local config = require('jq-treesitter').config
  local width = math.floor(vim.o.columns * config.geometry.width)
  local height = math.floor(vim.o.lines * config.geometry.height)

  -- Reset navigation state
  M.nav_history = {}
  M.current_path = ''
  M.source_bufnr = source_bufnr

  -- Create buffer
  M.current_buf = api.nvim_create_buf(false, true)

  -- Create window
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = config.geometry.border,
    title = title and (' ' .. title .. ' ') or nil,
    title_pos = 'center',
  }

  M.float_win = api.nvim_open_win(M.current_buf, true, opts)

  -- Set initial content
  M.update_float_content(content)

  -- Set buffer options
  api.nvim_buf_set_option(M.current_buf, 'filetype', 'json')
  api.nvim_buf_set_option(M.current_buf, 'modifiable', false)

  -- Set up keymaps
  local buf_opts = { noremap = true, silent = true, buffer = M.current_buf }
  vim.keymap.set('n', 'X', M.handle_navigation, buf_opts)
  vim.keymap.set('n', '<C-o>', M.navigate_back, buf_opts)
  vim.keymap.set('n', '<C-p>', function()
    local path = M.current_path == '' and '.' or M.current_path
    vim.fn.setreg('+', path)
    vim.notify('Copied path: ' .. path)
  end, buf_opts)
  vim.keymap.set('n', 'q', ':close<CR>', buf_opts)
  vim.keymap.set('n', '<Esc>', ':close<CR>', buf_opts)

  -- Clean up on window close
  api.nvim_create_autocmd('WinClosed', {
    buffer = M.current_buf,
    once = true,
    callback = function()
      M.nav_history = {}
      M.current_path = ''
      M.current_buf = nil
      M.float_win = nil
      M.source_bufnr = nil
    end,
  })

  return M.float_win
end

return M
