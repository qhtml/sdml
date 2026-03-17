# sdml-parser Module API

## Purpose and Boundaries
This module parses SDML source into a structured AST and validates semantic correctness for the v1 language subset. It does not create HTTP servers, execute requests, or perform runtime sandbox operations.

## Public Definitions
### Function
- `parseSdml(source, filePath = '<inline>')`
  - Parses SDML text into AST rooted at `Server`.
  - Supports `headers { Header-Name { value } }` declarations at server and location scope.
  - Returns `{ ast }` on success.
  - Throws `SdmlSyntaxError` with file/line/column when syntax is invalid.

### Function
- `validateAst(ast)`
  - Validates semantic rules for listen/location blocks, route uniqueness, request parameter usage, scope visibility, assignment targets, and allowed call expressions.
  - Returns `{ ok: boolean, errors: string[] }`.

### Class
- `SdmlSyntaxError`
  - Structured parse exception with file, line, and column metadata.

## Parameter Semantics
- `source`: full SDML document string.
- `filePath`: optional source identity used in diagnostics.
- `ast`: server-level AST returned by `parseSdml`.

## Side Effects and External Dependencies
- Pure parsing/validation logic only.
- Uses local parser helpers and Node built-ins only; no network, no filesystem writes.

## Cross-Module Imports/Exports
- Exported for use by `sdml-runtime` and root integration CLI.
- No imports from other SDML modules.

## Backward Compatibility and Breaking Changes
- Initial public surface for v1.
- Future grammar expansions should preserve existing `parseSdml` and `validateAst` contracts.
