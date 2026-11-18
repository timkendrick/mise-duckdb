# mise-duckdb

A [mise](https://mise.jdx.dev) backend plugin that manages DuckDB extensions declaratively.

Install duck DuckDB extensions in `mise.toml` instead of running `INSTALL` by hand:

```toml
[tools]
"aqua:duckdb/duckdb" = "latest"
"duckdb:spatial" = "latest"
"duckdb:h3" = { version = "latest", repository = "community" }
```

Plugins are downloaded into DuckDB's extension directory for the right DuckDB version, ready to `LOAD`.

## Install the plugin

```sh
mise plugin install duckdb https://github.com/timkendrick/mise-duckdb
```

Each extension is then available as `duckdb:<extension>`, for example `duckdb:spatial` or `duckdb:httpfs`.

### The DuckDB CLI tool name

When this plugin is installed as `duckdb`, mise reads the bare tool name `duckdb` as a reference to the plugin, not to the DuckDB CLI.

Install the CLI with its full backend name instead:

```toml
[tools]
# Before
duckdb = "latest"

# After
"aqua:duckdb/duckdb" = "latest"
```

## Versions

DuckDB extension binaries work with one DuckDB version only. A DuckDB extension repository serves one build of each extension for each DuckDB version and platform. The plugin uses the DuckDB version as the mise version.

| mise version | Installs |
| --- | --- |
| `2.0.0` | The build of the extension that the repository serves for DuckDB 2.0.0 |
| `latest` | The build for the newest stable DuckDB release |
| `2.0.0+v0.4.0` | Version `v0.4.0` of the extension, built for DuckDB 2.0.0 |

`mise ls-remote duckdb:<extension>` lists every DuckDB release from the [release list on duckdb.org](https://duckdb.org/data/duckdb-releases.csv). The list does not check that the repository publishes the extension for each release. If it does not, install fails with an error such as:

```text
spatial is not published for DuckDB v2.1.0 on osx_arm64 in http://extensions.duckdb.org
```

### Install an extension for several DuckDB versions

Use a list of versions. Each version links into the extension directory of its DuckDB version.

```toml
[tools]
"duckdb:h3" = { version = ["1.5.6", "2.0.0"], repository = "community" }
```

### Published extension versions

Some repositories also publish fixed versions of an extension. DuckDB installs these with `INSTALL <extension> VERSION '<version>'`. To install one, add the extension version after a `+`:

```toml
[tools]
"duckdb:myext" = { version = "2.0.0+v0.4.0", repository = "https://ext.example.com" }
```

The plugin downloads only the published version. If the repository does not publish it, install fails. The core and community repositories do not publish fixed versions.

### Extension versions

Each extension also has its own version, such as `v1.5.6` or a short git hash such as `a3dbcd1781`. The plugin reads this version from the downloaded extension. DuckDB shows it in the `extension_version` column of `duckdb_extensions()`.

## Tool options

| Option | Default | Description |
| --- | --- | --- |
| `repository` | `core` | `core`, `core_nightly`, `community`, or the `http://` or `https://` URL of a custom repository |
| `extension_directory` | `~/.duckdb/extensions` | The DuckDB extension directory. Set it if you change DuckDB's `extension_directory` setting. The plugin adds the DuckDB version and platform directories below it. |

A custom repository must use the directory layout of the DuckDB repositories. For example, for DuckDB 2.0.0 on macOS on Apple silicon:

```text
https://ext.example.com/v2.0.0/osx_arm64/myext.duckdb_extension.gz
https://ext.example.com/myext/v0.4.0/v2.0.0/osx_arm64/myext.duckdb_extension.gz
```

Local directories are not supported as repositories.

## How install works

For `"duckdb:spatial" = "2.0.0"` on macOS on Apple silicon, install does these steps:

1. Download `https://extensions.duckdb.org/v2.0.0/osx_arm64/spatial.duckdb_extension.gz`. The plugin uses HTTPS for the core, core_nightly and community repositories.
2. If the ETag of the download is an MD5 digest, compare it with the MD5 digest of the download.
3. Decompress the extension into the mise install directory, such as `~/.local/share/mise/installs/duckdb-spatial/2.0.0/`.
4. Read the extension version from the extension.
5. Write the install info file `spatial.duckdb_extension.info` next to the extension. This file has the same content as the file that DuckDB writes for `INSTALL spatial`. It records the repository, so DuckDB shows it in `duckdb_extensions()`, uses it for `UPDATE EXTENSIONS`, and selects the keys that verify the signature of the extension.
6. Link both files into `~/.duckdb/extensions/v2.0.0/osx_arm64/`. Install replaces files that are already there.

The plugin does not verify extension signatures. DuckDB verifies the signature each time it loads an extension.

## How uninstall works

`mise uninstall` removes the links in the DuckDB extension directory, but only if they still point into the mise install directory. If DuckDB replaced a link, for example after `FORCE INSTALL` or `UPDATE EXTENSIONS`, uninstall keeps the file that DuckDB wrote.

## Find extensions

`mise search duckdb:` and shell completion list the extensions in the core and community repositories:

- Core extension names come from the `duckdb` CLI on `PATH`. If the CLI is not available, they come from the core repository download statistics.
- Community extension names come from the community repository download statistics.

## Platforms

The plugin supports macOS and Linux on x86-64 and ARM64, including Linux with musl. It needs `gzip`, `readlink`, and `md5` on macOS or `md5sum` on Linux. Windows is not supported.

## Limitations

- **Rebuilt extensions:** a repository can replace the build of an extension for a DuckDB version. mise does not detect this, because the DuckDB version does not change. To get the new build, run `mise install --force duckdb:<extension>`, or run `UPDATE EXTENSIONS` in DuckDB.
- **Upgrades remove old builds:** for a tool with version `latest`, `mise upgrade` installs the build for the new DuckDB release and removes the build for the old release. A DuckDB CLI of the old version then cannot find the extension. Upgrade the DuckDB CLI at the same time.
- **Built-in extensions:** the DuckDB CLI includes some extensions, such as `parquet`, `json` and `icu`. The plugin installs these, but DuckDB uses its built-in copy.
- **Two versions for one DuckDB version:** if you configure both `2.0.0` and `2.0.0+v0.4.0` for one extension, both link to the same files. The last install wins.

## Development

Link your working copy:

```sh
mise plugin link --force duckdb .
```

| Task | Description |
| --- | --- |
| `mise run test-unit` | Run the unit tests for the helpers in `lib/` |
| `mise run test` | Install, load and uninstall extensions in an isolated mise environment |
| `mise run lint` | Check formatting, types and GitHub Actions workflows |
| `mise run ci` | Run all checks |

The unit tests compare the install info files that the plugin writes with files that DuckDB wrote. These files are in `tests/fixtures/`.

## License

MIT
