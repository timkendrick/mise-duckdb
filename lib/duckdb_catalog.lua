--- Lists the extension names that DuckDB repositories publish.

local cmd = require("cmd")
local http = require("http")
local json = require("json")
local log = require("log")
local ext = require("duckdb_ext")

local M = {}

local CORE_STATS_URL = "https://extensions.duckdb.org/downloads-last-week.json"
local COMMUNITY_STATS_URL = "https://community-extensions.duckdb.org/downloads-last-week.json"
local DUCKDB_COMMAND = "env -u AI_AGENT duckdb -csv -noheader -c 'SELECT extension_name FROM duckdb_extensions()'"

---@return string[]|nil
local function names_from_duckdb()
    local ok, output = pcall(cmd.exec, DUCKDB_COMMAND, { timeout = 30 })
    if not ok then
        log.debug("cannot list core extensions with the duckdb CLI:", output)
        return nil
    end
    local names = {}
    for line in output:gmatch("[^\r\n]+") do
        if line:match("^[%w_%-]+$") then
            names[#names + 1] = line
        end
    end
    if #names == 0 then
        return nil
    end
    table.sort(names)
    return names
end

---@param url string
---@return string[]
local function names_from_stats(url)
    local response, request_error = http.try_get({ url = url })
    if response == nil or request_error ~= nil then
        log.debug("cannot fetch", url, request_error)
        return {}
    end
    if response.status_code ~= 200 then
        log.debug("cannot fetch", url, "HTTP", response.status_code)
        return {}
    end
    local ok, stats = pcall(json.decode, response.body)
    if not ok or type(stats) ~= "table" then
        log.debug("cannot parse", url)
        return {}
    end
    return ext.extension_names_from_stats(stats)
end

---@return BackendToolEntry[]
function M.list()
    local core = names_from_duckdb() or names_from_stats(CORE_STATS_URL)
    local community = names_from_stats(COMMUNITY_STATS_URL)
    return ext.merge_catalogs({
        { names = core, description = "DuckDB core extension" },
        { names = community, description = 'DuckDB community extension (set repository = "community")' },
    })
end

return M
