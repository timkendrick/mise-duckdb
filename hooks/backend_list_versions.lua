local http = require("http")
local ext = require("duckdb_ext")

local RELEASES_URL = "https://duckdb.org/data/duckdb-releases.csv"

--- Lists the DuckDB releases. Each version selects the extension build for that DuckDB release.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    local options = ctx.options or {}
    ext.validate_extension_name(ctx.tool)
    ext.resolve_repository(options.repository)

    local response = http.get({ url = RELEASES_URL })
    if response.status_code ~= 200 then
        error("fetching " .. RELEASES_URL .. " failed: HTTP " .. response.status_code)
    end

    local versions = {}
    for _, release in ipairs(ext.parse_releases_csv(response.body)) do
        versions[#versions + 1] = { version = release.version, created_at = release.created_at }
    end
    if #versions == 0 then
        error("no DuckDB releases found at " .. RELEASES_URL)
    end
    return { versions = versions }
end
