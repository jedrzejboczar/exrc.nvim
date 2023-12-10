local config = require('exrc.config')

local function logger(level, notify_fn, cond)
    return function(...)
        if level < config.min_log_level then
            return
        end
        if cond and not cond() then
            return
        end
        -- Use notify_fn as string to get correct function if user
        -- replaced it later via vim.notify = ...
        local notify = vim[notify_fn]
        notify(string.format(...), level)
    end
end

return {
    trace = logger(vim.log.levels.TRACE, 'notify'),
    debug = logger(vim.log.levels.DEBUG, 'notify'),
    info = logger(vim.log.levels.INFO, 'notify'),
    warn = logger(vim.log.levels.WARN, 'notify'),
    error = logger(vim.log.levels.ERROR, 'notify'),
    trace_once = logger(vim.log.levels.TRACE, 'notify_once'),
    debug_once = logger(vim.log.levels.DEBUG, 'notify_once'),
    info_once = logger(vim.log.levels.INFO, 'notify_once'),
    warn_once = logger(vim.log.levels.WARN, 'notify_once'),
    error_once = logger(vim.log.levels.ERROR, 'notify_once'),
}
