# Root Integration Module API

## Purpose and Boundaries
Root integration module wires parser and runtime modules into executable workflows. It handles file loading, CLI argument parsing, startup/shutdown orchestration, and error reporting. It must not implement parser or runtime internals.

## Public Definitions
### Function
- `loadSdmlFile(filePath)`
  - Loads and resolves `.sdml` file content from disk.
  - Returns `{ absolutePath, source }`.

### Function
- `runSdmlFile(filePath, options = {})`
  - Integration entrypoint for parse -> validate -> runtime start flow.
  - Returns started `SdmlRuntime` instance.

### Function
- `parseArgs(argv)`
  - Parses CLI arguments for `sdml run`.
  - Validates host/port/thread and execution guard options.

### Function
- `main(argv = process.argv.slice(2))`
  - CLI process entrypoint used by `bin/sdml.js`.
  - Starts runtime and installs SIGINT/SIGTERM shutdown handlers.

## Side Effects and External Dependencies
- Reads SDML files from filesystem.
- Starts/stops network listener via `sdml-runtime`.
- Writes startup/shutdown/error output to stdout/stderr.

## Cross-Module Imports/Exports
- Imports `parseSdml` and `validateAst` from `modules/sdml-parser`.
- Imports `buildRuntime` from `modules/sdml-runtime`.
- Exports orchestration APIs for CLI and programmatic use.

## Backward Compatibility and Breaking Changes
- Initial integration API.
- Future changes should preserve `sdml run --file` contract and `runSdmlFile` behavior.
