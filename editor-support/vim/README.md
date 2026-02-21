# Vim / Neovim Support for Compact

Compact language support for Vim and Neovim is provided via a community-driven standalone plugin:

**[1NickPappas/compact.vim](https://github.com/1NickPappas/compact.vim)**

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{ "1NickPappas/compact.vim", ft = "compact" }
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug '1NickPappas/compact.vim'
```

### Native Package Manager (Vim 8+ / Neovim)

```bash
git clone https://github.com/1NickPappas/compact.vim \
    ~/.local/share/nvim/site/pack/plugins/start/compact.vim
```

## Features

- Syntax highlighting (regex-based for Vim, tree-sitter for Neovim)
- Filetype detection for `.compact` files
- Smart indentation
- Code folding
- Comment support (`//` and `/* */`)
- Text objects (requires [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects))
- Import navigation via `gf`
- Compiler integration via `:make`
- Local scoping (variable references scoped per circuit/block)