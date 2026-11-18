local http = require("http")
local json = require("json")
local ext = require("duckdb_ext")

local RELEASES_URL = "https://api.github.com/repos/duckdb/duckdb/releases"
local PAGE_SIZE = 100

---@return GitHubRelease[]
local function fetch_releases()
    local releases = {}
    local page = 1
    while true do
        local url = RELEASES_URL .. "?per_page=" .. PAGE_SIZE .. "&page=" .. page
        local response = http.get({ url = url, headers = { ["Accept"] = "application/vnd.github+json" } })
        if response.status_code ~= 200 then
            error("fetching " .. url .. " failed: HTTP " .. response.status_code)
        end
        local batch = json.decode(response.body)
        for _, release in ipairs(batch) do
            releases[#releases + 1] = release
        end
        if #batch < PAGE_SIZE then
            return releases
        end
        page = page + 1
    end
end

--- Lists the stable DuckDB releases. Each version selects the extension build for that DuckDB release.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    local options = ctx.options or {}
    ext.validate_extension_name(ctx.tool)
    ext.resolve_repository(options.repository)

    local versions = {}
    for _, release in ipairs(ext.stable_duckdb_releases(fetch_releases())) do
        versions[#versions + 1] = { version = release.version, created_at = release.created_at }
    end
    if #versions == 0 then
        error("no stable DuckDB releases found at " .. RELEASES_URL)
    end
    return { versions = versions }
end
