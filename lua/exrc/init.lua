local M = {}

--- Use as first line of .nvim.lua, e.g. `local ctx = require('exrc').init()`
---@param opts? exrc.InitOpts
---@return exrc.Context
function M.init(opts)
    return require('exrc.context'):new(opts or {})
end

local function exrc_edit_cmd(opts)
    local loader = require('exrc.loader')
    local utils = require('exrc.utils')

    local found = {}
    local function add_from(cwd)
        local files = vim.fs.find(loader.EXRC_NAME, {
            upward = true,
            type = 'file',
            path = cwd,
        })
        if files then
            vim.list_extend(found, files)
        end
    end

    local cwd = vim.fn.getcwd()
    add_from(cwd)
    if opts.bang then
        add_from(vim.fn.getcwd(-1)) -- tab cwd
        add_from(vim.fn.getcwd(-1, -1)) -- global cwd
        vim.list_extend(found, loader.loaded.history)
    end

    -- remove duplicates
    found = vim.tbl_keys(utils.list_to_set(found))
    table.sort(found)

    if #found > 0 then
        if #found == 1 then
            vim.cmd.edit(found[1])
        else
            vim.ui.select(found, { prompt = 'Select exrc file to edit:' }, function(item)
                vim.cmd.edit(item)
            end)
        end
    else
        utils.log.error('No exrc files found at "%s"', cwd)
    end
end

---@class exrc.SetupOpts
---@field on_dir_changed? boolean Automatically load exrc files on DirChanged autocmd
---@field trust_on_write? boolean Automatically trust when saving exrc file

---@param opts exrc.SetupOpts
function M.setup(opts)
    opts = vim.tbl_extend('force', {
        on_dir_changed = true,
        trust_on_write = true,
    }, opts or {})

    vim.api.nvim_create_user_command('ExrcEdit', exrc_edit_cmd, {
        bang = true,
        desc = 'Edit exrc file from cwd (with ! also considers all loaded files)',
    })

    local group = vim.api.nvim_create_augroup('Exrc', { clear = true })

    if opts.on_dir_changed then
        vim.api.nvim_create_autocmd('DirChanged', {
            group = group,
            desc = 'Load exrc files when changing directory',
            callback = function()
                require('exrc.loader').on_dir_changed()
            end,
        })
    end

    if opts.trust_on_write then
        vim.api.nvim_create_autocmd('BufWritePost', {
            group = group,
            desc = 'Trust exrc files after write',
            pattern = require('exrc.loader').EXRC_NAME,
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
