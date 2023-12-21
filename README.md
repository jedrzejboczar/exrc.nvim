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

While `|exrc|` is useful, it is limited to only load the file on Neovim startup and does not fit workflows where
you change current directory at runtime (either manually or by loading a different session) - it assumes that you
will open new Neovim instance. This plugin serves as an alternative to the `|exrc|` option, it implements it's
functionality, extends it and adds several utilities that make it easier to write your `|exrc|` files in Lua.

Features include:

* Configurable name of exrc files (defaults to `.nvim.lua`)
* Auto-detect path to the exrc file that is currently being executed
* Provide `source_up` for loading exrc from directories above
* `:Exrc*` commands for managing exrc files (info, edit, load/unload/reload, ...)
* Automatic telescope integration if available
* Auto-trust exrc files changed from withing Neovim
* Automatically load exrc on `VimEnter`
* Automatically load exrc when changing directory with `:cd`
* Setting up project-local LSP config (even `config.cmd`) when using [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
* Set `on_unload` cleanup hooks called when un-/reloading exrc files
* **TODO:** register variables with UI to modify them and auto-reload exrc

### Similar plugins

* [nvim-config-local](https://github.com/klen/nvim-config-local) unneeded as `vim.secure.trust` is now built into Neovim; does not provide `.nvim.lua` helpers
* [neoconf.nvim](https://github.com/folke/neoconf.nvim) limited config as it uses JSON files not Lua; can only update LSP `config.settings.*`
* [nlsp-settings.nvim](https://github.com/tamago324/nlsp-settings.nvim) like neoconf.nvim

## Installation

Currently requires Neovim nightly.

> Feel free to test it with older versions of Neovim and report issues/create PRs.
> Maybe it would be relatively easy to support some older releases.

Example using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    {
        'jedrzejboczar/exrc.nvim',
        dependencies = {'neovim/nvim-lspconfig'}, -- (optional)
        config = true,
        opts = { --[[ your config ]] } ,
    },
}
```

## Configuration

Run `require('exrc').setup { ... }`.

> If using lazy.nvim as described above just put these options in the `opts` table (or use `config` as a function).

Available options (with default values):
```lua
require('exrc').setup {
    on_dir_changed = true, -- Automatically load exrc files on DirChanged autocmd
    trust_on_write = true, -- Automatically trust when saving exrc file
    use_telescope = true, -- Use telescope instead of vim.ui.select for picking files (if available)
    min_log_level = vim.log.levels.TRACE, -- Disable notifications below this level
    lsp = {
        auto_setup = false, -- Automatically configure lspconfig to register on_new_config
    },
    commands = {
        instant_edit_single = true, -- Do not use vim.ui.select if there is only 1 candidate for ExrcEdit* commands
    },
}
```

> **IMPORTANT!** When you use `on_vim_enter=true` then **do not** lazy-load this plugin.

### Relation to the builtin `exrc` option

`exrc` files were originally meant to run only once at startup, so existing `exrc` files in your projects
may not be written in a way that will work well when loading in other situations (or more than once).
If you feel so, then you might decide to use some other name then the default name `.nvim.lua`
(e.g. `.nvim.local.lua`). If you do so, then this plugin will become orthogonal to the `exrc` option and
there should be no problems with using both.

However, the default for this plugin is to use `.nvim.lua` with the assumption that you are in control of
exrc files and you will adjust them if needed. You can disable the `exrc` option (`:set noexrc`) and let
exrc.nvim handle exrc files (it will set up `VimEnter` and `DirChanged` autocmds for loading the files).
But if you decide to still keep `exrc` enabled then it shouldn't cause problems - the file won't be loaded
twice.

## Usage

Create an exrc file (`.nvim.lua`) in your project directory, e.g. `/my/project/.nvim.lua`
and initialize exrc.nvim Context, then use provided fields/methods, e.g.

```lua
local ctx = require('exrc').init()
local path_to_this_file = ctx.exrc_path

-- to load first exrc from directories above
ctx:source_up()
```

`exrc.nvim` provides some useful commands like `ExrcEdit` or `ExrcInfo`.
Type `:command Exrc` to see all the available commands with descriptions.


### LSP

To set up local LSP configuration you must be using [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) (current limitation).
If not using `lsp.auto_setup = true` then manually configure the `on_setup` hook such that
it sets `on_new_config` hook from exrc.nvim for each of your LSP setups:
```lua
local lsp_util = require('lspconfig.util')
lsp_util.on_setup = lsp_util.add_hook_before(lsp_util.on_setup, function(config, user_config)
    config.on_new_config = lsp_util.add_hook_before(config.on_new_config, require('exrc.lsp').on_new_config)
end)
```
This `on_new_config` hook will check all LSP handlers registered in exrc files and apply
updates from matching handlers whenever LSP client is started.

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

## Examples

### Add .nvim.lua to .gitignore without modifying the repository

You can use `$GIT_DIR/info/exclude` file or configure `core.excludeFiles`,
see [Git documentation](https://git-scm.com/docs/gitignore#_description).
For `$GIT_DIR/info/exclude` this can be symlinked somewhere else.

### How to store .nvim.lua in separate repository?

If you want to track your .nvim.lua in Git in separate repository, use symbolic links, e.g.
```
> tree ./top-dir
./top-dir
├── my-exrc-repo
│   └── my-project.lua
└── my-project
    └── my-project.lua -> ../my-exrc-repo/my-project.lua
```

### Add build tasks with overseer.nvim

Register local tasks for (overseer.nvim)[https://github.com/stevearc/overseer.nvim]:

```lua
local ctx = require('exrc').init()
local overseer = require('overseer')

overseer.register_template {
    name = 'my local task template',
    condition = { dir = ctx.exrc_dir },
    builder = function(params)
        return {
            name = 'my local task',
            cwd = ctx.exrc_dir,
            cmd = 'echo "running task command"',
        }
    end,
}

overseer.register_template {
    name = 'my local complex task template',
    tags = { overseer.TAG.BUILD },
    params = {
        -- ...
    },
    condition = { dir = ctx.exrc_dir },
    builder = function(params)
        local task = {
            name = 'my local complex task',
            cwd = ctx.exrc_dir,
            strategy = {
                'orchestrator',
                tasks = {
                    { 'shell', name = 'stage 1', cmd = 'echo "setting something up in directory $PWD"' },
                    { 'shell', name = 'stage 2', cmd = 'echo "running build process"' },
                },
            },
        }
        return task
    end,
}
```
