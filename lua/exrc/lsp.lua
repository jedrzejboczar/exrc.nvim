local M = {}

local utils = require('exrc.utils')

--- Handler called in on_new_config hook that should update config in-place.
--- Called only after root_dir/client_name matching.
---@alias exrc.lsp.OnNewConfig fun(config: table, root_dir: string)

--- exrc_path -> client_name -> handler
---@type table<string, table<string, exrc.lsp.OnNewConfig>>
M.handlers = {}

local function dir_matches(top_dir, dir)
    dir = utils.clean_path(dir)
    top_dir = utils.clean_path(top_dir)
    return vim.startswith(dir, top_dir)
end

--- lspconfig on_new_config hook that will call all registered handlers
function M.on_new_config(config, root_dir)
    ---@type { exrc_dir: string, handler: exrc.lsp.OnNewConfig }[]
    local matching = {}

    for exrc_path, handlers in pairs(M.handlers) do
        local exrc_dir = vim.fs.dirname(exrc_path)
        if dir_matches(exrc_dir, root_dir) then
            for client_name, handler in pairs(handlers) do
                if config.name == client_name then
                    table.insert(matching, {
                        handler = handler,
                        exrc_dir = exrc_dir,
                        client_name = client_name,
                    })
                end
            end
        end
    end

    -- sort by longest exrc_dir first
    table.sort(matching, function(a, b)
        return #utils.clean_path(a.exrc_dir) > #utils.clean_path(b.exrc_dir)
    end)

    if #matching > 0 then
        local match = matching[1]
        match.handler(config, root_dir)
        utils.log.debug(
            'exrc.lsp.on_new_config: applied for %s out of %d candidates from dir "%s"',
            config.name,
            #matching,
            match.exrc_dir
        )
    end
end

-- Adapted from lspconfig :LspRestart
local function restart_clients(clients)
    local detach_clients = {}
    for _, client in ipairs(clients) do
        client.stop()
        if vim.tbl_count(client.attached_buffers) > 0 then
            detach_clients[client.name] = { client, client.attached_buffers }
        end
    end
    local timer = vim.loop.new_timer()
    timer:start(
        500,
        100,
        vim.schedule_wrap(function()
            for client_name, tuple in pairs(detach_clients) do
                local client, attached_buffers = unpack(tuple)
                if client.is_stopped() then
                    for buf in pairs(attached_buffers) do
                        require('lspconfig.configs')[client_name].launch(buf)
                    end
                    detach_clients[client_name] = nil
                end
            end

            if next(detach_clients) == nil and not timer:is_closing() then
                timer:close()
            end
        end)
    )
end

--- Call this as a method of exrc.Context to get correct exrc_path
---@param exrc_path string
---@param handlers table<string, exrc.lsp.OnNewConfig> maps client_name to handler (after root_dir/client matching)
function M.setup(exrc_path, handlers)
    assert(require('lspconfig'), 'lspconfig needs to be installed')

    local first = not M.handlers[exrc_path]
    local exrc_dir = vim.fs.dirname(exrc_path)
    utils.log.debug(
        'exrc.lsp.setup(%s): %d handlers for dir: "%s"',
        first and 'first' or 'reload',
        #vim.tbl_keys(handlers),
        exrc_dir
    )

    M.handlers[exrc_path] = handlers

    -- restart all matching clients that are already running
    local to_restart = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
        if dir_matches(exrc_dir, client.config.root_dir) then
            if M.handlers[exrc_dir][client.config.name] then
                table.insert(to_restart, client)
            end
        end
    end
    if #to_restart > 0 then
        utils.log.debug('exrc.lsp.setup: restarting %d clients', #to_restart)
        restart_clients(to_restart)
    end
end

return M
