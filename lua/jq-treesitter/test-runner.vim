" Test runner for jq-treesitter plugin
" Run this file with :source % after opening Neovim

echo "Testing jq-treesitter plugin with ABI JSON..."

" Open the test JSON file
edit lua/custom/plugins/jq-treesitter/test-data.json

" Test 1: List keys
echo "\n1. Testing :JqtList command..."
JqtList
sleep 500m

" Close quickfix window and go back to JSON buffer
cclose
wincmd p

" Test 2: Query simple path  
echo "\n2. Testing :JqtQuery .abi"
JqtQuery .abi
sleep 1

" Close floating window
normal q

" Test 3: Complex query
echo "\n3. Testing :JqtQuery .abi[] | {name, type}"
JqtQuery .abi[] | {name, type}
sleep 1

" Close floating window  
normal q

" Test 4: Path at cursor
echo "\n4. Testing :JqtPath"
" Move to line with "modifyAllocations"
normal 5G15|
JqtPath
sleep 500m

" Test 5: Markdown table
echo "\n5. Testing :JqtMarkdownTable"
" Move inside the abi array
normal 3G
JqtMarkdownTable
sleep 500m

echo "\nTests completed! Check clipboard for markdown table."
echo "Run :JqtRunTests for automated tests."
