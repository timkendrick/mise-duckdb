local cmd = require("cmd")
local file = require("file")
local http = require("http")
local json = require("json")
local log = require("log")
local ext = require("duckdb_ext")

---@param path string
---@return string
local function md5_digest(path)
    local command = RUNTIME.osType == "darwin" and 'md5 -q "$FILE"' or 'md5sum "$FILE"'
    local digest = cmd.exec(command, { env = { FILE = path } }):match("^(%x+)")
    if digest == nil then
        error("cannot compute the MD5 digest of " .. path)
    end
    return digest:lower()
end

---@param path string
---@return string
local function read_footer(path)
    local handle, open_error = io.open(path, "rb")
    if handle == nil then
        error("cannot open " .. path .. ": " .. tostring(open_error))
    end
    local size = handle:seek("end")
    if size < ext.FOOTER_SIZE then
        handle:close()
        error("file is not a DuckDB extension: " .. path .. " has only " .. size .. " bytes")
    end
    handle:seek("set", size - ext.FOOTER_SIZE)
    local footer = handle:read(ext.FOOTER_SIZE)
    handle:close()
    return footer
end

---@param path string
---@param content string
local function write_file(path, content)
    local handle, open_error = io.open(path, "wb")
    if handle == nil then
        error("cannot write " .. path .. ": " .. tostring(open_error))
    end
    handle:write(content)
    handle:close()
end

---@param source string
---@param target string
local function replace_with_symlink(source, target)
    if file.stat(target) ~= nil then
        local removed, remove_error = os.remove(target)
        if not removed then
            error("cannot replace " .. target .. ": " .. tostring(remove_error))
        end
    end
    file.symlink(source, target)
end

--- Downloads a DuckDB extension into the install directory and links it into the DuckDB extension directory.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    local options = ctx.options or {}
    local name = ext.validate_extension_name(ctx.tool)
    local version = ext.parse_version(ctx.version)
    local repository = ext.resolve_repository(options.repository)
    local platform = ext.platform(RUNTIME.osType, RUNTIME.archType, RUNTIME.envType)
    local root = ext.extension_root(options.extension_directory, os.getenv("HOME"))

    local download_url = ext.extension_url(repository.download_url, name, version, platform)
    local response = http.head({ url = download_url })
    if response.status_code == 404 or response.status_code == 403 then
        local subject = name
        if version.extension_version ~= nil then
            subject = name .. " " .. version.extension_version
        end
        error(
            string.format(
                "%s is not published for DuckDB %s on %s in %s (HTTP %d from %s)",
                subject,
                version.duckdb_version,
                platform,
                repository.url,
                response.status_code,
                download_url
            )
        )
    elseif response.status_code ~= 200 then
        error("checking " .. download_url .. " failed: HTTP " .. response.status_code)
    end
    local etag = response.headers["etag"]

    local archive_path = file.join_path(ctx.download_path, name .. ".duckdb_extension.gz")
    http.download_file({ url = download_url }, archive_path)

    local expected_digest = ext.etag_md5(etag)
    if expected_digest ~= nil then
        local actual_digest = md5_digest(archive_path)
        if actual_digest ~= expected_digest then
            error(
                "checksum mismatch for "
                    .. download_url
                    .. ": expected MD5 "
                    .. expected_digest
                    .. ", got "
                    .. actual_digest
            )
        end
    else
        log.debug("no MD5 digest in the ETag of", download_url, "so the download is not verified")
    end

    local extension_file = name .. ".duckdb_extension"
    local extension_path = file.join_path(ctx.install_path, extension_file)
    cmd.exec('mkdir -p "$DIR" && gzip -dc "$ARCHIVE" > "$TARGET"', {
        env = { DIR = ctx.install_path, ARCHIVE = archive_path, TARGET = extension_path },
    })
    local footer = ext.parse_footer(read_footer(extension_path))

    local info_path = extension_path .. ".info"
    local info = ext.repository_install_info(repository, name, version, platform, footer.extension_version, etag)
    write_file(info_path, ext.encode_install_info(info))

    local link_directory = file.join_path(root, version.duckdb_version, platform)
    local links = {
        { source = info_path, target = file.join_path(link_directory, extension_file .. ".info") },
        { source = extension_path, target = file.join_path(link_directory, extension_file) },
    }
    write_file(file.join_path(ctx.install_path, ext.LINK_RECORD_FILE), json.encode({ links = links }))

    cmd.exec('mkdir -p "$DIR"', { env = { DIR = link_directory } })
    for _, link in ipairs(links) do
        replace_with_symlink(link.source, link.target)
    end
    log.info(name, footer.extension_version, "linked into", link_directory)

    return {}
end
