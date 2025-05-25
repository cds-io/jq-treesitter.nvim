-- Treesitter-based navigation for JSON
local M = {}
local api = vim.api
local ts = vim.treesitter

M.ns_id = api.nvim_create_namespace 'jq_treesitter_nav'
M.current_path = '.'
M.original_content = ''
M.navigation_stack = {}

-- Parse JSON structure using treesitter
function M.parse_json_structure(bufnr)
  local parser = ts.get_parser(bufnr, 'json')
  local tree = parser:parse()[1]
  local root = tree:root()

  -- Data structure to hold navigable items
  local structure = {
    type = nil, -- 'object', 'array', or 'value'
    navigable_items = {}, -- List of {line, key, path, type}
  }

  -- Helper to get node text
  local function get_node_text(node)
    return vim.treesitter.get_node_text(node, bufnr)
  end

  -- Determine root type - handle 'document' node
  local content_node = root
  if root:type() == 'document' and root:child_count() > 0 then
    content_node = root:child(0)
  end

  local node_type = content_node:type()
  if node_type == 'object' then
    structure.type = 'object'
    M.parse_object(content_node, bufnr, structure.navigable_items)
  elseif node_type == 'array' then
    structure.type = 'array'
    M.parse_array(content_node, bufnr, structure.navigable_items)
  else
    structure.type = 'value'
  end

  return structure
end

-- Parse object node
function M.parse_object(node, bufnr, items)
  for pair in node:iter_children() do
    if pair:type() == 'pair' then
      local key_node = pair:field('key')[1]
      local value_node = pair:field('value')[1]

      if key_node and value_node then
        local key = vim.treesitter.get_node_text(key_node, bufnr):gsub('^"', ''):gsub('"$', '')
        local value_type = value_node:type()
        local line = key_node:start() + 1

        -- Only add navigable items (objects and arrays)
        if value_type == 'object' or value_type == 'array' then
          table.insert(items, {
            line = line,
            key = key,
            value_type = value_type,
            value_node = value_node,
          })
        end
      end
    end
  end
end

-- Parse array node
function M.parse_array(node, bufnr, items)
  local index = 0
  for child in node:iter_children() do
    if child:type() == 'object' or child:type() == 'array' then
      local line = child:start() + 1
      table.insert(items, {
        line = line,
        key = tostring(index),
        value_type = child:type(),
        value_node = child,
        is_array_element = true,
      })
      index = index + 1
    elseif child:type() ~= ',' and child:type() ~= '[' and child:type() ~= ']' then
      -- Count other value types too
      index = index + 1
    end
  end
end

-- Update visual markers
function M.update_markers(bufnr)
  -- Clear existing marks
  api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1)

  -- Parse structure first to know what we're dealing with
  local structure = M.parse_json_structure(bufnr)

  -- Add path indicator when not at root (as end-of-line virtual text)
  if M.current_path ~= '.' then
    local path_text = 'Path: ' .. M.current_path .. ' | <C-o>=back'
    if structure.type == 'array' then
      path_text = path_text .. ' | X=navigate'
    end

    -- Put breadcrumb at end of first line to avoid collisions
    api.nvim_buf_set_extmark(bufnr, M.ns_id, 0, 0, {
      virt_text = { { ' 📍 ' .. path_text, 'Comment' } },
      virt_text_pos = 'eol',
      priority = 100, -- High priority to ensure it shows
    })
  end

  if structure.type == 'object' then
    -- Add markers for object keys
    for _, item in ipairs(structure.navigable_items) do
      local marker_text = item.value_type == 'object' and ' {}' or ' []'
      api.nvim_buf_set_extmark(bufnr, M.ns_id, item.line - 1, 0, {
        virt_text = { { ' → [' .. item.key .. marker_text .. ']', 'Comment' } },
        virt_text_pos = 'eol',
      })
    end
  elseif structure.type == 'array' then
    -- Add markers for array elements (no separate hint needed - it's in the path)
    for _, item in ipairs(structure.navigable_items) do
      if item.is_array_element then
        local element_text = item.value_type == 'object' and '[{}]' or '[array]'
        api.nvim_buf_set_extmark(bufnr, M.ns_id, item.line - 1, 0, {
          virt_text = { { ' → ' .. element_text .. ' [' .. item.key .. ']', 'Special' } },
          virt_text_pos = 'eol',
        })
      end
    end
  end

  return structure
end

-- Find which array element contains the cursor
function M.find_array_element_at_cursor(bufnr, cursor_line, structure)
  for _, item in ipairs(structure.navigable_items) do
    if item.is_array_element and item.value_node then
      local start_line = item.value_node:start() + 1
      local end_line = item.value_node:end_() + 1

      if cursor_line >= start_line and cursor_line <= end_line then
        return item
      end
    end
  end
  return nil
end

-- Navigate to item at cursor
function M.navigate_at_cursor(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Get current structure
  local structure = M.parse_json_structure(bufnr)

  if structure.type == 'array' then
    -- Handle array element navigation
    local element = M.find_array_element_at_cursor(bufnr, line, structure)
    if element then
      local new_path = M.current_path .. '[' .. element.key .. ']'
      M.navigate_to_path(bufnr, new_path)
      return
    end
  elseif structure.type == 'object' then
    -- Find navigable item on this line
    for _, item in ipairs(structure.navigable_items) do
      if item.line == line then
        local new_path
        if M.current_path == '.' then
          new_path = '.' .. item.key
        else
          new_path = M.current_path .. '.' .. item.key
        end
        M.navigate_to_path(bufnr, new_path)
        return
      end
    end
  end

  vim.notify('No navigable item at cursor', vim.log.levels.INFO)
end

-- Navigate to a specific path
function M.navigate_to_path(bufnr, new_path)
  -- Save current state
  local content = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  table.insert(M.navigation_stack, {
    path = M.current_path,
    content = content,
  })

  -- Get content at new path
  local temp_file = vim.fn.tempname() .. '.json'
  vim.fn.writefile(vim.split(M.original_content, '\n'), temp_file)

  local cmd = string.format('cat %s | jq %s 2>&1', vim.fn.shellescape(temp_file), vim.fn.shellescape(new_path))
  local handle = io.popen(cmd)
  local new_content = handle:read '*a'
  local success = handle:close()

  os.remove(temp_file)

  if new_content and not new_content:match 'error' and success then
    M.current_path = new_path

    -- Update buffer
    api.nvim_buf_set_option(bufnr, 'modifiable', true)
    api.nvim_buf_set_option(bufnr, 'modified', false)
    local new_lines = vim.split(new_content, '\n')
    api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    api.nvim_buf_set_option(bufnr, 'modified', false)
    api.nvim_buf_set_option(bufnr, 'modifiable', true)

    -- Update display with proper timing
    vim.schedule(function()
      -- Force treesitter reparse
      local parser = ts.get_parser(bufnr, 'json')
      parser:parse()

      -- Update markers
      M.update_markers(bufnr)

      -- Force redraw to ensure virtual text is visible
      vim.cmd 'redraw'

      -- Re-setup other features
      local motions = require 'jq-treesitter.motions'
      local textobjects = require 'jq-treesitter.textobjects'
      motions.setup_motions(bufnr)
      textobjects.setup_textobjects(bufnr)
    end)

    api.nvim_win_set_cursor(0, { 1, 0 })
  else
    table.remove(M.navigation_stack)
    vim.notify('Failed to navigate to ' .. new_path, vim.log.levels.WARN)
  end
end

-- Go back in navigation
function M.go_back(bufnr)
  if #M.navigation_stack == 0 then
    vim.notify('Already at root', vim.log.levels.INFO)
    return
  end

  local prev = table.remove(M.navigation_stack)
  M.current_path = prev.path

  -- Restore content
  api.nvim_buf_set_option(bufnr, 'modifiable', true)
  api.nvim_buf_set_option(bufnr, 'modified', false)
  local lines = vim.split(prev.content, '\n')
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  api.nvim_buf_set_option(bufnr, 'modified', false)
  api.nvim_buf_set_option(bufnr, 'modifiable', true)

  vim.schedule(function()
    M.update_markers(bufnr)
    local motions = require 'custom.plugins.jq-treesitter.motions'
    local textobjects = require 'custom.plugins.jq-treesitter.textobjects'
    motions.setup_motions(bufnr)
    textobjects.setup_textobjects(bufnr)
  end)
end

-- Setup for buffer
function M.setup(bufnr)
  -- Store original content
  M.original_content = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  M.current_path = '.'
  M.navigation_stack = {}

  -- Ensure highlight groups exist
  vim.cmd [[
    highlight default link JqTreesitterMarker Special
    highlight default link JqTreesitterPath Comment
  ]]

  -- Initial setup with a slight delay to ensure buffer is ready
  vim.schedule(function()
    M.update_markers(bufnr)
  end)

  -- Set up keymaps
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', 'X', function()
    M.navigate_at_cursor(bufnr)
  end, opts)
  vim.keymap.set('n', '<C-o>', function()
    M.go_back(bufnr)
  end, opts)
end

-- Debug function to test virtual text
function M.test_virtual_text()
  local bufnr = api.nvim_get_current_buf()
  local ns_test = api.nvim_create_namespace 'test_virtual_text'

  -- Clear any existing marks
  api.nvim_buf_clear_namespace(bufnr, ns_test, 0, -1)

  -- Try multiple virtual text styles
  vim.notify 'Testing virtual text...'

  -- Test 1: EOL virtual text
  local id1 = api.nvim_buf_set_extmark(bufnr, ns_test, 0, 0, {
    virt_text = { { 'EOL TEST', 'Error' } },
    virt_text_pos = 'eol',
  })

  -- Test 2: Overlay virtual text
  local id2 = api.nvim_buf_set_extmark(bufnr, ns_test, 1, 0, {
    virt_text = { { 'OVERLAY TEST', 'WarningMsg' } },
    virt_text_pos = 'overlay',
  })

  -- Test 3: Right aligned
  local id3 = api.nvim_buf_set_extmark(bufnr, ns_test, 2, 0, {
    virt_text = { { 'RIGHT TEST', 'Question' } },
    virt_text_pos = 'right_align',
  })

  -- Test 4: Virtual lines
  local id4 = api.nvim_buf_set_extmark(bufnr, ns_test, 3, 0, {
    virt_lines = {
      { { 'VIRTUAL LINE TEST', 'Title' } },
    },
    virt_lines_above = false,
  })

  vim.notify(string.format('Created marks: %d, %d, %d, %d', id1, id2, id3, id4))

  -- Check conceallevel
  vim.notify('conceallevel = ' .. vim.wo.conceallevel)

  -- Check if virtual text is enabled
  local virt_text_enabled = vim.api.nvim_get_option_value('virtualedit', { win = 0 })
  vim.notify('virtualedit = ' .. virt_text_enabled)

  -- List all namespaces
  local our_marks = api.nvim_buf_get_extmarks(bufnr, M.ns_id, 0, -1, { details = true })
  vim.notify('Found ' .. #our_marks .. ' navigation marks in namespace ' .. M.ns_id)
end

-- Create user command for testing
vim.api.nvim_create_user_command('JqtTestVirtualText', M.test_virtual_text, {})

-- Minimal test that should definitely work
vim.api.nvim_create_user_command('JqtMinimalTest', function()
  local bufnr = api.nvim_get_current_buf()
  local ns = api.nvim_create_namespace 'minimal_test'

  -- Clear and add one simple marker
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local id = api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
    virt_text = { { 'MINIMAL TEST', 'Error' } },
    virt_text_pos = 'eol',
  })

  vim.notify('Created minimal test mark with ID: ' .. id)
end, {})

-- Command to inspect extmarks on current line
vim.api.nvim_create_user_command('JqtInspectLine', function()
  local bufnr = api.nvim_get_current_buf()
  local line = api.nvim_win_get_cursor(0)[1] - 1
  local all_ns = api.nvim_get_namespaces()

  vim.notify('Inspecting line ' .. (line + 1))

  for name, ns_id in pairs(all_ns) do
    local marks = api.nvim_buf_get_extmarks(bufnr, ns_id, { line, 0 }, { line, -1 }, { details = true })
    if #marks > 0 then
      vim.notify(string.format("Namespace '%s' (id=%d): %d marks", name, ns_id, #marks))
      for _, mark in ipairs(marks) do
        if mark[4].virt_text then
          local text = ''
          for _, part in ipairs(mark[4].virt_text) do
            text = text .. part[1]
          end
          vim.notify('  Virtual text: ' .. text)
        end
      end
    end
  end
end, {})

return M
