--- Unit tests for lib/duckdb_ext.lua. Run from the repository root: `lua tests/run.lua`.

package.path = "./lib/?.lua;" .. package.path

local ext = require("duckdb_ext")

local tests = {}
local failures = 0

---@param name string
---@param fn fun()
local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

---@param actual any
---@param expected any
---@param label string|nil
local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", label or "value", tostring(expected), tostring(actual)), 2)
    end
end

---@param fn fun()
---@param pattern string
local function assert_error(fn, pattern)
    local ok, err = pcall(fn)
    if ok then
        error("expected an error matching '" .. pattern .. "'", 2)
    end
    if not tostring(err):find(pattern, 1, true) then
        error("expected an error matching '" .. pattern .. "', got: " .. tostring(err), 2)
    end
end

---@param name string
---@return string
local function read_fixture(name)
    local handle = assert(io.open("tests/fixtures/" .. name, "rb"))
    local content = handle:read("*a")
    handle:close()
    return content
end

test("validate_extension_name accepts DuckDB extension names", function()
    assert_equal(ext.validate_extension_name("postgres_scanner"), "postgres_scanner")
end)

test("validate_extension_name rejects path separators", function()
    assert_error(function()
        ext.validate_extension_name("../h3")
    end, "invalid DuckDB extension name")
end)

test("parse_version reads a plain DuckDB version", function()
    local version = ext.parse_version("2.0.0")
    assert_equal(version.duckdb_version, "v2.0.0")
    assert_equal(version.extension_version, nil)
end)

test("parse_version accepts a v prefix", function()
    assert_equal(ext.parse_version("v1.5.6").duckdb_version, "v1.5.6")
end)

test("parse_version reads a composite version", function()
    local version = ext.parse_version("2.0.0+v0.4.0")
    assert_equal(version.duckdb_version, "v2.0.0")
    assert_equal(version.extension_version, "v0.4.0")
end)

test("parse_version rejects an empty extension version", function()
    assert_error(function()
        ext.parse_version("2.0.0+")
    end, "extension version after '+'")
end)

test("parse_version rejects an extension version with a path separator", function()
    assert_error(function()
        ext.parse_version("2.0.0+../x")
    end, "extension version after '+'")
end)

test("parse_version rejects a partial DuckDB version", function()
    assert_error(function()
        ext.parse_version("2.0")
    end, "invalid version '2.0'")
end)

test("resolve_repository defaults to core over HTTPS", function()
    local repository = ext.resolve_repository(nil)
    assert_equal(repository.url, "http://extensions.duckdb.org")
    assert_equal(repository.download_url, "https://extensions.duckdb.org")
end)

test("resolve_repository resolves community", function()
    local repository = ext.resolve_repository("community")
    assert_equal(repository.url, "http://community-extensions.duckdb.org")
    assert_equal(repository.download_url, "https://community-extensions.duckdb.org")
end)

test("resolve_repository keeps a custom URL and removes trailing slashes", function()
    local repository = ext.resolve_repository("http://ext.example.com/repo/")
    assert_equal(repository.url, "http://ext.example.com/repo")
    assert_equal(repository.download_url, "http://ext.example.com/repo")
end)

test("resolve_repository rejects local paths", function()
    assert_error(function()
        ext.resolve_repository("/srv/duckdb-repo")
    end, "invalid repository '/srv/duckdb-repo'")
end)

test("platform maps mise platforms to DuckDB platforms", function()
    assert_equal(ext.platform("darwin", "arm64", nil), "osx_arm64")
    assert_equal(ext.platform("darwin", "amd64", nil), "osx_amd64")
    assert_equal(ext.platform("linux", "amd64", "gnu"), "linux_amd64")
    assert_equal(ext.platform("linux", "arm64", "musl"), "linux_arm64_musl")
end)

test("platform rejects Windows", function()
    assert_error(function()
        ext.platform("windows", "amd64", nil)
    end, "unsupported platform: windows/amd64")
end)

test("extension_url builds the unversioned URL", function()
    assert_equal(
        ext.extension_url("https://extensions.duckdb.org", "spatial", ext.parse_version("2.0.0"), "osx_arm64"),
        "https://extensions.duckdb.org/v2.0.0/osx_arm64/spatial.duckdb_extension.gz"
    )
end)

test("extension_url builds the versioned URL", function()
    assert_equal(
        ext.extension_url("https://extensions.duckdb.org", "delta", ext.parse_version("2.0.0+v0.4.0"), "osx_arm64"),
        "https://extensions.duckdb.org/delta/v0.4.0/v2.0.0/osx_arm64/delta.duckdb_extension.gz"
    )
end)

test("parse_footer reads an in-tree C++ extension", function()
    local footer = ext.parse_footer(read_fixture("parquet-v1.5.6-osx_arm64.footer"))
    assert_equal(footer.platform, "osx_arm64")
    assert_equal(footer.target_version, "v1.5.6")
    assert_equal(footer.extension_version, "v1.5.6")
    assert_equal(footer.abi_type, "CPP")
end)

test("parse_footer reads an out-of-tree C++ extension", function()
    local footer = ext.parse_footer(read_fixture("spatial-v1.5.6-osx_arm64.footer"))
    assert_equal(footer.extension_version, "04270fe")
    assert_equal(footer.target_version, "v1.5.6")
end)

test("parse_footer reads a C API extension", function()
    local footer = ext.parse_footer(read_fixture("h3-v2.0.0-osx_arm64.footer"))
    assert_equal(footer.extension_version, "v1.5.6")
    assert_equal(footer.target_version, "v1.2.0")
    assert_equal(footer.abi_type, "C_STRUCT")
end)

test("parse_footer rejects data without the magic value", function()
    assert_error(function()
        ext.parse_footer(string.rep("\0", 512))
    end, "not a DuckDB extension")
end)

test("parse_footer rejects data of the wrong size", function()
    assert_error(function()
        ext.parse_footer("short")
    end, "must be 512 bytes")
end)

test("encode_install_info matches DuckDB output for a plain ETag", function()
    local encoded = ext.encode_install_info({
        mode = ext.INSTALL_MODE_REPOSITORY,
        full_path = "http://extensions.duckdb.org/v1.5.6/osx_arm64/parquet.duckdb_extension.gz",
        repository_url = "http://extensions.duckdb.org",
        version = "v1.5.6",
        etag = '"11fdcfddcd63a1ed5caaabf78ff112b0"',
    })
    assert_equal(encoded, read_fixture("parquet-v1.5.6-osx_arm64.info"), "parquet info")
end)

test("encode_install_info matches DuckDB output for a multipart ETag", function()
    local encoded = ext.encode_install_info({
        mode = ext.INSTALL_MODE_REPOSITORY,
        full_path = "http://extensions.duckdb.org/v1.5.6/osx_arm64/spatial.duckdb_extension.gz",
        repository_url = "http://extensions.duckdb.org",
        version = "04270fe",
        etag = '"045d5574f93f0f6aae01bca31e8ca206-3"',
    })
    assert_equal(encoded, read_fixture("spatial-v1.5.6-osx_arm64.info"), "spatial info")
end)

test("encode_install_info matches DuckDB output from DuckDB v1.1.3", function()
    local encoded = ext.encode_install_info({
        mode = ext.INSTALL_MODE_REPOSITORY,
        full_path = "http://extensions.duckdb.org/v1.1.3/osx_arm64/arrow.duckdb_extension.gz",
        repository_url = "http://extensions.duckdb.org",
        version = "c50862c",
        etag = '"988aa394177e5f9a5fb7d054facb138a"',
    })
    assert_equal(encoded, read_fixture("arrow-v1.1.3-osx_arm64.info"), "arrow info")
end)

test("encode_install_info omits an empty ETag", function()
    local encoded = ext.encode_install_info({
        mode = ext.INSTALL_MODE_REPOSITORY,
        full_path = "u",
        repository_url = "r",
        version = "v",
        etag = nil,
    })
    assert_equal(encoded, "\100\0\1\101\0\1u\102\0\1r\103\0\1v\255\255")
end)

test("encode_install_info encodes long strings with a multi-byte length", function()
    local encoded = ext.encode_install_info({
        mode = ext.INSTALL_MODE_REPOSITORY,
        full_path = string.rep("x", 200),
        repository_url = "",
        version = "",
        etag = nil,
    })
    assert_equal(encoded:sub(1, 7), "\100\0\1\101\0\200\1")
    assert_equal(#encoded, 3 + 4 + 200 + 2)
end)

test("etag_md5 reads a quoted MD5 digest", function()
    assert_equal(ext.etag_md5('"11FDCFDDCD63A1ED5CAAABF78FF112B0"'), "11fdcfddcd63a1ed5caaabf78ff112b0")
end)

test("etag_md5 ignores multipart ETags", function()
    assert_equal(ext.etag_md5('"045d5574f93f0f6aae01bca31e8ca206-3"'), nil)
end)

test("etag_md5 ignores missing ETags", function()
    assert_equal(ext.etag_md5(nil), nil)
end)

test("extension_root expands the default directory", function()
    assert_equal(ext.extension_root(nil, "/home/me"), "/home/me/.duckdb/extensions")
end)

test("extension_root keeps an absolute path", function()
    assert_equal(ext.extension_root("/opt/duckdb", nil), "/opt/duckdb")
end)

test("extension_root rejects a relative path", function()
    assert_error(function()
        ext.extension_root("ext", "/home/me")
    end, "must be an absolute path")
end)

test("stable_duckdb_releases keeps stable releases in version order", function()
    local null = setmetatable({}, {})
    local releases = ext.stable_duckdb_releases({
        { tag_name = "v1.5.0", prerelease = false, draft = false, published_at = "2026-02-01T00:00:00Z" },
        { tag_name = "v1.4.10", prerelease = false, draft = false, published_at = "2026-03-01T00:00:00Z" },
        { tag_name = "v1.4.9", prerelease = false, draft = false, published_at = null },
        { tag_name = "v2.0.0-rc1", prerelease = false, draft = false, published_at = "2026-04-01T00:00:00Z" },
        { tag_name = "v2.0.0", prerelease = true, draft = false, published_at = "2026-04-02T00:00:00Z" },
        { tag_name = "v2.0.1", prerelease = false, draft = true, published_at = "2026-04-03T00:00:00Z" },
    })
    assert_equal(#releases, 3, "release count")
    assert_equal(releases[1].version, "1.4.9")
    assert_equal(releases[1].created_at, nil)
    assert_equal(releases[2].version, "1.4.10")
    assert_equal(releases[3].version, "1.5.0")
    assert_equal(releases[3].created_at, "2026-02-01T00:00:00Z")
end)

test("extension_names_from_stats removes metadata keys", function()
    local names = ext.extension_names_from_stats({ _last_update = "x", spatial = 1, h3 = 2 })
    assert_equal(#names, 2, "name count")
    assert_equal(names[1], "h3")
    assert_equal(names[2], "spatial")
end)

test("merge_catalogs prefers earlier catalogs", function()
    local tools = ext.merge_catalogs({
        { names = { "spatial", "arrow" }, description = "core" },
        { names = { "arrow", "h3" }, description = "community" },
    })
    assert_equal(#tools, 3, "tool count")
    assert_equal(tools[1].name, "arrow")
    assert_equal(tools[1].description, "core")
    assert_equal(tools[2].name, "h3")
    assert_equal(tools[2].description, "community")
end)

test("filter_tools matches substrings without case", function()
    local tools = ext.filter_tools({
        { name = "postgres_scanner", description = "" },
        { name = "spatial", description = "" },
    }, "Scan")
    assert_equal(#tools, 1, "tool count")
    assert_equal(tools[1].name, "postgres_scanner")
end)

for _, case in ipairs(tests) do
    local ok, err = pcall(case.fn)
    if ok then
        io.write("ok   ", case.name, "\n")
    else
        failures = failures + 1
        io.write("FAIL ", case.name, "\n     ", tostring(err), "\n")
    end
end

io.write(string.format("\n%d tests, %d failures\n", #tests, failures))
if failures > 0 then
    os.exit(1)
end
