local cmd = require("cmd")
local file = require("file")
local json = require("json")
local log = require("log")
local ext = require("duckdb_ext")

---@param path string
---@return string
local function read_symlink(path)
    local target = cmd.exec('readlink "$LINK"', { env = { LINK = path } })
    return (target:gsub("[\r\n]+$", ""))
end

--- Removes the links that BackendInstall created, if they still point into the install directory.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backenduninstall
--- @param ctx BackendUninstallCtx
function PLUGIN:BackendUninstall(ctx)
    local record_path = file.join_path(ctx.install_path, ext.LINK_RECORD_FILE)
    if not file.exists(record_path) then
        log.debug("no link record at", record_path)
        return
    end

    local record = json.decode(file.read(record_path))
    for _, link in ipairs(record.links) do
        local stat = file.stat(link.target)
        if stat == nil then
            log.debug("link already removed:", link.target)
        elseif not stat.is_symlink then
            log.info("leaving", link.target, "because it is not a link to this install")
        elseif read_symlink(link.target) ~= link.source then
            log.info("leaving", link.target, "because it links to another file")
        else
            local removed, remove_error = os.remove(link.target)
            if not removed then
                error("cannot remove " .. link.target .. ": " .. tostring(remove_error))
            end
        end
    end
end
