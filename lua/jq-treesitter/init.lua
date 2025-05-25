local M = {}
local api = vim.api

M.config = {
  geometry = {
    border = 'single',
    width = 0.7,
    height = 0.5,
  },
  query_key = 'X',
  sort = false,
  show_legend = true,
  use_quickfix = false,
}

local function get_json_parser(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok then
    vim.notify('Treesitter not found', vim.log.levels.ERROR)
    return nil
  end
  
  local lang = parsers.get_buf_lang(bufnr)
  if lang ~= 'json' and lang ~= 'yaml' then
    vim.notify('Buffer is not JSON or YAML', vim.log.levels.ERROR)
    return nil
  end
  
  return parsers.get_parser(bufnr), lang
end

function M.extract_json_keys(bufnr)
  local parser, lang = get_json_parser(bufnr)
  if not parser then return {} end
  
  local tree = parser:parse()[1]
  local root = tree:root()
  
  local keys = {}
  
  local query_string
  if lang == 'json' then
    query_string = [[
      (object
        (pair
          key: (string (string_content) @key)
          value: (_) @value
        ) @pair
      )
    ]]
  else -- yaml
    query_string = [[
      (block_mapping_pair
        key: (flow_node) @key
        value: (_) @value
      ) @pair
    ]]
  end
  
  local query = vim.treesitter.query.parse(lang, query_string)
  
  for id, node, metadata in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == 'key' then
      local key_text = vim.treesitter.get_node_text(node, bufnr)
      
      -- Find the pair node and check if it's at the top level
      local pair_node = node:parent():parent() -- string -> pair
      local object_node = pair_node and pair_node:parent() -- pair -> object
      
      -- Check if this object is the root or a direct child of root
      local is_top_level = false
      if object_node then
        if object_node == root then
          is_top_level = true
        elseif object_node:parent() == root then
          is_top_level = true
        end
      end
      
      if is_top_level then
        local row, col = node:start()
        table.insert(keys, {
          key = key_text,
          line = row + 1,
          col = col + 1,
          node = node,
        })
      end
    end
  end
  
  if M.config.sort then
    table.sort(keys, function(a, b) return a.key < b.key end)
  end
  
  return keys
end

local function populate_quickfix(keys, bufnr)
  local qf_list = {}
  local filename = api.nvim_buf_get_name(bufnr)
  
  for _, item in ipairs(keys) do
    -- Remove quotes from key for display
    local display_key = item.key:gsub('^"', ''):gsub('"$', '')
    table.insert(qf_list, {
      filename = filename,
      lnum = item.line,
      col = item.col,
      text = display_key,
    })
  end
  
  if M.config.use_quickfix then
    vim.fn.setqflist(qf_list)
    vim.cmd('copen')
  else
    vim.fn.setloclist(0, qf_list)
    vim.cmd('lopen')
  end
end

local function get_node_value(node, bufnr)
  local parser, lang = get_json_parser(bufnr)
  if not parser then return nil end
  
  local query_string
  if lang == 'json' then
    query_string = [[
      (pair
        key: (string (string_content) @key)
        value: (_) @value
      )
    ]]
  else
    query_string = [[
      (block_mapping_pair
        key: (flow_node) @key
        value: (_) @value
      )
    ]]
  end
  
  local query = vim.treesitter.query.parse(lang, query_string)
  local parent = node:parent():parent()
  
  for id, capture_node, metadata in query:iter_captures(parent, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == 'value' and capture_node:parent():child(0) == node:parent() then
      return vim.treesitter.get_node_text(capture_node, bufnr)
    end
  end
  
  return nil
end

local function show_floating_window(content, title, source_bufnr)
  -- Use the new navigator for interactive exploration
  local navigator = require('jq-treesitter.navigator')
  return navigator.create_float_window(content, title, source_bufnr or api.nvim_get_current_buf())
end

function M.list_keys(filter_type)
  local bufnr = api.nvim_get_current_buf()
  local keys = M.extract_json_keys(bufnr)
  
  if filter_type then
    local filtered = {}
    for _, item in ipairs(keys) do
      local value = get_node_value(item.node, bufnr)
      if value then
        local val_type = 'unknown'
        if value:match('^%d+%.?%d*$') then
          val_type = 'number'
        elseif value == 'true' or value == 'false' then
          val_type = 'boolean'
        elseif value:match('^".*"$') or value:match("^'.*'$") then
          val_type = 'string'
        elseif value:match('^%[') then
          val_type = 'array'
        elseif value:match('^{') then
          val_type = 'object'
        elseif value == 'null' then
          val_type = 'null'
        end
        
        if val_type == filter_type then
          table.insert(filtered, item)
        end
      end
    end
    keys = filtered
  end
  
  populate_quickfix(keys, bufnr)
end

function M.query_key()
  local line = vim.fn.getline('.')
  
  -- Extract the key from quickfix format: "filename|line col col| key"
  -- Match everything after the last "|" and trim whitespace
  local key = line:match('|%s*([^|]+)%s*$')
  if not key then
    -- Try simple format if no pipe found
    key = line:match('^%s*(.+)%s*$')
  end
  
  if not key then
    vim.notify('No key found on current line', vim.log.levels.WARN)
    return
  end
  
  -- Clean up the key - remove any remaining whitespace
  key = vim.trim(key)
  
  -- Debug output to see what we extracted
  -- vim.notify('Extracted key: "' .. key .. '"', vim.log.levels.INFO)
  
  -- Get the original buffer number (before quickfix was opened)
  local orig_win = nil
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local ft = api.nvim_buf_get_option(buf, 'filetype')
    if ft == 'json' or ft == 'yaml' then
      orig_win = win
      break
    end
  end
  
  if not orig_win then
    vim.notify('No JSON/YAML buffer found', vim.log.levels.WARN)
    return
  end
  
  local bufnr = api.nvim_win_get_buf(orig_win)
  local parser, lang = get_json_parser(bufnr)
  if not parser then return end
  
  local keys = M.extract_json_keys(bufnr)
  for _, item in ipairs(keys) do
    -- Clean the stored key for comparison
    local clean_key = item.key:gsub('^"', ''):gsub('"$', '')
    if clean_key == key or item.key == key or item.key == '"' .. key .. '"' then
      local value = get_node_value(item.node, bufnr)
      if value then
        -- Show in floating window without switching buffers
        show_floating_window(value, key, bufnr)
        return
      end
    end
  end
  
  vim.notify('Key not found: ' .. key, vim.log.levels.WARN)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  
  -- Load debug commands
  require('jq-treesitter.debug')
  
  vim.api.nvim_create_user_command('JqtList', function(args)
    M.list_keys(args.args ~= '' and args.args or nil)
  end, {
    nargs = '?',
    complete = function()
      return { 'string', 'number', 'boolean', 'array', 'object', 'null' }
    end,
  })
  
  vim.api.nvim_create_user_command('JqtQuery', function(args)
    if args.args == '' then
      vim.notify('Usage: JqtQuery <jq-expression>', vim.log.levels.ERROR)
      return
    end
    
    local hybrid = require('jq-treesitter.hybrid')
    local result = hybrid.execute_hybrid_query(args.args)
    
    if result then
      show_floating_window(result, 'Query: ' .. args.args, vim.api.nvim_get_current_buf())
    else
      vim.notify('No results for query: ' .. args.args, vim.log.levels.WARN)
    end
  end, { nargs = '*' })
  
  -- Add command to get JSON path at cursor
  vim.api.nvim_create_user_command('JqtPath', function()
    local hybrid = require('jq-treesitter.hybrid')
    local path = hybrid.get_path_to_cursor(vim.api.nvim_get_current_buf())
    if path then
      vim.notify('Path: ' .. path)
      vim.fn.setreg('+', path)
    else
      vim.notify('Could not determine path at cursor', vim.log.levels.WARN)
    end
  end, {})
  
  -- Add command to copy surrounding object as markdown table
  vim.api.nvim_create_user_command('JqtMarkdownTable', function()
    local markdown = require('jq-treesitter.markdown')
    markdown.copy_as_markdown_table()
  end, {})
  
  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'qf' },
    callback = function()
      vim.keymap.set('n', M.config.query_key, M.query_key, { 
        buffer = true, 
        desc = 'Query JSON key value' 
      })
    end,
  })
  
  -- Add keymap for JSON/YAML files
  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'json', 'yaml' },
    callback = function(ev)
      vim.keymap.set('n', '<leader>jcp', '<cmd>JqtPath<cr>', {
        buffer = true,
        desc = '[J]son [C]opy [P]ath'
      })
      vim.keymap.set('n', '<leader>jmt', '<cmd>JqtMarkdownTable<cr>', {
        buffer = true,
        desc = '[J]son [M]arkdown [T]able'
      })
      
      -- Enable treesitter-based navigation
      local nav = require('jq-treesitter.treesitter-nav')
      nav.setup(ev.buf)
    end,
  })
end

return M