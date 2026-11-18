--- Pure helpers for DuckDB extension repositories, footers and install info files.
--- This module does not use mise modules, so plain Lua can load it in unit tests.

local M = {}

M.FOOTER_SIZE = 512
M.LINK_RECORD_FILE = "mise-duckdb-links.json"
M.DEFAULT_EXTENSION_DIRECTORY = "~/.duckdb/extensions"
M.INSTALL_MODE_REPOSITORY = 1
M.REPOSITORY_TYPE_CORE = 0
M.REPOSITORY_TYPE_COMMUNITY = 1

--- Repository names that DuckDB knows. The type selects the public keys that DuckDB trusts to sign their extensions.
M.KNOWN_REPOSITORIES = {
    core = { url = "http://extensions.duckdb.org", type = M.REPOSITORY_TYPE_CORE },
    core_nightly = { url = "http://nightly-extensions.duckdb.org", type = M.REPOSITORY_TYPE_CORE },
    community = { url = "http://community-extensions.duckdb.org", type = M.REPOSITORY_TYPE_COMMUNITY },
}

--- The first DuckDB major version that records the repository type and name in install info files.
local REPOSITORY_ORIGIN_MAJOR_VERSION = 2

local FOOTER_FIELD_SIZE = 32
local FOOTER_MAGIC_VALUE = "4"

---@class Repository
---@field name string Known repository name, or "" for a custom URL
---@field type integer Repository type that DuckDB records in install info files
---@field url string URL that DuckDB records as the repository of an installed extension
---@field download_url string URL that the plugin downloads from

---@class ParsedVersion
---@field duckdb_version string DuckDB version directory name, such as "v2.0.0"
---@field extension_version string|nil Published extension version, such as "v0.4.0"

---@class ExtensionFooter
---@field platform string
---@field target_version string DuckDB version for C++ extensions, C API version for C extensions
---@field extension_version string
---@field abi_type string

---@class InstallInfo
---@field mode integer
---@field full_path string
---@field repository_url string
---@field version string
---@field etag string|nil
---@field repository_type integer|nil Omitted from the file when nil or core
---@field repository_name string|nil Omitted from the file when nil or empty

---@class DuckDBRelease
---@field version string
---@field created_at string Release date as an RFC 3339 timestamp

---@param name any
---@return string
function M.validate_extension_name(name)
    if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
        error("invalid DuckDB extension name: " .. tostring(name))
    end
    return name
end

--- Splits a mise version into the DuckDB version and the optional published extension version.
--- "2.0.0" selects the build that the repository serves for DuckDB v2.0.0.
--- "2.0.0+v0.4.0" selects the published extension version v0.4.0 for DuckDB v2.0.0.
---@param version string
---@return ParsedVersion
function M.parse_version(version)
    local duckdb_part, extension_part = version:match("^([^+]*)%+(.*)$")
    if duckdb_part == nil then
        duckdb_part = version
    end
    local number = duckdb_part:match("^v?(%d+%.%d+%.%d+)$")
    if number == nil then
        error("invalid version '" .. version .. "': expected a DuckDB version such as 2.0.0 or 2.0.0+v0.4.0")
    end
    if extension_part ~= nil and not extension_part:match("^[%w_%.%-]+$") then
        error("invalid version '" .. version .. "': the extension version after '+' is empty or invalid")
    end
    return { duckdb_version = "v" .. number, extension_version = extension_part }
end

---@param option string|nil Value of the `repository` tool option
---@return Repository
function M.resolve_repository(option)
    local name = option
    if name == nil or name == "" then
        name = "core"
    end
    local known = M.KNOWN_REPOSITORIES[name]
    if known ~= nil then
        return {
            name = name,
            type = known.type,
            url = known.url,
            download_url = (known.url:gsub("^http://", "https://")),
        }
    end
    if name:match("^https?://") then
        local url = (name:gsub("/+$", ""))
        return { name = "", type = M.REPOSITORY_TYPE_CORE, url = url, download_url = url }
    end
    error("invalid repository '" .. name .. "': expected core, core_nightly, community, or an http:// or https:// URL")
end

--- Returns the DuckDB platform name, such as "osx_arm64" or "linux_amd64_musl".
---@param os_type string
---@param arch_type string
---@param env_type string|nil
---@return string
function M.platform(os_type, arch_type, env_type)
    local os_names = { darwin = "osx", linux = "linux" }
    local arch_names = { amd64 = "amd64", arm64 = "arm64" }
    local os_name = os_names[os_type]
    local arch_name = arch_names[arch_type]
    if os_name == nil or arch_name == nil then
        error("unsupported platform: " .. tostring(os_type) .. "/" .. tostring(arch_type))
    end
    local platform = os_name .. "_" .. arch_name
    if os_type == "linux" and env_type == "musl" then
        platform = platform .. "_musl"
    end
    return platform
end

--- Builds the URL of a compressed extension, using the layout of DuckDB's `INSTALL` statement.
---@param base_url string
---@param name string
---@param version ParsedVersion
---@param platform string
---@return string
function M.extension_url(base_url, name, version, platform)
    local file_name = name .. ".duckdb_extension.gz"
    if version.extension_version ~= nil then
        return table.concat(
            { base_url, name, version.extension_version, version.duckdb_version, platform, file_name },
            "/"
        )
    end
    return table.concat({ base_url, version.duckdb_version, platform, file_name }, "/")
end

---@param footer string
---@param index integer Zero-based field index, in file order
---@return string
local function footer_field(footer, index)
    local start = index * FOOTER_FIELD_SIZE + 1
    local raw = footer:sub(start, start + FOOTER_FIELD_SIZE - 1)
    return (raw:gsub("%z+$", ""))
end

--- Parses the metadata in the last 512 bytes of an uncompressed extension file.
---@param footer string
---@return ExtensionFooter
function M.parse_footer(footer)
    if #footer ~= M.FOOTER_SIZE then
        error("extension footer must be " .. M.FOOTER_SIZE .. " bytes, got " .. #footer)
    end
    if footer_field(footer, 7) ~= FOOTER_MAGIC_VALUE then
        error("file is not a DuckDB extension: the footer has no metadata")
    end
    return {
        platform = footer_field(footer, 6),
        target_version = footer_field(footer, 5),
        extension_version = footer_field(footer, 4),
        abi_type = footer_field(footer, 3),
    }
end

---@param value integer
---@return string
local function encode_varint(value)
    local bytes = {}
    repeat
        local byte = value % 128
        value = math.floor(value / 128)
        if value > 0 then
            byte = byte + 128
        end
        bytes[#bytes + 1] = string.char(byte)
    until value == 0
    return table.concat(bytes)
end

---@param id integer
---@return string
local function encode_field_id(id)
    return string.char(id % 256, math.floor(id / 256))
end

---@param id integer
---@param value integer|nil
---@param default integer
---@return string
local function encode_integer_property(id, value, default)
    if value == nil or value == default then
        return ""
    end
    return encode_field_id(id) .. encode_varint(value)
end

---@param id integer
---@param value string|nil
---@return string
local function encode_string_property(id, value)
    if value == nil or value == "" then
        return ""
    end
    return encode_field_id(id) .. encode_varint(#value) .. value
end

--- Encodes an install info file in DuckDB's binary serialization format.
---@param info InstallInfo
---@return string
function M.encode_install_info(info)
    return table.concat({
        encode_field_id(100) .. encode_varint(info.mode),
        encode_string_property(101, info.full_path),
        encode_string_property(102, info.repository_url),
        encode_string_property(103, info.version),
        encode_string_property(104, info.etag),
        encode_integer_property(105, info.repository_type, M.REPOSITORY_TYPE_CORE),
        encode_string_property(106, info.repository_name),
        encode_field_id(0xFFFF),
    })
end

--- Describes an extension installed from a repository, in the form that the target DuckDB version reads.
---@param repository Repository
---@param name string
---@param version ParsedVersion
---@param platform string
---@param extension_version string Extension version from the extension footer
---@param etag string|nil
---@return InstallInfo
function M.repository_install_info(repository, name, version, platform, extension_version, etag)
    local info = {
        mode = M.INSTALL_MODE_REPOSITORY,
        full_path = M.extension_url(repository.url, name, version, platform),
        repository_url = repository.url,
        version = extension_version,
        etag = etag,
    }
    local major = tonumber(version.duckdb_version:match("^v(%d+)%.")) or 0
    if major >= REPOSITORY_ORIGIN_MAJOR_VERSION then
        info.repository_type = repository.type
        info.repository_name = repository.name
    end
    return info
end

--- Returns the MD5 digest that an ETag holds, or nil when the ETag is not a plain MD5 digest.
---@param etag string|nil
---@return string|nil
function M.etag_md5(etag)
    if etag == nil then
        return nil
    end
    local digest = etag:match('^"?(%x+)"?$')
    if digest ~= nil and #digest == 32 then
        return digest:lower()
    end
    return nil
end

---@param option string|nil Value of the `extension_directory` tool option
---@param home string|nil
---@return string
function M.extension_root(option, home)
    local root = option
    if root == nil or root == "" then
        root = M.DEFAULT_EXTENSION_DIRECTORY
    end
    if root == "~" or root:sub(1, 2) == "~/" then
        if home == nil or home == "" then
            error("cannot expand '" .. root .. "': HOME is not set")
        end
        root = home .. root:sub(2)
    end
    if root:sub(1, 1) ~= "/" then
        error("extension_directory must be an absolute path: " .. root)
    end
    return root
end

---@param version string
---@return integer[]
local function version_numbers(version)
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

---@param a string
---@param b string
---@return boolean
local function version_less_than(a, b)
    local left = version_numbers(a)
    local right = version_numbers(b)
    for index = 1, 3 do
        if left[index] ~= right[index] then
            return left[index] < right[index]
        end
    end
    return false
end

---@param line string
---@return string[]
local function split_csv_line(line)
    if line:find('"', 1, true) then
        error("unsupported quoted field in DuckDB release list: " .. line)
    end
    local fields = {}
    for field in (line .. ","):gmatch("([^,]*),") do
        fields[#fields + 1] = field
    end
    return fields
end

---@param header string[]
---@param name string
---@return integer
local function column_index(header, name)
    for index, column in ipairs(header) do
        if column == name then
            return index
        end
    end
    error("DuckDB release list has no '" .. name .. "' column")
end

--- Parses the DuckDB release list that duckdb.org publishes as CSV, and returns the releases oldest first.
---@param csv string
---@return DuckDBRelease[]
function M.parse_releases_csv(csv)
    local lines = {}
    for line in csv:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end
    if #lines == 0 then
        error("DuckDB release list is empty")
    end
    local header = split_csv_line(lines[1])
    local date_column = column_index(header, "release_date")
    local version_column = column_index(header, "version_number")

    local result = {}
    for index = 2, #lines do
        local fields = split_csv_line(lines[index])
        local version = fields[version_column]
        local date = fields[date_column]
        if version == nil or not version:match("^%d+%.%d+%.%d+$") then
            error("invalid version in DuckDB release list: " .. lines[index])
        end
        if date == nil or not date:match("^%d%d%d%d%-%d%d%-%d%d$") then
            error("invalid release date in DuckDB release list: " .. lines[index])
        end
        result[#result + 1] = { version = version, created_at = date .. "T00:00:00Z" }
    end
    table.sort(result, function(a, b)
        return version_less_than(a.version, b.version)
    end)
    return result
end

--- Returns the extension names in a download statistics file, without metadata keys such as "_last_update".
---@param stats table<string, any>
---@return string[]
function M.extension_names_from_stats(stats)
    local names = {}
    for key in pairs(stats) do
        if type(key) == "string" and key:sub(1, 1) ~= "_" then
            names[#names + 1] = key
        end
    end
    table.sort(names)
    return names
end

--- Combines extension names from repositories into tool entries. Earlier catalogs take precedence.
---@param catalogs {names: string[], description: string}[]
---@return BackendToolEntry[]
function M.merge_catalogs(catalogs)
    local seen = {}
    local tools = {}
    for _, catalog in ipairs(catalogs) do
        for _, name in ipairs(catalog.names) do
            if not seen[name] then
                seen[name] = true
                tools[#tools + 1] = { name = name, description = catalog.description }
            end
        end
    end
    table.sort(tools, function(a, b)
        return a.name < b.name
    end)
    return tools
end

---@param tools BackendToolEntry[]
---@param query string
---@return BackendToolEntry[]
function M.filter_tools(tools, query)
    local needle = query:lower()
    local result = {}
    for _, tool in ipairs(tools) do
        if tool.name:lower():find(needle, 1, true) then
            result[#result + 1] = tool
        end
    end
    return result
end

return M
