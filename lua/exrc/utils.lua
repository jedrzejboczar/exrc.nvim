local M = {}

local log = require('exrc.log')

function M.coroutine_resume()
    local co = assert(coroutine.running())
    return function(...)
        coroutine.resume(co, ...)
    end
end

---@generic T
---@param items T[]
---@param opts {}
---@return T?
function M.ui_select(items, opts)
    local resume = M.coroutine_resume()
    vim.ui.select(items, opts, resume)
    return coroutine.yield()
end

--- Transform path to a consistent version: absolute, normalized, directories do NOT end with /
---@param path string
---@return string
function M.clean_path(path)
    return vim.fs.normalize(assert(vim.fn.fnamemodify(path, ':p')))
end

---@param start? integer 0->debug.getinfo(), 1->get_call_stack(), 2->caller
---@return { source: string, short_src: string, linedefined: integer, lastlinedefined: integer, what: string }[]
local function get_call_stack(start)
    start = start or 2
    local stack = {}
    local what = 'S'
    local info = debug.getinfo(start, what)
    while info do
        table.insert(stack, info)
        start = start + 1
        info = debug.getinfo(start, what)
    end
    return stack
end

-- Load info cases (stack traces for given load methods):
-- 'exrc' by just opening nvim
--   1: info={ namewhat = "", short_src = '[string "<nvim>"]', source = "<nvim>", what = "main" }
-- :luafile filename
--   1: info={ namewhat = "", short_src = "stacktrace.lua", source = "@stacktrace.lua", what = "main" }
-- :source filename
--   1: info={ namewhat = "", short_src = ".../exrc.nvim/scratch/stacktrace.lua",
--             source = "@/full/path/to/exrc.nvim/scratch/stacktrace.lua", what = "main" }
-- loadstring(read(filename), filename)()
--   1: info={ namewhat = "", short_src = '[string "./stacktrace.lua"]', source = "./stacktrace.lua", what = "main" }
--   2: info={ namewhat = "", short_src = '[string ":lua"]', source = ":lua", what = "main" }
-- loadfile(filename)()
--   1: info={ namewhat = "", short_src = "./stacktrace.lua", source = "@./stacktrace.lua", what = "main" }
--   2: info={ namewhat = "", short_src = '[string ":lua"]', source = ":lua", what = "main" }
-- combo: exrc + luafile
--   1: info={ namewhat = "", short_src = "./stacktrace.lua", source = "@./stacktrace.lua", what = "main" }
--   2: info={ name = "luafile", namewhat = "field", short_src = "[C]", source = "=[C]", what = "C" }
--   3: info={ namewhat = "", short_src = '[string "<nvim>"]', source = "<nvim>", what = "main" }

---@class exrc.LoadInfo
---@field type 'exrc'|'luafile'|'source' detection between :luafile/:source might be inaccurate
---@field path string path to the loaded file

--- Retrieve load info when called in file loaded by |exrc| or ':luafile'/':source'.
---
--- First element in the returned LoadInfo is for the closest load, e.g. |exrc| which
--- does ':luafile' will return { 1: luafile, 2: exrc }.
---
---@return exrc.LoadInfo[]
function M.get_load_info()
    local stack = get_call_stack(3)
    local load_info = {}
    for _, frame in ipairs(stack) do
        if frame.what == 'main' then
            local info
            if frame.source == '<nvim>' then
                info = { type = 'exrc', path = M.clean_path('.nvim.lua') }
            elseif frame.source:sub(1, 1) == '@' then
                local path = frame.source:sub(2)
                -- :source will have a full path, but this might not always be true
                local type = vim.fs.basename(path) == path and 'luafile' or 'exrc'
                info = { type = type, path = M.clean_path(path) }
            end
            if info then
                table.insert(load_info, info)
            else
                log.debug(
                    'get_load_info: ignoring "main" frame: %s',
                    vim.inspect(frame):gsub('\n', ' '):gsub('%s+', ' ')
                )
            end
        end
    end
    return load_info
end

--- Get path to the currently sourced exrc file
---@return string
function M.get_exrc_path()
    return assert(M.get_load_info()[1].path)
end

function M.win_dir(win)
    return vim.fn.getcwd(win or 0)
end

function M.tab_dir(tab)
    tab = vim.api.nvim_tabpage_get_number(tab or vim.api.nvim_get_current_tabpage())
    return vim.fn.getcwd(-1, tab)
end

function M.global_dir()
    return vim.fn.getcwd(-1, -1)
end

---Defaults to global + tabs
---@param opts? { global?: boolean, tabs?: boolean, windows?: boolean }
function M.get_dirs(opts)
    opts = vim.tbl_extend('force', {
        global = true,
        tabs = true,
        windows = false,
    }, opts or {})

    local dirs = {}
    if opts.global then
        table.insert(dirs, M.global_dir())
    end
    if opts.tabs then
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
            table.insert(dirs, M.tab_dir(tab))
        end
    end
    if opts.windows then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            table.insert(dirs, M.win_dir(win))
        end
    end

    return M.unique(dirs)
end

-- Convert list-like table to a set. Uses true or value_fn(val) as set values.
function M.list_to_set(t, value_fn)
    local set = {}
    for _, val in ipairs(t) do
        set[val] = value_fn and value_fn(val) or true
    end
    return set
end

---@generic T
---@param list T[]
---@return T[]
function M.unique(list)
    local set = {}
    return vim.tbl_filter(function(val)
        if not set[val] then
            set[val] = true
            return true
        else
            return false
        end
    end, list)
end

return M
