# sdml-runtime Module API

## Purpose and Boundaries
This module executes validated SDML AST as HTTP JSON endpoints. It handles route dispatch, request parameter mapping, restricted sandboxed expression execution, and runtime lifecycle. It does not parse SDML text.

## Public Definitions
### Function
- `buildRuntime(ast, options = {})`
  - Creates an `SdmlRuntime` from validated server AST.
  - Runtime options include host/port, response mode, worker-thread count, script timeout, and call-depth guard.

### Class
- `SdmlRuntime`
  - `start(): Promise<void>` starts the HTTP listener.
  - `stop(): Promise<void>` stops listener and worker threads.

## Parameter Semantics
- `ast`: validated server AST from `sdml-parser`.
- `options.host`: bind interface override.
- `options.port`: bind port override.
- `options.workerThreads`: number of worker threads for request execution.
- `options.scriptTimeoutMs`: vm execution timeout per expression.
- `options.maxCallDepth`: recursion guard for user-defined function calls.

## Side Effects and External Dependencies
- Opens and closes HTTP sockets.
- Optionally creates worker threads for parallel request processing.
- Uses `node:vm` to evaluate AST-derived expressions with restricted helpers only.
- Applies `headers { ... }` declarations from SDML to outgoing HTTP responses.

## Cross-Module Imports/Exports
- Consumes AST produced by `modules/sdml-parser`.
- Exported to root integration CLI for SDML service startup.

## Backward Compatibility and Breaking Changes
- Initial public runtime API.
- Future changes should preserve `buildRuntime` and `SdmlRuntime.start/stop` contracts.
