local M = {}

local utils = require('exrc.utils')

---@class exrc.Loaded
---@field path string
---@field hash string sha256
---@field on_unload? fun()

M.loaded = {
    ---@type string[]
    history = {},
    ---@type table<string, exrc.Loaded>
    db = {},
}

---@param path string
---@return boolean
function M.is_loaded(path)
    return M.loaded.db[utils.clean_path(path)] ~= nil
end

function M.add_on_unload(exrc_path, fn)
    local entry = assert(M.loaded.db[exrc_path])
    local old_fn = entry.on_unload
    entry.on_unload = function()
        if old_fn then
            old_fn()
        end
        fn()
    end
end

local function db_remove(exrc_path)
    utils.log.trace('exrc.db_remove(%s)', exrc_path)
    -- remove old one from history
    for i, hist_path in ipairs(M.loaded.history) do
        if hist_path == exrc_path then
            table.remove(M.loaded.history, i)
            break
        end
    end
    M.loaded.db[exrc_path] = nil
end

--- Name of exrc file that is currently being loaded
---@type string?
M._now_loading = nil

function M.mark_loaded(exrc_path)
    utils.log.trace('exrc.mark_loaded(%s)', exrc_path)
    exrc_path = utils.clean_path(exrc_path)
    assert(not M.is_loaded(exrc_path))

    -- NOTE: when mark_loaded is called we either want vim.secure.read prompt
    -- or the file has already been trusted
    local data = vim.secure.read(exrc_path)
    assert(data, 'vim.secure.read failed for mark_loaded')
    local hash = vim.fn.sha256(data)

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
    utils.log.trace('exrc.load(%s)', exrc_path)
    exrc_path = utils.clean_path(exrc_path)

    -- Ensure we trust the file before loading
    local data = vim.secure.read(exrc_path)
    if not data then
        error(string.format('Could not read file "%s"', data))
    end

    M.unload(exrc_path)

    -- execute the file, not 100% secure (delay between vim.secure.read and vim.cmd.source) but secure enough
    utils.log.debug('Loading exrc "%s"', exrc_path)
    M._now_loading = exrc_path
    local ok, result = xpcall(vim.cmd.source, debug.traceback, exrc_path)
    M._now_loading = nil

    if not ok then
        utils.log.error('Failed to load exrc "%s"', exrc_path)
        error(result)
    elseif not M.loaded.db[exrc_path] then -- if not called by Context:new
        M.mark_loaded(exrc_path)
    end
end

--- Unload given exrc file by calling on_unload and removing from db
---@param exrc_path string
function M.unload(exrc_path)
    exrc_path = utils.clean_path(exrc_path)
    if M.loaded.db[exrc_path] and M.loaded.db[exrc_path].on_unload then
        utils.log.trace('exrc.unload.on_unload(%s)', exrc_path)
        M.loaded.db[exrc_path].on_unload()
    end
    db_remove(exrc_path)
end

---@type string[]
M.pending_load = {}

function M.load_pending()
    local pending = vim.tbl_filter(function(path)
        return not M.is_loaded(path)
    end, M.pending_load)
    pending = utils.unique(pending)
    utils.log.trace('exrc.load_pending(#%d)', #pending)
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
            end,
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
    utils.log.trace('exrc.ui_load(#%d, %s): aleady_pending=%d', #candidates, try_now, #M.pending_load)

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
            end,
        })
        coroutine.yield()
    end

    M.load_pending()
end

--- Load exrc files in given directories
---@param dirs string[]
function M.load_from_dirs(dirs)
    local candidates = vim.iter(dirs)
        :map(function(dir)
            return vim.fs.joinpath(dir, '.nvim.lua')
        end)
        :filter(function(exrc)
            return vim.fn.filereadable(exrc) == 1
        end)
        :totable()
    candidates = utils.unique(candidates)

    M.ui_load(candidates)
end

--- Load exrc from files in directories from getcwd (global/tabs/windows),
--- by default global+tabs.
---@param opts? { global?: boolean, tabs?: boolean, windows?: boolean }
function M.load_from_cwd(opts)
    M.load_from_dirs(utils.get_dirs(opts))
end

--- DirChanged handler that loads exrc files
function M.on_dir_changed()
    ---@type { scope: 'global'|'tabpage'|'window', cwd: string, changed_window: boolean }
    local event = vim.api.nvim_get_vvar('event')
    local cwd = vim.fn.fnamemodify(event.cwd, ':p')
    if (event.scope == 'global' or event.scope == 'tabpage') and not event.changed_window then
        utils.log.trace('exrc.on_dir_changed(%s)', cwd)
        coroutine.wrap(M.load_from_dirs) { cwd }
    end
end

return M
