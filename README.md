# jq-treesitter.nvim

A Neovim plugin for navigating and querying JSON/YAML files using TreeSitter and jq.

## Features

- 🔍 List JSON/YAML keys with `:JqtList`
- 🔎 Query values with jq expressions: `:JqtQuery <expression>`
- 📋 Get JSON path at cursor: `:JqtPath`
- 📊 Convert to markdown table: `:JqtMarkdownTable`
- 🚀 Interactive navigation with `X` key
- ⬆️ Navigate back with `<C-o>`

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'cds-io/jq-treesitter.nvim',
  ft = { 'json', 'yaml' },
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('jq-treesitter').setup()
  end,
}
```

## Requirements

- Neovim 0.9.0+
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with JSON and YAML parsers installed
- `jq` command-line tool (for advanced queries)

## Usage

### Commands

- `:JqtList [type]` - List all top-level keys (optionally filter by type: string, number, boolean, array, object, null)
- `:JqtQuery <jq-expression>` - Execute a jq query on the current buffer
- `:JqtPath` - Copy the JSON path at cursor to clipboard
- `:JqtMarkdownTable` - Convert the surrounding JSON array to a markdown table

### Key Mappings

In JSON/YAML files:
- `<leader>jcp` - Copy JSON path at cursor
- `<leader>jmt` - Convert to markdown table

In quickfix window (after `:JqtList`):
- `X` - Query the value of the key under cursor

When navigating JSON structure:
- `X` - Drill down into object/array
- `<C-o>` - Go back to previous level
- `<C-p>` - Copy current path

### Navigation Motions

- `]j` - Go to next navigable JSON item
- `[j` - Go to previous navigable JSON item

## Configuration

```lua
require('jq-treesitter').setup({
  geometry = {
    border = 'single',    -- Border style for floating windows
    width = 0.7,          -- Width as percentage of screen
    height = 0.5,         -- Height as percentage of screen
  },
  query_key = 'X',        -- Key to query values in quickfix
  sort = false,           -- Sort keys alphabetically
  show_legend = true,     -- Show navigation legend
  use_quickfix = false,   -- Use quickfix instead of location list
})
```

## License

MIT
