-- Tests for jq-treesitter plugin
local M = {}

-- Helper to create a test buffer with JSON content
local function create_test_buffer(content)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, '\n'))
  vim.api.nvim_buf_set_option(buf, 'filetype', 'json')
  return buf
end

-- Test runner
function M.run_tests()
  print 'Running jq-treesitter tests...'

  -- Load test data
  local test_file = vim.fn.stdpath 'config' .. '/lua/jq-treesitter/test-data.json'
  local file = io.open(test_file, 'r')
  if not file then
    print '❌ Could not open test file'
    return
  end

  local content = file:read '*all'
  file:close()

  local buf = create_test_buffer(content)
  vim.api.nvim_set_current_buf(buf)

  -- Test 1: Extract JSON keys
  print '\nTest 1: Extract JSON keys'
  local init = require 'jq-treesitter'
  local keys = init.extract_json_keys(buf)

  if #keys == 1 and keys[1].key == 'abi' then
    print('✅ Successfully extracted root key: ' .. keys[1].key)
  else
    print '❌ Failed to extract keys'
  end

  -- Test 2: Hybrid query - simple path
  print '\nTest 2: Hybrid query - simple path'
  local hybrid = require 'jq-treesitter.hybrid'
  local result = hybrid.execute_hybrid_query('.abi', buf)

  if result and result:match 'modifyAllocations' then
    print '✅ Successfully queried .abi path'
  else
    print '❌ Failed to query .abi path'
  end

  -- Test 3: JQ query with filter
  print '\nTest 3: JQ query with filter'
  local filtered = hybrid.execute_hybrid_query('.abi[] | {name, type}', buf)

  if filtered and filtered:match '"name"' and filtered:match '"type"' then
    print '✅ Successfully filtered with jq expression'
  else
    print '❌ Failed to filter with jq expression'
  end

  -- Test 4: Path extraction
  print '\nTest 4: Path extraction'
  -- Move cursor to "modifyAllocations"
  vim.api.nvim_win_set_cursor(0, { 5, 15 }) -- Line 5, column 15
  local path = hybrid.get_path_to_cursor(buf)

  if path then
    print('✅ Path at cursor: ' .. path)
  else
    print '❌ Failed to get path at cursor'
  end

  -- Test 5: Markdown table conversion
  print '\nTest 5: Markdown table conversion'
  local markdown = require 'jq-treesitter.markdown'

  -- Move cursor inside the abi array
  vim.api.nvim_win_set_cursor(0, { 2, 2 })
  local node = markdown.find_surrounding_object(buf)

  if node and node:type() == 'array' then
    print '✅ Found surrounding array node'

    -- Extract array data
    local headers, rows = markdown.extract_array_data(node, buf)
    if headers and #headers > 0 then
      print('✅ Extracted headers: ' .. table.concat(headers, ', '))
      print('✅ Found ' .. #rows .. ' rows')

      -- Convert to markdown
      local md_table = markdown.array_to_markdown_table(headers, rows)
      if md_table and md_table ~= '' then
        print '✅ Successfully converted to markdown table'
        print '\nMarkdown table preview:'
        local lines = vim.split(md_table, '\n')
        for i = 1, math.min(5, #lines) do
          print(lines[i])
        end
        if #lines > 5 then
          print('... (' .. (#lines - 5) .. ' more lines)')
        end
      end
    else
      print '❌ Failed to extract array data'
    end
  else
    print '❌ Failed to find surrounding array'
  end

  -- Test 6: Complex nested query
  print '\nTest 6: Complex nested query'
  local nested = hybrid.execute_hybrid_query('.abi[0].inputs[0]', buf)

  if nested and nested:match 'operator' then
    print '✅ Successfully queried nested path'
  else
    print '❌ Failed to query nested path'
  end

  -- Clean up
  vim.api.nvim_buf_delete(buf, { force = true })
  print '\n✅ All tests completed!'
end

-- Command to run tests
vim.api.nvim_create_user_command('JqtRunTests', function()
  M.run_tests()
end, {})

return M
