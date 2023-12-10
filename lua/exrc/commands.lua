local M = {}

local config = require('exrc.config')
local defs = require('exrc.defs')
local loader = require('exrc.loader')
local log = require('exrc.log')
local utils = require('exrc.utils')

---@class exrc.commands.Display
---@field format_item fun(path: string): string
---@field telescope_display fun(entry: table, orig_display: fun(entry: table): any): any

local display_exrc_loaded = {
    format_item = function(file)
        return string.format('%s (%sloaded)', file, loader.is_loaded(file) and '' or 'not ')
    end,
    telescope_display = function(entry, display)
        local text, highlights = display(entry)
        highlights = highlights or {}
        local loaded_str = string.format('(%sloaded)', loader.is_loaded(entry.value) and '' or 'not ')
        table.insert(highlights, { { #text + 1, #text + 1 + #loaded_str }, 'TelescopeResultsVariable' })
        text = text .. ' ' .. loaded_str
        return text, highlights
    end,
}

local display_exrc_dir = {
    format_item = function(dir)
        return vim.fs.joinpath(dir, defs.EXRC_NAME)
    end,
    telescope_display = function(entry, _display)
        return vim.fs.joinpath(entry.value, defs.EXRC_NAME)
    end,
}

---@class exrc.commands.select_files.Opts
---@field files string[]
---@field prompt string
---@field on_choice fun(file: string)
---@field display? exrc.commands.Display


---@param opts exrc.commands.select_files.Opts
local function select_files(opts)
    local use_telescope = config.use_telescope and pcall(require, 'telescope')
    if not use_telescope then
        local ui_opts = {
            prompt = opts.prompt,
            format_item = vim.tbl_get(opts, 'display', 'format_item'),
        }
        vim.ui.select(opts.files, ui_opts, opts.on_choice)
    else
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local finders = require('telescope.finders')
        local make_entry = require('telescope.make_entry')
        local pickers = require('telescope.pickers')
        local tele_conf = require('telescope.config').values

        local gen_from_file = make_entry.gen_from_file()
        local done = false
        local patch_mt = function(entry)
            local display = vim.tbl_get(opts, 'display', 'telescope_display')
            if done or not display then
                return
            end
            done = true

            local mt = getmetatable(entry)
            local orig_display = mt.display
            mt.display = function(entry)
                return display(entry, orig_display)
            end
        end

        pickers.new({}, {
            prompt_title = opts.prompt,
            finder = finders.new_table {
                results = opts.files,
                entry_maker = function(file)
                    local entry = gen_from_file(file)
                    patch_mt(entry)
                    return entry
                end,
            },
            previewer = tele_conf.file_previewer({}),
            sorter = tele_conf.file_sorter({}),
            attach_mappings = function()
                actions.select_default:replace(function(buf)
                    local entry = action_state.get_selected_entry()
                    actions.close(buf)
                    opts.on_choice(entry.value)
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
    files = vim.tbl_map(utils.clean_path, files)
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
---@field get_paths fun(opts): string[]
---@field on_select fun(file: string)
---@field auto_select_single? boolean
---@field prompt string
---@field error_msg? string
---@field display? exrc.commands.Display

---@param opts exrc.exrc_do.Opts
local function exrc_do(opts)
    return function(cmd_opts)
        local paths = opts.get_paths(cmd_opts)
        table.sort(paths)

        if #paths > 0 then
            if #paths == 1 and opts.auto_select_single then
                opts.on_select(paths[1])
            else
                select_files {
                    files = paths,
                    prompt = opts.prompt,
                    on_choice = opts.on_select,
                    display = opts.display,
                }
            end
        else
            log.error(opts.error_msg or 'No exrc files found')
        end
    end
end

local function edit(file)
    vim.cmd.edit(file)
end

M.exrc_edit = exrc_do {
    prompt = 'Select exrc file to edit:',
    display = display_exrc_loaded,
    get_paths = function(opts)
        return exrc_list { buf_paths = opts.bang }
    end,
    on_select = edit,
    auto_select_single = true,
}

M.exrc_edit_loaded = exrc_do {
    prompt = 'Select exrc file to edit:',
    display = display_exrc_loaded,
    get_paths = function(opts)
        return exrc_list { buf_paths = true, is_loaded = not opts.bang }
    end,
    on_select = edit,
    auto_select_single = true,
}

M.exrc_load = exrc_do {
    prompt = 'Select exrc file to load:',
    display = display_exrc_loaded,
    get_paths = function(opts)
        return exrc_list { buf_paths = true, is_loaded = not opts.bang and false or nil }
    end,
    on_select = function(file)
        local loader = require('exrc.loader')
        loader.load(file)
    end,
}

M.exrc_create = exrc_do {
    prompt = 'Select exrc file to create:',
    display = display_exrc_dir,
    get_paths = function()
        local dirs = {
            vim.fn.getcwd(),
            vim.fn.getcwd(-1),
            vim.fn.getcwd(-1, -1),
        }
        for _, client in ipairs(vim.lsp.get_clients()) do
            table.insert(dirs, client.config.root_dir)
        end

        local git_dirs = {}
        for _, dir in ipairs(dirs) do
            local found = vim.fs.find('.git', { upward = true, path = dir })
            if found then
                for _, path in ipairs(found) do
                    table.insert(git_dirs, vim.fs.dirname(path))
                end
            end
        end
        vim.list_extend(dirs, git_dirs)

        dirs = vim.tbl_map(utils.clean_path, dirs)
        dirs = utils.unique(dirs)
        dirs = vim.tbl_filter(function(dir)
            return vim.fn.filereadable(vim.fs.joinpath(dir, defs.EXRC_NAME)) == 0
        end, dirs)

        table.sort(dirs)
        return dirs
    end,
    on_select = function(dir)
        vim.cmd.edit(vim.fs.joinpath(dir, defs.EXRC_NAME))
    end,
}

return M
