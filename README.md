# exrc.nvim

Plugin that builds on top of Neovim's [|exrc|](https://neovim.io/doc/user/options.html#'exrc') and [vim.secure](https://neovim.io/doc/user/lua.html#vim.secure) by providing convenient utilities to set up project-local configurations.

## Overview

Neovim has a feature called [|exrc|](https://neovim.io/doc/user/options.html#'exrc') that can automatically
load `.nvim.lua`/`.nvimrc`/`.exrc` files when starting the editor. This was considered a security risk because
it could lead to arbitrary code execution (e.g. malicious `.nvim.lua` in cloned git repo), but with the addition
of [vim.secure](https://neovim.io/doc/user/lua.html#vim.secure) this is no longer the case. Neovim manages a database
of "trusted" files, whenever loading a file it will ask you if you trust the file before executing any code.

This plugin adds several utilities that make it easier to write your `|exrc|` files in Lua
(**only** `.nvim.lua` files are supported, **not** the Vimscript ones: `.nvimrc`/`.exrc`).
Feature include:

* Auto-detect path to the currently executed exrc (`.nvim.lua`)
* Provide `source_up` for loading exrc from directories above
* `ExrcEdit` command to easily edit exrc files
* Auto-trust written exrc files
* Automatically load exrc when changing directory
* Setting up project-local LSP config when using [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
* **TODO:** cleanup hooks and reloading of exrc files

## Installation

Example using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    { 'jedrzejboczar/exrc.nvim', config = true, opts = { --[[ your config ]] } },
}
```

## Configuration

Run `require('exrc').setup { ... }`.

> If using lazy.nvim as described above just put these options in the `opts` table (or use `config` as a function).

Available options (with default values):
```lua
require('exrc').setup {
    on_dir_changed = true, -- create DirChanged autocmd that loads exrc file from new directory
    trust_on_write = true, -- create BufWritePost autocmd to trust saved exrc files
}
```

## Usage

Create an exrc file (`.nvim.lua`) in your project directory, e.g. `/my/project/.nvim.lua`
and initialize exrc.nvim Context, then use provided fields/methods, e.g.

```lua
local ctx = require('exrc').init()
local path_to_this_file = ctx.exrc_path
```

### LSP

To set up local LSP configuration use e.g.
```lua
local ctx = require('exrc').init()
-- Pass a table with keys being LSP client names. Handlers will be executed only
-- for given client when root_dir matches (root_dir=exrc_dir or is below exrc_dir).
-- Modify config table in-place.
ctx:lsp_setup {
    lua_ls = function(config, root_dir)
        -- Example of changing lua_ls settings
        config.settings = vim.tbl_deep_extend('force', config.settings, {
            Lua = {
                diagnostics = {
                    globals = { "vim" },
                    unusedLocalExclude = { '_*' },
                }
            }
        }
    end,
    clangd = function(config, root_dir)
        -- Example of changing LSP command to run in Docker
        local host_dir = vim.fs.dirname(ctx.exrc_path)
        config.cmd = {
            'docker', 'run',
            '--interactive',
            '--rm',
            '--user', 'root',
            '--volume', string.format('%s/.config/clangd:/root/.config/clangd', vim.env.HOME),
            '--volume', string.format('%s:%s', host_dir, '/root/workdir'),
            '--workdir', '/root/workdir',
            'my_clangd_docker_image',
            -- command to run in container
            'clangd',
            '--clang-tidy',
            '--background-index',
            '--compile-commands-dir=/root/workdir/build',
            '--query-driver=/usr/bin/arm-none-eabi-*', -- ARM bare metal toolchain
            -- clangd path mappings to translate between paths on host and in container
            string.format('--path-mappings=%s=%s', host_dir, '/root/workdir'),
        }
    end,
}
```
