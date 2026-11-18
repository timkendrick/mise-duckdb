local catalog = require("duckdb_catalog")
local ext = require("duckdb_ext")

--- Lists the extensions in the core and community repositories whose names contain the query.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendsearchtools
--- @param ctx BackendSearchToolsCtx
--- @return BackendListToolsResult
function PLUGIN:BackendSearchTools(ctx)
    return { tools = ext.filter_tools(catalog.list(), ctx.query or "") }
end
