# AGENT INSTRUCTIONS
This document is the authoritative process for running a multi-agent, multi-module workflow with `wheel.sh`. Read all sections before doing any work.

## Non-Negotiable Rules
- Follow this process exactly. Details are part of correctness.
- Always split work into modules. A module should represent one logical abstract type or subsystem and be as dependency-free as practical.
- Always switch into the target module directory before reading specs, making plans, or editing code for that module.
- Never change one module while context is centered in a different module.
- Keep top-level/main code focused on module wiring, orchestration, input/output handling, and event loop glue.
- Do not reinvent existing functionality. Query `WHEEL.db` first and reuse existing definitions when possible using ./wheel.sh helpers
- Prefer many small modules over large mixed files to reduce context rot.

## Required Files Per Module
Each module directory must contain:
- `AGENTS.md` (this policy)
- `wheel.sh`
- `wheel-scan.sh`
- `README-WHEEL.md`
- `README-WHEEL-SCAN.md`
- `MODULE-API.md`
- `WHEEL.db` (auto-created by `./wheel.sh` if missing)

`MODULE-API.md` must stay current and document all externally consumable definitions in that module as well as all feature sets / use cases 

## Drop-In Bootstrap for New Projects
When these files are copied into a brand new project, do this before agent work:
1. Identify initial module boundaries and create one directory per module.
2. Copy required module files into each module directory.
3. Run module bootstrap in each module (`chmod`, `./wheel.sh --help`, schema checks).
4. Create or verify module registry table:
   - `./wheel.sh raw "CREATE TABLE IF NOT EXISTS modules (id INTEGER PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, description TEXT, dependencies TEXT);"`
5. Register each module in `modules`:
   - `./wheel.sh insert modules name=<module_name> path=<module_path> description=<purpose> dependencies=<comma_separated_module_names_or_empty>`
6. Create initial `MODULE-API.md` stubs for every module.
7. Treat root/main as integration-only module (wiring and orchestration), not feature implementation.

## Module Bootstrap (Mandatory)
Run this sequence inside every module directory before work starts:
1. Ensure required files exist (copy from project template/root if needed).
2. Ensure executables are executable:
   - `chmod +x wheel.sh wheel-scan.sh`
3. Initialize database:
   - `./wheel.sh --help >/dev/null`
4. Verify schema access:
   - `./wheel.sh describe files --schema`
   - `./wheel.sh describe defs --schema`
   - `./wheel.sh describe spec_memory --schema`

If `sqlite3` is unavailable, stop this workflow and inform the user that the system requires `sqlite3` and a Linux-like shell environment.

## Project-Level Multi-Agent Orchestration
Use four explicit roles. Do not blend responsibilities.

### Specification manager
Purpose
- determine if the user's prompt adds any additional requirements or specifications to a specific module. If so, cross-check existing specifications using ./wheel.sh spec helpers for that module and determine if any conflicts arise from adding the additional specifications. In the event of a conflict, prompt the user to choose between specifications
- Determine if the user's prompt invalidates or cancels any specifications based on wheel.sh spec data, at which point confirm with the user before removing / changing any existing specifications one specification at a time.

### CoordinatorAgent Contract
Purpose:
- Select active module and route work to RequirementsAgent/SolverAgent.
- Enforce one active write-owner agent per module at a time.
- Track module dependencies via `modules` table and `MODULE-API.md` using `wheel.sh`

Hard constraints:
- MUST NOT write code for module internals.
- MUST NOT bypass completion gates.
- MUST ensure module handoff packet is complete before solver execution.
- MUST create an informed plan that conforms to all specifications for any module that is to be modified as long as the specifications are influenced by or have influence over some part of the module which will be modified / added / removed.
- Job is to determine scope of work to be done and create concrete plan and TODO entries in wheel.sh which describe the different steps and tasks which are to be done by the SolverAgent.

Mandatory handoff packet from RequirementsAgent to SolverAgent:
- Active module name and absolute path.
- Completion-gate query outputs proving zero open rows.
- Approved specification rows (`spec_memory`) for that module scope.
- Open dependency rows (if any) and explicit blocked/unblocked status.
- Reuse evidence: key `wheel.sh search/query` results used to avoid duplicate implementations.

### SolverAgent Contract
Purpose:
- Implement code only if implemented code conforms to all relevant approved `spec_memory` rows for one active module at a time.
- Update module metadata (`files`, `defs`, `api`, `deps`, `refs`, `changes`, `todo`, `modules`) immediately after each change using `wheel.sh`.
- Reads TO DO list from ./wheel.sh to determine what work is to be done and then completes all tasks in the to do list while ensuring to stay within all specifications which have not been removed or invalidated by user confirmation.
- Remove or mark as complete TO DO list items as you finish them. 
- All metadata added to wheel.sh must contain descriptions that explain what the thing is, a general use guideline, and the purpose of the thing added. More details is better but limit to one paragraph.

Hard constraints:
- MUST conform to relevant `spec_memory` when generating solution/code.
- MUST NOT generate solution/code when completion gate is closed.
- MUST NOT create or edit `spec_memory` rows (except status changes explicitly approved by RequirementsAgent output policy, if your environment combines roles).
- MUST treat `spec_memory` as source of truth; conversation memory is advisory only.
- MUST NOT perform cross-module edits in one solver context unless dependencies exist involving changes across multiple modules for a single implementation. 

## Completion Gate (Global Rule)
If any row exists with `kind='question' AND status='open'`, solution generation is forbidden for that module.

Required gate checks:
- Open questions:
  - `./wheel.sh query spec_memory --where "kind='question' AND status='open'" --count`
- Open requirements/decisions/constraints:
  - `./wheel.sh query spec_memory --where "kind IN ('requirement','decision','constraint') AND status='open'" --count`

RequirementsAgent may escalate to SolverAgent only when both counts are zero.

## Requirements-First Spec Memory Rules
All authoritative requirement data must be persisted in `spec_memory`.

### Input Classification
- Each distinct requirement statement: one row, `kind='requirement'`.
- Each explicit constraint: one row, `kind='constraint'`.
- Each explicit choice: one row, `kind='decision'`.
- Each unresolved ambiguity/question: one row, `kind='question'`, `status='open'`.
- Non-requirement context: one row, `kind='note'`.
- One user message with multiple distinct items requires multiple rows.

### Row Structure and Status
- `path`: dot-delimited scope (for example `module.auth.login`).
- `parent_id`: immediate parent scope id or `NULL`.
- `branch`: `NULL` unless user explicitly names a branch.
- `depends_on`: ids that must be resolved first.
- `supersedes_id`: prior row id when replacing a prior statement.
- Rows are append-only except status updates; do not delete rows.

Recommended statuses:
- `open`: unresolved or awaiting approval.
- `approved`: accepted and ready for solver consumption.
- `resolved`: answered question.
- `superseded`: replaced by a newer row.

### Spec Memory I/O Constraints
- Use only `./wheel.sh query/insert/update` for `spec_memory` reads/writes.
- Direct `sqlite3` access is forbidden for spec lifecycle operations.
- Partial answers keep original rows open and create follow-up question rows for missing details.

## WHEEL.db Schema Expectations
Use `./wheel.sh` for all interactions. Default DB file is `WHEEL.db`.

Core tables expected in each module:
- `files` (`id`, `relpath`, `description`)
- `defs` (`id`, `file_id`, `type`, `signature`, `parameters`, `description`)
- `refs` (`id`, `def_id`, `reference_def_id`)
- `todo` (`id`, `change_id`, `change_defs_id`, `change_files_id`, `description`)
- `spec_memory` (`id`, `path`, `parent_id`, `kind`, `status`, `content`, `depends_on`, `branch`, `supersedes_id`, `created_at`)
- `api` (`id`, `file_id`, `def_id`, `signature`, `description`)
- `deps` (`id`, `def_id`, `file_id`, `dep_def_id`, `dep_file_id`, `description`)

Module-registry table for cross-module mapping:
- `modules` (`id`, `name`, `path`, `description`, `dependencies`)

If `modules` table is missing, create it once per module DB:
- `./wheel.sh raw "CREATE TABLE IF NOT EXISTS modules (id INTEGER PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, description TEXT, dependencies TEXT);"`

## Required wheel.sh Usage Patterns
- Prefer `./wheel.sh` queries over bulk file reading.
- Before coding, search for reusable definitions:
  - `./wheel.sh search <term> --table defs --table files`
  - Use semantic ranking when keyword match is weak:
  - `./wheel.sh search --table defs --semantic "<intent text>" --semantic-top 30 --semantic-min-score 0.05`
- Use table aliases for faster navigation:
  - `api(s)` commands map to `api`
  - `dep(s)` commands map to `deps`
  - `module(s)` commands map to `modules`
- Add/update metadata whenever public code changes:
  - `files`, `defs`, `refs`, `changes`, and `todo` must reflect current module state.
- When reporting status/review/approval, cite `wheel.sh` output, not memory.

## MODULE-API.md Contract (Per Module)
`MODULE-API.md` must be minimal but complete so a different agent can consume the module without opening all source files.

Include:
1. Module purpose and boundaries.
2. Public definitions grouped by type (class/function/signal/property/command).
3. Signatures and parameter semantics.
4. Side effects and external dependencies.
5. Cross-module imports/exports.
6. Backward-compatibility notes and breaking-change history.

Update `MODULE-API.md` immediately when public API changes.

## Cross-Module Rules
- Never edit two modules in one solver context.
- Read other modules through their `MODULE-API.md` first, then targeted `wheel.sh query` calls.
- Record inter-module dependencies in `modules.dependencies`.
- If a change requires another module:
  - finish and document current module,
  - switch directory/context,
  - start a separate requirements/spec cycle for the other module.

## README Files (Read Before Work)
- `README-WHEEL.md`: operational guide for `wheel.sh`, schema, and workflows.
- `README-WHEEL-SCAN.md`: scanner behavior and extraction pipeline.
- Read these before changing workflow logic.

## Prohibited Actions
- Do not load `WHEEL.sql` into context; use `wheel.sh` queries.
- Do not add `wheel.sh` or `wheel-scan.sh` entries to `files/defs` unless user explicitly requests editing those scripts.
- Do not skip completion gate checks.
- Do not run cross-module code edits from the wrong module directory.

## Quality Checklist (Must Pass Before Handoff)
1. Active module directory confirmed.
2. Completion gate status confirmed with `wheel.sh` queries.
3. Reuse scan completed (`search/query` against `defs/files/refs`).
4. `todo` updated (even if non-trivial change).
5. `files/defs/refs` metadata updated for public code changes.
6. `MODULE-API.md` updated and consistent with code.
7. Main module changes limited to integration wiring.

## General Coding Guidance
- Break large problems into specific steps.
- Prefer existing helpers, base classes, and established abstractions before adding new code paths.
- Keep code compact, readable, and scalable.
- Favor small cohesive modules over monolithic files.
- Do multiple scans using wheel.sh for different implementations and briefly analyze if any of them have the potential to be reused for the specific code that is being generated before generating anything
