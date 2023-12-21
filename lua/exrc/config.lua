local M = {}

local function defaults()
    -- stylua: ignore
    return {
        exrc_name = '.nvim.lua', -- Name of exrc files to use
        on_vim_enter = true, -- Load exrc from current directory on start
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
end

local config = defaults()

-- Keys that cannot be checked automatically because they are nil by default
local nil_keys = {}

local function warn_on_unknown_keys(conf)
    local unknown = {}

    local function traverse(c, ref, state)
        state = state or {
            path = '',
            max_depth = 8,
        }

        if state.max_depth <= 0 then
            return
        end

        for key, val in pairs(c) do
            -- ignore list-like tables
            if type(key) == 'string' then
                if ref == nil or ref[key] == nil then
                    local path = state.path .. key
                    if ref[key] == nil and not nil_keys[path] then
                        table.insert(unknown, path)
                    end
                elseif type(val) == 'table' then
                    traverse(val, ref[key], {
                        path = state.path .. key .. '.',
                        max_depth = state.max_depth - 1,
                    })
                end
            end
        end
    end

    traverse(conf, defaults())

    if #unknown > 0 then
        vim.schedule(function()
            vim.notify(
                'Unknown keys passed to exrc.nvim setup:\n  ' .. table.concat(unknown, '\n  '),
                vim.log.levels.WARN
            )
        end)
    end
end

local function fix_compatibility(opts) end

function M.setup(opts)
    warn_on_unknown_keys(opts)

    fix_compatibility(opts)

    local new_config = vim.tbl_deep_extend('force', {}, defaults(), opts or {})
    -- Do _not_ replace the table pointer with `config = ...` because this
    -- wouldn't change the tables that have already been `require`d by other
    -- modules. Instead, clear all the table keys and then re-add them.
    for _, key in ipairs(vim.tbl_keys(config)) do
        config[key] = nil
    end
    for key, val in pairs(new_config) do
        config[key] = val
    end
end

-- Return the config table (getting completion!) but fall back to module methods.
return setmetatable(config, { __index = M })
