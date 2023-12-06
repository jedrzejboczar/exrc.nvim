local M = {}

local utils = require('exrc.utils')

--- As defined in |exrc| ('.nvim.lua', '.nvimrc', '.exrc') but we use only the lua file
M.EXRC_NAME = '.nvim.lua'

---@class exrc.Loaded
---@field path string
---@field hash string sha256

M.loaded = {
    ---@type string[]
    history = {},
    ---@type table<string, exrc.Loaded>
    db = {}
}

---@param path string
---@return boolean
function M.is_loaded(path)
    return M.loaded.db[utils.clean_path(path)] ~= nil
end

---@param fname string
---@return string
local function read_file(fname)
    local fd = assert(vim.loop.fs_open(fname, "r", 438))
    local stat = assert(vim.loop.fs_fstat(fd))
    local data = assert(vim.loop.fs_read(fd, stat.size, 0))
    assert(vim.loop.fs_close(fd))
    return data
end

--- Name of exrc file that is currently being loaded
---@type string?
M._now_loading = nil

function M.mark_loaded(exrc_path)
    exrc_path = utils.clean_path(exrc_path)

    -- NOTE: when mark_loaded is called we either want vim.secure.read prompt
    -- or the file has already been trusted
    local data = vim.secure.read(exrc_path)
    assert(data, 'vim.secure.read failed for mark_loaded')
    local hash = vim.fn.sha256(data)

    -- remove old one from history
    for i, hist_path in ipairs(M.loaded.history) do
        if hist_path == exrc_path then
            table.remove(M.loaded.history, i)
            break
        end
    end

    -- add to database
    table.insert(M.loaded.history, exrc_path)
    M.loaded.db[exrc_path] = {
        path = exrc_path,
        hash = hash,
    }
end

--- Load given exrc file
---@param exrc_path string
function M.load(exrc_path)
    exrc_path = utils.clean_path(exrc_path)

    -- Ensure we trust the file before loading
    local data = vim.secure.read(exrc_path)
    if not data then
        error(string.format('Could not read file "%s"', data))
    end

    -- execute the file, not 100% secure (delay between vim.secure.read and vim.cmd.source) but secure enough
    utils.log.debug('Loading exrc "%s"', exrc_path)
    M._now_loading = exrc_path
    local ok, result = xpcall(vim.cmd.source, debug.traceback, exrc_path)
    M._now_loading = nil

    if not ok then
        utils.log.error('Failed to load exrc "%s"', exrc_path)
        error(result)
    else
        M.mark_loaded(exrc_path)
    end
end

---@type string[]
M.pending_load = {}

function M.load_pending()
    local pending = vim.tbl_filter(M.is_loaded, M.pending_load)
    if #pending == 0 then
        return
    end

    local function remove_pending(item)
        for i, path in ipairs(M.pending_load) do
            if path == item then
                table.remove(M.pending_load, i)
                return
            end
        end
    end

    local n_initial = #pending
    local n_loaded = 0
    pending = utils.list_to_set(pending)

    while vim.tbl_count(pending) > 0 do
        local items = vim.tbl_keys(pending)
        table.sort(items)

        local item = utils.ui_select(items, {
            prompt = 'Select .nvim.lua files to source, or quit to abort',
            format_item = function(item)
                return vim.fn.fnamemodify(item, ':~')
            end
        })
        if item == nil then
            break
        end

        pending[item] = nil
        remove_pending(item)

        local ok, err = pcall(M.load, item)
        if ok then
            n_loaded = n_loaded + 1
        elseif err and vim.startswith(err, 'Could not read file') then
            utils.log.warn('Aborted: %s', item)
        end
    end

    utils.log.info('Loaded %d/%d files', n_loaded, n_initial)
    M.pending_load = {}
end

local function is_float()
    local config = vim.api.nvim_win_get_config(0)
    return config.relative and config.relative ~= ''
end

--- Determines if user is ready to hanndle ui.select
function M.is_ui_ready()
    return not is_float()
end

--- Add exrc files to load queue and load when user can conveniently handle ui.select
---@param candidates string[]
---@param try_now boolean?
function M.ui_load(candidates, try_now)
    local already_pending = #M.pending_load > 0
    vim.list_extend(M.pending_load, candidates)
    if already_pending then
        return
    end

    local resume = utils.coroutine_resume()
    if not try_now or not M.is_ui_ready() then
        vim.api.nvim_create_autocmd('CursorHold', {
            callback = function()
                if M.is_ui_ready() then
                    resume()
                    return true -- remove autocmd
                end
            end
        })
        coroutine.yield()
    end

    M.load_pending()
end

--- Load exrc files in given directories
---@param dirs string[]
function M.load_from_dirs(dirs)
    local candidates = vim.iter(dirs)
        :map(function(dir) return vim.fs.joinpath(dir, '.nvim.lua') end)
        :filter(function(exrc) return vim.fn.filereadable(exrc) == 1 end)
        :totable()
    candidates = utils.unique(candidates)

    M.ui_load(candidates)
end

--- DirChanged handler that loads exrc files
function M.on_dir_changed()
    ---@type { scope: 'global'|'tabpage'|'window', cwd: string, changed_window: boolean }
    local event = vim.api.nvim_get_vvar('event')
    local cwd = vim.fn.fnamemodify(event.cwd, ':p')
    if (event.scope == 'global' or event.scope == 'tabpage') and not event.changed_window then
        coroutine.wrap(M.load_from_dirs)({cwd})
    end
end

return M
