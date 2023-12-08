local M = {}

local config = require('exrc.config')
local loader = require('exrc.loader')

local function select_files(files, prompt, on_choice)
    local use_telescope = config.use_telescope and pcall(require, 'telescope')
    if not use_telescope then
        local ui_opts = {
            prompt = prompt,
            format_item = function(file)
                return string.format('%s (%sloaded)', file, loader.is_loaded(file) and '' or 'not ')
            end
        }
        vim.ui.select(files, ui_opts, on_choice)
    else
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local finders = require('telescope.finders')
        local make_entry = require('telescope.make_entry')
        local pickers = require('telescope.pickers')
        local tele_conf = require('telescope.config').values

        local gen_from_file = make_entry.gen_from_file()
        local first = true
        local patch_mt = function(mt)
            -- display with `(loaded)`/`(not loaded)`
            local display = mt.display
            mt.display = function(entry)
                local text, highlights = display(entry)
                highlights = highlights or {}
                local loaded_str = string.format('(%sloaded)', loader.is_loaded(entry.value) and '' or 'not ')
                table.insert(highlights, { { #text + 1, #text + 1 + #loaded_str }, 'TelescopeResultsVariable' })
                text = text .. ' ' .. loaded_str
                return text, highlights
            end
        end

        pickers.new({}, {
            prompt_title = prompt,
            finder = finders.new_table {
                results = files,
                entry_maker = function(file)
                    local entry = gen_from_file(file)
                    if first then
                        patch_mt( getmetatable(entry))
                        first = false
                    end
                    return entry
                end,
            },
            previewer = tele_conf.file_previewer({}),
            sorter = tele_conf.file_sorter({}),
            attach_mappings = function()
                actions.select_default:replace(function(buf)
                    local entry = action_state.get_selected_entry()
                    actions.close(buf)
                    on_choice(entry.value)
                end)
                return true
            end
        }):find()
    end
end

---@param opts? { is_loaded?: boolean, buf_paths?: boolean }
---@return string[]
local function exrc_list(opts)
    local defs = require('exrc.defs')
    local loader = require('exrc.loader')

    opts = opts or {}

    local files = {}
    local checked = {}
    local function add_upward_from(cwd)
        if checked[cwd] then
            return
        end
        local found = vim.fs.find(defs.EXRC_NAME, {
            upward = true,
            type = 'file',
            path = cwd,
        })
        if found then
            vim.list_extend(files, found)
        end
        checked[cwd] = true
    end

    local cwd = vim.fn.getcwd()
    add_upward_from(cwd)
    add_upward_from(vim.fn.getcwd(-1)) -- tab cwd
    add_upward_from(vim.fn.getcwd(-1, -1)) -- global cwd
    vim.list_extend(files, loader.loaded.history)

    if opts.buf_paths then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            add_upward_from(vim.fs.dirname(vim.api.nvim_buf_get_name(buf)))
        end
    end

    -- now filter results and remove duplicates
    local set = {}
    files = vim.tbl_map(require('exrc.utils').clean_path, files)
    files = vim.tbl_map(vim.fs.normalize, files)
    files = vim.tbl_filter(function (file)
        if set[file] then
            return false
        end
        set[file] = true
        return opts.is_loaded == nil or loader.is_loaded(file) == opts.is_loaded
    end, files)

    return files
end

---@class exrc.exrc_do.Opts
---@field get_list_opts fun(opts): table
---@field on_select fun(file: string)
---@field auto_select_single? boolean

---@param opts exrc.exrc_do.Opts
local function exrc_do(opts)
    return function(cmd_opts)
        local loader = require('exrc.loader')
        local utils = require('exrc.utils')

        local files = exrc_list(opts.get_list_opts(cmd_opts))
        table.sort(files)

        if #files > 0 then
            if #files == 1 and opts.auto_select_single then
                opts.on_select(files[1])
            else
                select_files(files, 'Select exrc file to edit:', opts.on_select)
            end
        else
            utils.log.error('No exrc files found')
        end
    end
end

local function edit(file)
    vim.cmd.edit(file)
end

M.exrc_edit = exrc_do {
    get_list_opts = function(opts)
        return { buf_paths = opts.bang }
    end,
    on_select = edit,
    auto_select_single = true,
}

M.exrc_edit_loaded = exrc_do {
    get_list_opts = function(opts)
        return { buf_paths = true, is_loaded = not opts.bang }
    end,
    on_select = edit,
    auto_select_single = true,
}

M.exrc_load = exrc_do {
    get_list_opts = function(opts)
        return { buf_paths = true, is_loaded = not opts.bang and false or nil }
    end,
    on_select = function(file)
        local loader = require('exrc.loader')
        loader.load(file)
    end,
}

return M
