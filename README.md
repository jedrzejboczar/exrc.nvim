[![Lint](https://github.com/jedrzejboczar/exrc.nvim/actions/workflows/lint.yml/badge.svg)](https://github.com/jedrzejboczar/exrc.nvim/actions/workflows/lint.yml)

# exrc.nvim

Plugin that builds on top of Neovim's [|exrc|](https://neovim.io/doc/user/options.html#'exrc') and [vim.secure](https://neovim.io/doc/user/lua.html#vim.secure) by providing convenient utilities to set up project-local configurations.

## Overview

Neovim has a feature called [|exrc|](https://neovim.io/doc/user/options.html#'exrc') that can automatically
load `.nvim.lua`/`.nvimrc`/`.exrc` files when starting the editor, which is great for setting up project-local
configuration. For a long time it was considered a security risk because it could lead to arbitrary code execution
(e.g. malicious `.nvim.lua` in cloned git repo), but with the addition of [vim.secure](https://neovim.io/doc/user/lua.html#vim.secure)
this is no longer the case - Neovim manages a database of "trusted" files and, whenever loading a file which has
been modified since last time, you will be asked if you trust the file before executing any code.

This plugin adds several utilities that make it easier to write your `|exrc|` files in Lua
(**only** `.nvim.lua` files are supported, **not** the Vimscript ones: `.nvimrc`/`.exrc`).
Feature include:

* Auto-detect path to the currently executed exrc (`.nvim.lua`)
* Provide `source_up` for loading exrc from directories above
* `:ExrcEdit*` commands to easily edit exrc files
* `:ExrcLoad` command for (re-)loading exrc files
* Automatic telescope integration if available
* Auto-trust written exrc files
* Automatically load exrc when changing directory
* Setting up project-local LSP config when using [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
* **TODO:** cleanup hooks and reloading of exrc files

## Installation

Currently requires Neovim nightly.

> Feel free to test it with older versions of Neovim and report issues/create PRs.
> Maybe it would be relatively easy to support some older releases.

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

-- to load first exrc from directories above
ctx:source_up()
```

### LSP

To set up local LSP configuration you must be using [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) (current limitation).
Configure the `on_setup` hook such that it sets `on_new_config` hook from exrc.nvim for each of your LSP setups:
```lua
local lsp_util = require('lspconfig.util')
lsp_util.on_setup = lsp_util.add_hook_before(lsp_util.on_setup, function(config, user_config)
    config.on_new_config = lsp_util.add_hook_before(config.on_new_config, require('exrc.lsp').on_new_config)
end)
```
This on_new_config hook will check all LSP handlers registered in exrc files and apply updates from matching handlers
whenever LSP client is started.

Now you can use `lsp_setup` in your exrc files. Here is an example content of `.nvim.lua`:
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
        -- Example of changing LSP command to run in Docker, with volume mounts and clangd path mappings
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
