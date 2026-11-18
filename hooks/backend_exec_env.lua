--- DuckDB finds extensions in its extension directory, so installed extensions need no environment variables.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv
--- @param _ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(_ctx)
    return { env_vars = {} }
end
