local M = {}

local config = require('exrc.config')

--- Use as first line of .nvim.lua, e.g. `local ctx = require('exrc').init()`
---@param opts? exrc.InitOpts
---@return exrc.Context
function M.init(opts)
    return require('exrc.context'):new(opts or {})
end

--- Defers require of the module until the command function is called
---@module 'exrc.commands'
local lazy_cmd = setmetatable({}, {
    __index = function(_, key)
        return function(...)
            return require('exrc.commands')[key](...)
        end
    end
})

function M.setup(opts)
    require('exrc.config').setup(opts)

    local command = vim.api.nvim_create_user_command
    command('ExrcEdit', lazy_cmd.exrc_edit, {
        bang = true,
        desc = 'Select exrc file to edit (! discovers more files)',
    })

    command('ExrcEditLoaded', lazy_cmd.exrc_edit_loaded, {
        bang = true,
        desc = 'Select exrc file to edit from already loaded (! for not-loaded)',
    })

    command('ExrcLoad', lazy_cmd.exrc_load, {
        bang = true,
        desc = 'Select and load exrc file (! to include already loaded)',
    })

    command('ExrcCreate', lazy_cmd.exrc_create, {
        desc = 'Select path to create a new .nvim.lua file',
    })

    local group = vim.api.nvim_create_augroup('Exrc', { clear = true })

    if config.on_dir_changed then
        vim.api.nvim_create_autocmd('DirChanged', {
            group = group,
            desc = 'Load exrc files when changing directory',
            callback = function()
                require('exrc.loader').on_dir_changed()
            end,
        })
    end

    if config.trust_on_write then
        vim.api.nvim_create_autocmd('BufWritePost', {
            group = group,
            desc = 'Trust exrc files after write',
            pattern = require('exrc.defs').EXRC_NAME,
            callback = function()
                local ok, err = vim.secure.trust {
                    action = 'allow',
                    bufnr = vim.api.nvim_get_current_buf(),
                }
                if not ok then
                    require('exrc.utils').log.error('Could not trust exrc file: %s', err)
                end
            end,
        })
    end
end

return M
