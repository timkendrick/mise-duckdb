local catalog = require("duckdb_catalog")

--- Lists the extensions in the core and community repositories.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlisttools
--- @param _ctx table
--- @return BackendListToolsResult
function PLUGIN:BackendListTools(_ctx)
    return { tools = catalog.list() }
end
