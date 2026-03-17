#!/usr/bin/env bash
#set -euo pipefail

PROG="${0##*/}"
DB_PATH="WHEEL.db"
PARAM_PREF="auto"
PARAM_STATE=""
VERBOSE=0
SQLITE_BUSY_TIMEOUT_MS="${WHEEL_SQLITE_BUSY_TIMEOUT_MS:-60000}"
SQLITE_PRAGMA_DB_PATH=""

usage() {
  cat <<'USAGE'
Usage:
  wheel.sh [GLOBAL OPTIONS] query    [TABLE] [COLUMN ...] [QUERY OPTIONS]
  wheel.sh [GLOBAL OPTIONS] search   [TERMS...] [--table TABLE] [query opts]
  wheel.sh [GLOBAL OPTIONS] insert   TABLE key=value [...]
  wheel.sh [GLOBAL OPTIONS] update   TABLE --set col=value [--set col=value ...] [--id ID | --where SQL]
  wheel.sh [GLOBAL OPTIONS] delete   TABLE [--id ID | --where SQL]
  wheel.sh [GLOBAL OPTIONS] describe TABLE [--id ID] [--schema]
  wheel.sh [GLOBAL OPTIONS] plan     CHANGE_ID
  wheel.sh [GLOBAL OPTIONS] raw      [SQL]
  wheel.sh [GLOBAL OPTIONS] modules  SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] module   SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] deps     SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] dep      SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] apis     SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] api      SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] todo     SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] changes  SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] files    SUBCOMMAND [ARGS]
  wheel.sh [GLOBAL OPTIONS] defs     SUBCOMMAND [ARGS]

Global options:
  --database PATH     Use the given SQLite database (default WHEEL.db)
  --force-params      Force use of sqlite3 .parameter bindings where supported
  --no-params         Disable use of sqlite3 .parameter bindings
  --verbose           Emit debug logging to stderr
  -h, --help          Show this message

Todo shortcuts:
  todo list
      List todo items (id, change id, linked file/definition, description).
  todo add --description=TEXT [--file=REL|--file_id=ID] [--def=SIG|--def_id=ID] [--change-id=ID]
      Adds a todo entry, resolving file/def ids and change links automatically when possible.
      Optional --change-def-id/--change-file-id may be supplied to target specific change rows.
  todo del TODO_ID
      Removes the matching todo entry.
  todo search TERM... [--file=REL|--file_id=ID] [--def=SIG|--def_id=ID] [--change-id=ID]
      AND-search across description/signature/path with optional file or definition filters.

Change shortcuts:
  changes list
      Show all change rows (id, title, status, context).
  changes add --title=TEXT --status=STATUS [--context=TEXT]
      Create a new change entry; context is optional.
  changes update CHANGE_ID [--title=TEXT] [--status=STATUS] [--context=TEXT]
      Update one or more fields on the selected change.

File shortcuts:
  files list
      List all files with ids and descriptions ordered by relpath.
  files search TERM...
      Keyword search (AND) over file paths and descriptions.
  files add --relpath=PATH|--file=PATH [--description=TEXT]
      Insert a new file row; description defaults to NULL when omitted.
  files del [--file_id=ID | --file=PATH]
      Delete a file row by id or matching relpath.
  files update [--file_id=ID | --file=PATH] [--relpath=PATH] [--description=TEXT]
      Update file metadata; supply whichever fields you want to change.

Definition shortcuts:
  defs list [--file=PATH | --file_id=ID]
      List definitions joined to their files, optionally filtered by file.
  defs search TERM... [--file=PATH]
      Keyword search (AND) across definition signatures, descriptions, parameters, types, or file paths.
  defs add --file=PATH|--file_id=ID --type=TYPE [--signature=SIG] [--parameters=TEXT] [--description=TEXT]
      Insert a definition for the selected file; non-type fields are optional.
  defs del [--def_id=ID | --def=SIG [--file=PATH|--file_id=ID]]
      Remove a definition either by id or by signature (optionally scoping to a file).
  defs update [--def_id=ID | --def=SIG [--file=PATH|--file_id=ID]]
              [--type=TYPE] [--signature=SIG] [--parameters=TEXT] [--description=TEXT]
              [--new_file=PATH|--new_file_id=ID]
      Update one or more definition fields, including moving the definition to another file.

API shortcuts:
  apis/api list [--file=PATH | --file_id=ID]
      List API rows (linked to files and optional defs).
  apis/api search TERM... [--file=PATH]
      Search API signatures/descriptions.
  apis/api add --file=PATH|--file_id=ID [--def=SIG|--def_id=ID] --signature=SIG [--description=TEXT]
      Add an API row.
  apis/api del [--id=ID | --signature=SIG [--file=PATH|--file_id=ID]]
      Delete one API row.
  apis/api update [--id=ID | --signature-filter=SIG [--file=PATH|--file_id=ID]] ...
      Update API row fields.

Dependency shortcuts:
  deps/dep list [--def_id=ID] [--file_id=ID] [--dep_def_id=ID] [--dep_file_id=ID]
      List dependency rows.
  deps/dep search TERM...
      Search dependency links/descriptions.
  deps/dep add [--def=SIG|--def_id=ID] [--file=PATH|--file_id=ID] [--dep_def=SIG|--dep_def_id=ID] [--dep_file=PATH|--dep_file_id=ID] [--description=TEXT]
      Add a dependency row.
  deps/dep del --id=ID
      Delete one dependency row.
  deps/dep update --id=ID [...]
      Update dependency row fields.

Module shortcuts:
  module ... (alias for modules)
      `module` is a command alias for the `modules` shortcuts below.
  modules list
      List registered modules (id, name, path, description, dependencies).
  modules search TERM...
      Search module registry rows by name/path/description/dependencies.
  modules add --name=NAME --path=PATH [--description=TEXT] [--dependencies=CSV]
      Register a module; path may be module directory or direct DB file path.
  modules update [--id=ID|--name=NAME|--path=PATH] [--new-name=NAME] [--new-path=PATH] [--description=TEXT] [--dependencies=CSV]
      Update module metadata for one selected module.
  modules del [--id=ID|--name=NAME|--path=PATH]
      Remove one module row.
  modules query [--module PATTERN]... [--strict] [QUERY ARGS...]
      Run `query` against each matched module database.
  modules xsearch [--module PATTERN]... [--strict] [SEARCH ARGS...]
      Run `search` across matched module databases.

Notes:
  • Invoking wheel.sh with only legacy query flags still works (query mode is default).
  • Provide the table to `query` either with --table or as the first positional argument (e.g. `query files`).
  • Singular aliases such as file/def/api/dep/ref/change automatically resolve to canonical tables.
  • LIKE filters wrap values in %...% unless you provide %/_ yourself.
  • `search` spreads the terms across the most relevant columns for each table.
  • `search` semantic flags: --semantic TEXT [--semantic-top N] [--semantic-min-score F].
  • `modules query/xsearch` accept module wildcards (e.g. core*, */auth*).
  • `raw` with no SQL launches an interactive sqlite3 shell.
  • Set WHEEL_SQLITE_BUSY_TIMEOUT_MS (default 60000) to tune sqlite lock wait time.

Spec memory:
  spec_memory is created in the schema initialization block in ensure_db.
  Unresolved requirements are rows where kind='question' AND status='open'.
  Insert new spec rows with the insert command; required columns are path, kind, status, content.
  Optional spec columns are parent_id, depends_on, branch, supersedes_id, created_at.
  Update status with update on spec_memory; never delete spec_memory rows.
USAGE
}

fatal() { echo "$PROG: $*" >&2; exit 1; }
warn() { echo "$PROG: warning: $*" >&2; }

debug() {
  if [[ $VERBOSE -eq 1 ]]; then
    echo "[$PROG] $*" >&2
  fi
}

sqlite3() {
  command sqlite3 -cmd ".timeout $SQLITE_BUSY_TIMEOUT_MS" "$@"
}

resolve_sql_seed_path() {
  local db_path="$1"
  local dir="."
  local name="$db_path"

  if [[ "$db_path" == */* ]]; then
    dir="${db_path%/*}"
    name="${db_path##*/}"
    [[ -n "$dir" ]] || dir="."
  fi

  if [[ -z "$name" ]]; then
    fatal "invalid database path: $db_path"
  fi

  local base="$name"
  if [[ "$name" == *.* ]]; then
    base="${name%.*}"
    if [[ -z "$base" ]]; then
      base="$name"
    fi
  fi

  if [[ "$dir" == "." || -z "$dir" ]]; then
    printf './%s.sql' "$base"
  else
    printf '%s/%s.sql' "$dir" "$base"
  fi
}

db_lock_path() {
  local db_path="$1"
  printf '%s.lock' "$db_path"
}

with_exclusive_lock() {
  local lock_file="$1"
  shift

  local lock_fd=""
  exec {lock_fd}> "$lock_file"
  if type -P flock >/dev/null 2>&1; then
    flock -x "$lock_fd"
  fi

  local rc=0
  if "$@"; then
    rc=0
  else
    rc=$?
  fi

  if type -P flock >/dev/null 2>&1; then
    flock -u "$lock_fd" || true
  fi
  exec {lock_fd}>&-
  return $rc
}

ensure_db_pragmas() {
  if [[ "$SQLITE_PRAGMA_DB_PATH" == "$DB_PATH" ]]; then
    return
  fi
  sqlite3 "$DB_PATH" <<'SQL' >/dev/null 2>&1 || true
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
SQL
  SQLITE_PRAGMA_DB_PATH="$DB_PATH"
}

ensure_db_locked() {
  local sql_seed
  local target_db="./WHEEL.db"
  local created_db=0

  if [[ "$DB_PATH" != "WHEEL.db" && "$DB_PATH" != "./WHEEL.db" ]]; then
    target_db="$DB_PATH"
  fi

  if [[ -f "$target_db" ]]; then
    return
  fi

  sql_seed="$(resolve_sql_seed_path "$target_db")"

  if [[ -f "$sql_seed" ]]; then
    debug "bootstrapping database from $sql_seed"
    sqlite3 "$target_db" < "$sql_seed" || fatal "failed to bootstrap database from $sql_seed"
    created_db=1
  else
    debug "initializing new database schema at $target_db"
    sqlite3 "$target_db" <<'SQL' || fatal "failed to initialize blank database schema"
BEGIN;
CREATE TABLE IF NOT EXISTS files (
  id INTEGER PRIMARY KEY,
  relpath TEXT UNIQUE NOT NULL,
  description TEXT
);
CREATE TABLE IF NOT EXISTS defs (
  id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL,
  type TEXT NOT NULL,
  signature TEXT,
  parameters TEXT,
  description TEXT,
  FOREIGN KEY(file_id) REFERENCES files(id)
);
CREATE TABLE IF NOT EXISTS api (
  id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL,
  def_id INTEGER,
  signature TEXT NOT NULL,
  description TEXT,
  FOREIGN KEY(file_id) REFERENCES files(id),
  FOREIGN KEY(def_id) REFERENCES defs(id)
);
CREATE INDEX IF NOT EXISTS idx_api_file_id ON api(file_id);
CREATE INDEX IF NOT EXISTS idx_api_def_id ON api(def_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_api_file_signature ON api(file_id, signature);
CREATE TABLE IF NOT EXISTS refs (
  id INTEGER PRIMARY KEY,
  def_id INTEGER NOT NULL,
  reference_def_id INTEGER NOT NULL,
  FOREIGN KEY(def_id) REFERENCES defs(id),
  FOREIGN KEY(reference_def_id) REFERENCES defs(id)
);
CREATE TABLE IF NOT EXISTS changes (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  context TEXT,
  status TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS change_files (
  id INTEGER PRIMARY KEY,
  change_id INTEGER NOT NULL,
  file_id INTEGER NOT NULL,
  FOREIGN KEY(change_id) REFERENCES changes(id),
  FOREIGN KEY(file_id) REFERENCES files(id)
);
CREATE TABLE IF NOT EXISTS change_defs (
  id INTEGER PRIMARY KEY,
  change_id INTEGER NOT NULL,
  file_id INTEGER NOT NULL,
  def_id INTEGER,
  description TEXT,
  FOREIGN KEY(change_id) REFERENCES changes(id),
  FOREIGN KEY(file_id) REFERENCES files(id),
  FOREIGN KEY(def_id) REFERENCES defs(id)
);
CREATE TABLE IF NOT EXISTS todo (
  id INTEGER PRIMARY KEY,
  change_id INTEGER NOT NULL,
  change_defs_id INTEGER,
  change_files_id INTEGER,
  description TEXT NOT NULL,
  FOREIGN KEY(change_id) REFERENCES changes(id),
  FOREIGN KEY(change_defs_id) REFERENCES change_defs(id),
  FOREIGN KEY(change_files_id) REFERENCES change_files(id)
);
CREATE TABLE IF NOT EXISTS spec_memory (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL,
  parent_id INTEGER,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  content TEXT NOT NULL,
  depends_on TEXT,
  branch TEXT,
  supersedes_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY(parent_id) REFERENCES spec_memory(id),
  FOREIGN KEY(supersedes_id) REFERENCES spec_memory(id)
);
CREATE TABLE IF NOT EXISTS modules (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  description TEXT,
  dependencies TEXT
);
CREATE TABLE IF NOT EXISTS deps (
  id INTEGER PRIMARY KEY,
  def_id INTEGER,
  file_id INTEGER,
  dep_def_id INTEGER,
  dep_file_id INTEGER,
  description TEXT,
  FOREIGN KEY(def_id) REFERENCES defs(id),
  FOREIGN KEY(file_id) REFERENCES files(id),
  FOREIGN KEY(dep_def_id) REFERENCES defs(id),
  FOREIGN KEY(dep_file_id) REFERENCES files(id)
);
CREATE INDEX IF NOT EXISTS idx_deps_def_id ON deps(def_id);
CREATE INDEX IF NOT EXISTS idx_deps_file_id ON deps(file_id);
CREATE INDEX IF NOT EXISTS idx_deps_dep_def_id ON deps(dep_def_id);
CREATE INDEX IF NOT EXISTS idx_deps_dep_file_id ON deps(dep_file_id);
COMMIT;
SQL

    created_db=1

    debug "dumping freshly initialized database schema to $sql_seed"
    sqlite3 "$target_db" .dump > "$sql_seed" || fatal "failed to dump database to $sql_seed"
  fi

  if [[ $created_db -eq 1 ]]; then
    run_bootstrap_scan "$target_db"
  fi
}

ensure_db() {
  if ! type -P sqlite3 >/dev/null 2>&1; then
    fatal "database not available, sqlite3 not in PATH"
  fi

  if [[ -f "$DB_PATH" ]]; then
    ensure_db_pragmas
    ensure_schema_compat
    return
  fi

  local lock_file
  lock_file="$(db_lock_path "$DB_PATH")"
  with_exclusive_lock "$lock_file" ensure_db_locked
  ensure_db_pragmas
  ensure_schema_compat
}

ensure_schema_compat_locked() {
  local has_modules
  local has_api
  local has_deps
  local needs_update=0
  has_modules="$(sqlite3 -batch -noheader "$DB_PATH" "SELECT COUNT(1) FROM sqlite_master WHERE type='table' AND name='modules';")" || has_modules="0"
  has_api="$(sqlite3 -batch -noheader "$DB_PATH" "SELECT COUNT(1) FROM sqlite_master WHERE type='table' AND name='api';")" || has_api="0"
  has_deps="$(sqlite3 -batch -noheader "$DB_PATH" "SELECT COUNT(1) FROM sqlite_master WHERE type='table' AND name='deps';")" || has_deps="0"
  if [[ "$has_modules" == "0" || "$has_api" == "0" || "$has_deps" == "0" ]]; then
    debug "adding missing compatibility tables to existing database"
    sqlite3 "$DB_PATH" <<'SQL' || fatal "failed to add compatibility tables"
BEGIN;
CREATE TABLE IF NOT EXISTS modules (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  description TEXT,
  dependencies TEXT
);
CREATE TABLE IF NOT EXISTS api (
  id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL,
  def_id INTEGER,
  signature TEXT NOT NULL,
  description TEXT,
  FOREIGN KEY(file_id) REFERENCES files(id),
  FOREIGN KEY(def_id) REFERENCES defs(id)
);
CREATE INDEX IF NOT EXISTS idx_api_file_id ON api(file_id);
CREATE INDEX IF NOT EXISTS idx_api_def_id ON api(def_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_api_file_signature ON api(file_id, signature);
CREATE TABLE IF NOT EXISTS deps (
  id INTEGER PRIMARY KEY,
  def_id INTEGER,
  file_id INTEGER,
  dep_def_id INTEGER,
  dep_file_id INTEGER,
  description TEXT,
  FOREIGN KEY(def_id) REFERENCES defs(id),
  FOREIGN KEY(file_id) REFERENCES files(id),
  FOREIGN KEY(dep_def_id) REFERENCES defs(id),
  FOREIGN KEY(dep_file_id) REFERENCES files(id)
);
CREATE INDEX IF NOT EXISTS idx_deps_def_id ON deps(def_id);
CREATE INDEX IF NOT EXISTS idx_deps_file_id ON deps(file_id);
CREATE INDEX IF NOT EXISTS idx_deps_dep_def_id ON deps(dep_def_id);
CREATE INDEX IF NOT EXISTS idx_deps_dep_file_id ON deps(dep_file_id);
COMMIT;
SQL
    needs_update=1
  fi
  if [[ "$needs_update" == "1" ]]; then
    refresh_sql_dump
  fi
}

ensure_schema_compat() {
  local lock_file
  lock_file="$(db_lock_path "$DB_PATH")"
  with_exclusive_lock "$lock_file" ensure_schema_compat_locked
}

run_bootstrap_scan() {
  local target_db="$1"
  if [[ "${WHEEL_SKIP_AUTO_SCAN:-0}" == "1" ]]; then
    debug "skip bootstrap scan because WHEEL_SKIP_AUTO_SCAN=1"
    return
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local scan_script="$script_dir/wheel-scan.sh"
  if [[ ! -f "$scan_script" ]]; then
    debug "wheel-scan.sh not found; skipping bootstrap scan"
    return
  fi

  local scan_root="$PWD"
  debug "bootstrapping database with $scan_script"
  if [[ -x "$scan_script" ]]; then
    WHEEL_DB_PATH="$target_db" "$scan_script" --path "$scan_root" >/dev/null
  else
    WHEEL_DB_PATH="$target_db" bash "$scan_script" --path "$scan_root" >/dev/null
  fi
}

refresh_sql_dump() {
  if ! type -P sqlite3 >/dev/null 2>&1; then
    debug "skip dump refresh: sqlite3 not available"
    return
  fi

  local dump_target="$(resolve_sql_seed_path "$DB_PATH")"
  local source_db="$DB_PATH"

  debug "refreshing $dump_target from $source_db"
  sqlite3 "$source_db" .dump > "$dump_target" || fatal "failed to dump database to $dump_target"
}

run_mutation_sql_locked() {
  local sql="$1"
  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
$sql
EOF
  refresh_sql_dump
}

run_mutation_sql() {
  local sql="$1"
  ensure_db
  local lock_file
  lock_file="$(db_lock_path "$DB_PATH")"
  with_exclusive_lock "$lock_file" run_mutation_sql_locked "$sql"
}

run_query_output() {
  local db="$1"
  local mode="${2:-column}"
  local sql="$3"

  case "$mode" in
    column|table)
      sqlite3 "$db" <<EOF
.timer off
.headers on
.mode column
$sql
EOF
      ;;
    tabs|tsv)
      sqlite3 "$db" <<EOF
.timer off
.headers on
.mode tabs
$sql
EOF
      ;;
    csv)
      sqlite3 "$db" <<EOF
.timer off
.headers on
.mode csv
$sql
EOF
      ;;
    json)
      sqlite3 "$db" <<EOF
.timer off
.headers off
.mode json
$sql
EOF
      ;;
    *)
      fatal "unknown output mode: $mode"
      ;;
  esac
}

semantic_rank_tsv_rows() {
  local input_tsv="$1"
  local query_text="$2"
  local top_k="$3"
  local min_score="$4"
  local out_tsv="$5"

  local scored_tsv
  scored_tsv="$(mktemp)"
  awk -F $'\t' -v OFS=$'\t' -v dim=192 -v query="$query_text" '
    function tok_hash(token,   i,ch,pos,h) {
      h=0
      for (i=1; i<=length(token); i++) {
        ch=substr(token,i,1)
        pos=index(charset,ch)
        if (pos == 0) pos=1
        h=(h*41 + pos) % dim
      }
      return h+1
    }

    function embed_into(text, arr,   n,i,t,tokens,idx) {
      text=tolower(text)
      gsub(/[^a-z0-9_]+/, " ", text)
      n=split(text, tokens, /[ ]+/)
      for (i=1; i<=n; i++) {
        t=tokens[i]
        if (length(t) < 2) continue
        idx=tok_hash(t)
        arr[idx]+=1
      }
    }

    function vec_norm(arr,   k,s) {
      s=0
      for (k in arr) s += arr[k] * arr[k]
      return sqrt(s)
    }

    function dot_qd(arr,   k,s) {
      s=0
      for (k in qvec) {
        if (k in arr) s += qvec[k] * arr[k]
      }
      return s
    }

    BEGIN {
      charset="abcdefghijklmnopqrstuvwxyz0123456789_"
      embed_into(query, qvec)
      qnorm=vec_norm(qvec)
    }

    NR == 1 {
      header=$0
      next
    }

    {
      text=""
      for (i=1; i<=NF; i++) text = text " " $i
      for (k in dvec) delete dvec[k]
      embed_into(text, dvec)
      dnorm=vec_norm(dvec)
      score=0
      if (qnorm > 0 && dnorm > 0) score=dot_qd(dvec)/(qnorm*dnorm)
      printf "%.8f\t%s\n", score, $0
    }
  ' "$input_tsv" | sort -t $'\t' -k1,1nr > "$scored_tsv"

  {
    awk -v FS=$'\t' -v OFS=$'\t' 'NR==1 { print "score", $0 }' "$input_tsv"
    awk -F $'\t' -v min="$min_score" -v top="$top_k" '
      BEGIN { c=0 }
      {
        if ($1 + 0 < min + 0) next
        c++
        if (c <= top) print
      }
    ' "$scored_tsv"
  } > "$out_tsv"

  rm -f "$scored_tsv"
}

sql_quote() {
  local v="$1"
  printf "'%s'" "${v//\'/\'\'}"
}

wrap_like() {
  local v="$1"
  if [[ "$v" == *%* || "$v" == *_* ]]; then
    printf '%s' "$v"
  else
    printf '%%%s%%' "$v"
  fi
}

sanitize_identifier() {
  local ident="$1"
  [[ "$ident" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fatal "invalid identifier: $ident"
  printf '%s' "$ident"
}

sanitize_column_ref() {
  local ref="$1"
  if [[ "$ref" == *.* ]]; then
    local lhs="${ref%%.*}"
    local rhs="${ref#*.}"
    sanitize_identifier "$lhs" >/dev/null
    sanitize_identifier "$rhs" >/dev/null
    printf '%s' "$lhs.$rhs"
  else
    sanitize_identifier "$ref"
  fi
}

sanitize_select_expression() {
  local expr="$1"
  local default_tbl="${2:-}"
  expr="${expr//[[:space:]]/}"
  if [[ -z "$expr" ]]; then
    fatal "empty column name"
  fi
  if [[ "$expr" == "*" ]]; then
    printf '*'
    return
  fi
  if [[ "$expr" == *.* && "${expr##*.}" == "*" ]]; then
    local tbl="${expr%%.*}"
    sanitize_identifier "$tbl" >/dev/null
    printf '%s.*' "$tbl"
    return
  fi
  if [[ "$expr" == *.* ]]; then
    sanitize_column_ref "$expr"
    return
  fi
  if [[ -n "$default_tbl" ]]; then
    local tbl="$(sanitize_identifier "$default_tbl")"
    local col="$(sanitize_identifier "$expr")"
    printf '%s.%s' "$tbl" "$col"
    return
  fi
  sanitize_identifier "$expr"
}

normalize_table_name() {
  local name="${1:-}"
  [[ -n "$name" ]] || { printf '%s' "$name"; return; }
  local lower="${name,,}"
  case "$lower" in
    def|defs) echo "defs";;
    api|apis) echo "api";;
    dep|deps|dependency|dependencies) echo "deps";;
    file|files) echo "files";;
    change|changes) echo "changes";;
    change_file|changefile|change_files|changefiles) echo "change_files";;
    change_def|changedef|change_defs|changedefs) echo "change_defs";;
    todo|todos) echo "todo";;
    ref|refs) echo "refs";;
    spec|specs|spec_memory|specmemory|specmem) echo "spec_memory";;
    module|modules) echo "modules";;
    *) echo "$lower";;
  esac
}

is_supported_query_table() {
  local tbl="${1:-}"
  case "$tbl" in
    defs|files|changes|change_files|change_defs|todo|refs|spec_memory|modules|api|deps) return 0;;
    *) return 1;;
  esac
}

init_param_mode() {
  if [[ -n "$PARAM_STATE" ]]; then
    return
  fi
  case "$PARAM_PREF" in
    off) PARAM_STATE="off"; return;;
    on)  PARAM_STATE="on"; return;;
  esac
  if out="$(sqlite3 "$DB_PATH" ".parameter init\n.parameter set @p 'X'\nselect @p;" 2>/dev/null)" && [[ "$out" == "X" ]]; then
    PARAM_STATE="on"
  else
    PARAM_STATE="off"
  fi
  debug "parameter mode: $PARAM_STATE"
}

join_with() {
  local delim="$1"; shift
  local out=""
  local first=1
  for part in "$@"; do
    [[ -n "$part" ]] || continue
    if [[ $first -eq 1 ]]; then
      out="$part"
      first=0
    else
      out+="$delim$part"
    fi
  done
  printf '%s' "$out"
}

build_search_clause() {
  local term="$1"; shift
  local like_term="$(wrap_like "$term")"
  like_term="$(sql_quote "$like_term")"
  local conditions=()
  for col in "$@"; do
    conditions+=("LOWER($col) LIKE LOWER($like_term)")
  done
  local joined="$(join_with ' OR ' "${conditions[@]}")"
  printf '( %s )' "$joined"
}

require_integer() {
  local value="$1"
  local label="${2:-value}"
  [[ "$value" =~ ^[0-9]+$ ]] || fatal "$label must be an integer"
}

sql_collect() {
  local -n _out_ref="$1"
  local sql="$2"
  mapfile -t _out_ref < <(sqlite3 -batch -noheader "$DB_PATH" "$sql")
}

resolve_file_id() {
  local provided_id="$1"
  local relpath="${2:-}"
  local allow_empty="${3:-0}"

  if [[ -n "$provided_id" ]]; then
    require_integer "$provided_id" "file_id"
    printf '%s' "$provided_id"
    return
  fi

  if [[ -z "$relpath" ]]; then
    if [[ "$allow_empty" -eq 1 ]]; then
      printf '%s' ""
      return
    fi
    fatal "file identifier required; provide --file or --file-id"
  fi

  ensure_db
  local exact_sql="SELECT id FROM files WHERE relpath = $(sql_quote "$relpath")"
  local matches=()
  sql_collect matches "$exact_sql"
  if [[ ${#matches[@]} -eq 1 ]]; then
    printf '%s' "${matches[0]}"
    return
  fi

  local like_term="$(wrap_like "$relpath")"
  local like_sql=$'SELECT id\n  FROM files\n WHERE LOWER(relpath) LIKE LOWER(%s)\n ORDER BY LENGTH(relpath)'
  like_sql="$(printf "$like_sql" "$(sql_quote "$like_term")")"
  matches=()
  sql_collect matches "$like_sql"
  if [[ ${#matches[@]} -eq 1 ]]; then
    printf '%s' "${matches[0]}"
    return
  fi

  if [[ ${#matches[@]} -eq 0 ]]; then
    fatal "no files match '$relpath'"
  fi
  fatal "multiple files match '$relpath'; please use --file-id"
}

resolve_def_id() {
  local provided_id="$1"
  local signature="${2:-}"
  local file_id="${3:-}"
  local allow_empty="${4:-0}"

  if [[ -n "$provided_id" ]]; then
    require_integer "$provided_id" "def_id"
    printf '%s' "$provided_id"
    return
  fi

  if [[ -z "$signature" ]]; then
    if [[ "$allow_empty" -eq 1 ]]; then
      printf '%s' ""
      return
    fi
    fatal "definition identifier required; provide --def or --def-id"
  fi

  ensure_db
  local where_parts=("signature = $(sql_quote "$signature")")
  if [[ -n "$file_id" ]]; then
    where_parts+=("file_id = $file_id")
  fi

  local where_exact="WHERE $(join_with ' AND ' "${where_parts[@]}")"
  local exact_sql=$'SELECT id\n  FROM defs\n %s'
  exact_sql="$(printf "$exact_sql" "$where_exact")"
  local matches=()
  sql_collect matches "$exact_sql"
  if [[ ${#matches[@]} -eq 1 ]]; then
    printf '%s' "${matches[0]}"
    return
  fi

  local like_term="$(wrap_like "$signature")"
  local like_where=("LOWER(signature) LIKE LOWER($(sql_quote "$like_term"))")
  if [[ -n "$file_id" ]]; then
    like_where+=("file_id = $file_id")
  fi
  local like_sql=$'SELECT id\n  FROM defs\n WHERE %s'
  like_sql="$(printf "$like_sql" "$(join_with ' AND ' "${like_where[@]}")")"
  matches=()
  sql_collect matches "$like_sql"
  if [[ ${#matches[@]} -eq 1 ]]; then
    printf '%s' "${matches[0]}"
    return
  fi

  if [[ ${#matches[@]} -eq 0 ]]; then
    fatal "no definitions match '$signature'"
  fi
  fatal "multiple definitions match '$signature'; please use --def-id"
}

resolve_change_defs_link() {
  local def_id="$1"
  local change_id="${2:-}"
  local file_id="${3:-}"

  if [[ -z "$def_id" ]]; then
    printf '%s' ""
    return
  fi

  ensure_db
  local conditions=("def_id = $def_id")
  if [[ -n "$change_id" ]]; then
    conditions+=("change_id = $change_id")
  fi
  if [[ -n "$file_id" ]]; then
    conditions+=("file_id = $file_id")
  fi
  local where_sql="WHERE $(join_with ' AND ' "${conditions[@]}")"
  local sql=$'SELECT id || "|" || change_id\n  FROM change_defs\n %s'
  sql="$(printf "$sql" "$where_sql")"
  local rows=()
  sql_collect rows "$sql"
  if [[ ${#rows[@]} -eq 0 ]]; then
    printf '%s' ""
    return
  fi
  if [[ ${#rows[@]} -eq 1 ]]; then
    printf '%s' "${rows[0]}"
    return
  fi
  fatal "multiple change_defs rows match criteria; specify --change-def-id or --change-id"
}

resolve_change_files_link() {
  local file_id="$1"
  local change_id="${2:-}"

  if [[ -z "$file_id" ]]; then
    printf '%s' ""
    return
  fi

  ensure_db
  local conditions=("file_id = $file_id")
  if [[ -n "$change_id" ]]; then
    conditions+=("change_id = $change_id")
  fi
  local where_sql="WHERE $(join_with ' AND ' "${conditions[@]}")"
  local sql=$'SELECT id || "|" || change_id\n  FROM change_files\n %s'
  sql="$(printf "$sql" "$where_sql")"
  local rows=()
  sql_collect rows "$sql"
  if [[ ${#rows[@]} -eq 0 ]]; then
    printf '%s' ""
    return
  fi
  if [[ ${#rows[@]} -eq 1 ]]; then
    printf '%s' "${rows[0]}"
    return
  fi
  fatal "multiple change_files rows match criteria; specify --change-file-id or --change-id"
}

sql_nullable_int() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf 'NULL'
  else
    require_integer "$value"
    printf '%s' "$value"
  fi
}

sql_nullable_text() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf 'NULL'
  else
    printf '%s' "$(sql_quote "$value")"
  fi
}

command_query() {
  local -a tables=()
  local positional_columns=()
  local merge_spec=""
  local table="defs"
  local order_sql=""
  local limit_sql=""
  local select_clause=""
  local from_clause=""
  local default_order=""
  local count_mode=0
  local distinct_mode=0
  local raw_sql=0
  local output_mode="column"
  local explicit_columns=""
  local explicit_where=""
  local id_filter=""
  local filters_cols=()
  local filters_vals=()
  local search_terms=()

  local type_filter=""
  local relpath_filter=""
  local signature_filter=""
  local params_filter=""
  local desc_filter=""
  local file_desc_filter=""
  local change_filter=""
  local refers_to=""
  local referenced_by=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --table)          tables+=("$2"); shift 2;;
      --merge)          merge_spec="$2"; shift 2;;
      --order-by)       order_sql="$2"; shift 2;;
      --limit)          limit_sql="$2"; shift 2;;
      --columns)        explicit_columns="$2"; shift 2;;
      --where)          explicit_where="$2"; shift 2;;
      --filter)         local kv="$2"; filters_cols+=("${kv%%=*}"); filters_vals+=("${kv#*=}"); shift 2;;
      --search)         search_terms+=("$2"); shift 2;;
      --id)             id_filter="$2"; shift 2;;
      --count)          count_mode=1; shift;;
      --distinct)       distinct_mode=1; shift;;
      --raw-sql)        raw_sql=1; shift;;
      --format)         output_mode="$2"; shift 2;;
      --json)           output_mode="json"; shift;;
      --csv)            output_mode="csv"; shift;;
      --tsv)            output_mode="tabs"; shift;;
      --type)           type_filter="$2"; shift 2;;
      --relpath)        relpath_filter="$2"; shift 2;;
      --signature)      signature_filter="$2"; shift 2;;
      --parameters)     params_filter="$2"; shift 2;;
      --description)    desc_filter="$2"; shift 2;;
      --file-desc)      file_desc_filter="$2"; shift 2;;
      --change)         change_filter="$2"; shift 2;;
      --refers-to)      refers_to="$2"; shift 2;;
      --referenced-by)  referenced_by="$2"; shift 2;;
      --help|-h)        usage; exit 0;;
      --verbose)        VERBOSE=1; shift;;
      --database)       DB_PATH="$2"; PARAM_STATE=""; shift 2;;
      --force-params)   PARAM_PREF="on"; PARAM_STATE=""; shift;;
      --no-params)      PARAM_PREF="off"; PARAM_STATE=""; shift;;
      --)               shift; break;;
      -*)               fatal "unknown query option: $1";;
      *)                positional_columns+=("$1"); shift;;
    esac
  done

  while [[ $# -gt 0 ]]; do
    positional_columns+=("$1"); shift
  done

  if [[ ${#tables[@]} -gt 0 ]]; then
    for idx in "${!tables[@]}"; do
      tables[$idx]="$(normalize_table_name "${tables[$idx]}")"
    done
  fi

  if [[ ${#tables[@]} -eq 0 && ${#positional_columns[@]} -gt 0 ]]; then
    local candidate_table="$(normalize_table_name "${positional_columns[0]}")"
    if is_supported_query_table "$candidate_table"; then
      tables=("$candidate_table")
      positional_columns=("${positional_columns[@]:1}")
    fi
  fi

  if [[ ${#tables[@]} -eq 0 ]]; then
    tables=("defs")
  fi
  table="${tables[0]}"

  if [[ ${#tables[@]} -gt 1 && -z "$merge_spec" ]]; then
    fatal "multiple --table values require --merge to define join columns"
  fi
  if [[ -n "$merge_spec" && ${#tables[@]} -lt 2 ]]; then
    fatal "--merge requires at least two --table entries"
  fi

  ensure_db
  init_param_mode

  if [[ ${#tables[@]} -gt 1 ]]; then
    if [[ -n "$type_filter" || -n "$relpath_filter" || -n "$signature_filter" || -n "$params_filter" || -n "$desc_filter" || -n "$file_desc_filter" || -n "$change_filter" || -n "$refers_to" || -n "$referenced_by" || -n "$id_filter" ]]; then
      fatal "specialized filters like --type/--relpath are not supported with multi-table queries"
    fi
    if [[ ${#search_terms[@]} -gt 0 ]]; then
      fatal "--search terms are not supported with multi-table queries; run per-table instead"
    fi

    local sanitized_tables=()
    for tbl in "${tables[@]}"; do
      sanitized_tables+=("$(sanitize_identifier "$tbl")")
    done

    IFS=',' read -r -a merge_cols <<< "$merge_spec"
    if [[ ${#merge_cols[@]} -ne ${#tables[@]} ]]; then
      fatal "--merge must provide one column per --table entry"
    fi
    local sanitized_merge=()
    for col in "${merge_cols[@]}"; do
      col="${col//[[:space:]]/}"
      sanitized_merge+=("$(sanitize_column_ref "$col")")
    done

    local base_table="${sanitized_tables[0]}"
    local base_merge_col="${sanitized_merge[0]}"
    from_clause="$base_table"
    for idx in "${!sanitized_tables[@]}"; do
      if [[ $idx -eq 0 ]]; then
        continue
      fi
      from_clause+=" JOIN ${sanitized_tables[$idx]} ON ${sanitized_merge[$idx]} = $base_merge_col"
    done

    if [[ -n "$explicit_columns" ]]; then
      select_clause="$explicit_columns"
    elif [[ ${#positional_columns[@]} -gt 0 ]]; then
      local sanitized_cols=()
      for col in "${positional_columns[@]}"; do
        sanitized_cols+=("$(sanitize_select_expression "$col")")
      done
      select_clause="$(join_with ', ' "${sanitized_cols[@]}")"
    else
      select_clause="*"
    fi
    [[ $count_mode -eq 1 ]] && select_clause="COUNT(*)"
    [[ $distinct_mode -eq 1 && $count_mode -eq 0 ]] && select_clause="DISTINCT $select_clause"

    local where_clauses=("1=1")
    for i in "${!filters_cols[@]}"; do
      local col="${filters_cols[$i]}"
      local val="${filters_vals[$i]}"
      [[ -n "$col" ]] || continue
      local ref="$(sanitize_column_ref "$col")"
      where_clauses+=("$ref LIKE $(sql_quote "$(wrap_like "$val")")")
    done
    if [[ -n "$explicit_where" ]]; then
      where_clauses+=("($explicit_where)")
    fi

    local where_sql="WHERE $(join_with ' AND ' "${where_clauses[@]}")"
    local order_clause=""
    [[ $count_mode -eq 0 && -n "$order_sql" ]] && order_clause="ORDER BY $order_sql"
    local limit_clause=""
    [[ -n "$limit_sql" ]] && limit_clause="LIMIT $limit_sql"

    read -r -d '' SQL_BODY <<SQL || true
SELECT $select_clause
FROM $from_clause
$where_sql
$order_clause
$limit_clause;
SQL

    if [[ $raw_sql -eq 1 ]]; then
      echo "/* SQL */" >&2
      echo "$SQL_BODY" >&2
    fi

    run_query_output "$DB_PATH" "$output_mode" "$SQL_BODY"
    return
  fi

  table="$(sanitize_identifier "$table")"

  local search_cols=()

  case "$table" in
    defs)
      select_clause="defs.id AS def_id, files.relpath, defs.type, defs.signature, defs.parameters, defs.description"
      from_clause=$'FROM defs\nJOIN files ON files.id = defs.file_id'
      default_order="files.relpath, defs.type, defs.signature"
      search_cols=("files.relpath" "defs.signature" "defs.description" "defs.parameters" "defs.type")
      ;;
    api)
      select_clause="api.id AS api_id, api.file_id, files.relpath, api.def_id, defs.signature AS def_signature, api.signature, api.description"
      from_clause=$'FROM api\nLEFT JOIN files ON files.id = api.file_id\nLEFT JOIN defs ON defs.id = api.def_id'
      default_order="files.relpath, api.signature, api.id"
      search_cols=("files.relpath" "api.signature" "api.description" "defs.signature")
      ;;
    files)
      select_clause="files.id, files.relpath, files.description"
      from_clause="FROM files"
      default_order="files.relpath"
      search_cols=("files.relpath" "files.description")
      ;;
    changes)
      select_clause="changes.id, changes.title, changes.status, changes.context"
      from_clause="FROM changes"
      default_order="changes.id"
      search_cols=("changes.title" "changes.context" "changes.status")
      ;;
    change_files)
      select_clause="change_files.id, change_files.change_id, change_files.file_id, files.relpath"
      from_clause=$'FROM change_files\nLEFT JOIN files ON files.id = change_files.file_id'
      default_order="change_files.change_id, change_files.id"
      search_cols=("files.relpath")
      ;;
    change_defs)
      select_clause="change_defs.id, change_defs.change_id, change_defs.file_id, change_defs.def_id, change_defs.description, files.relpath AS file_relpath, defs.signature AS def_signature"
      from_clause=$'FROM change_defs\nLEFT JOIN files ON files.id = change_defs.file_id\nLEFT JOIN defs ON defs.id = change_defs.def_id'
      default_order="change_defs.change_id, change_defs.id"
      search_cols=("change_defs.description" "files.relpath" "defs.signature")
      ;;
    todo)
      select_clause="todo.id, todo.change_id, todo.change_defs_id, todo.change_files_id, todo.description"
      from_clause="FROM todo"
      default_order="todo.change_id, todo.id"
      search_cols=("todo.description")
      ;;
    refs)
      select_clause="refs.id, refs.def_id, d.signature AS def_signature, refs.reference_def_id, rd.signature AS reference_signature"
      from_clause=$'FROM refs\nLEFT JOIN defs d ON d.id = refs.def_id\nLEFT JOIN defs rd ON rd.id = refs.reference_def_id'
      default_order="refs.id"
      search_cols=("d.signature" "rd.signature")
      ;;
    spec_memory)
      select_clause="spec_memory.id, spec_memory.path, spec_memory.parent_id, spec_memory.kind, spec_memory.status, spec_memory.content, spec_memory.depends_on, spec_memory.branch, spec_memory.supersedes_id, spec_memory.created_at"
      from_clause="FROM spec_memory"
      default_order="spec_memory.id"
      search_cols=("spec_memory.path" "spec_memory.kind" "spec_memory.status" "spec_memory.content" "spec_memory.depends_on" "spec_memory.branch")
      ;;
    modules)
      select_clause="modules.id, modules.name, modules.path, modules.description, modules.dependencies"
      from_clause="FROM modules"
      default_order="modules.name, modules.id"
      search_cols=("modules.name" "modules.path" "modules.description" "modules.dependencies")
      ;;
    deps)
      select_clause="deps.id, deps.file_id, sf.relpath AS source_relpath, deps.def_id, sd.signature AS source_signature, deps.dep_file_id, df.relpath AS dep_relpath, deps.dep_def_id, dd.signature AS dep_signature, deps.description"
      from_clause=$'FROM deps\nLEFT JOIN files sf ON sf.id = deps.file_id\nLEFT JOIN defs sd ON sd.id = deps.def_id\nLEFT JOIN files df ON df.id = deps.dep_file_id\nLEFT JOIN defs dd ON dd.id = deps.dep_def_id'
      default_order="deps.id"
      search_cols=("sf.relpath" "sd.signature" "df.relpath" "dd.signature" "deps.description")
      ;;
    *)
      fatal "unsupported table for query: $table"
      ;;
  esac

  if [[ -n "$explicit_columns" ]]; then
    select_clause="$explicit_columns"
  elif [[ ${#positional_columns[@]} -gt 0 ]]; then
    local sanitized_cols=()
    for col in "${positional_columns[@]}"; do
      sanitized_cols+=("$(sanitize_select_expression "$col" "$table")")
    done
    select_clause="$(join_with ', ' "${sanitized_cols[@]}")"
  fi
  [[ $count_mode -eq 1 ]] && select_clause="COUNT(*)"
  [[ $distinct_mode -eq 1 && $count_mode -eq 0 ]] && select_clause="DISTINCT $select_clause"

  [[ -z "$order_sql" ]] && order_sql="$default_order"

  local where_clauses=("1=1")

  if [[ -n "$id_filter" ]]; then
    where_clauses+=("$table.id = $id_filter")
  fi

  if [[ -n "$type_filter" ]]; then
    [[ "$table" == "defs" ]] || fatal "--type is only valid for defs"
    where_clauses+=("defs.type LIKE $(sql_quote "$(wrap_like "$type_filter")")")
  fi

  if [[ -n "$relpath_filter" ]]; then
    case "$table" in
      defs|change_files|change_defs|api)
        where_clauses+=("files.relpath LIKE $(sql_quote "$(wrap_like "$relpath_filter")")")
        ;;
      files)
        where_clauses+=("files.relpath LIKE $(sql_quote "$(wrap_like "$relpath_filter")")")
        ;;
      deps)
        where_clauses+=("(sf.relpath LIKE $(sql_quote "$(wrap_like "$relpath_filter")") OR df.relpath LIKE $(sql_quote "$(wrap_like "$relpath_filter")"))")
        ;;
      *)
        fatal "--relpath is not supported for table $table"
        ;;
    esac
  fi

  if [[ -n "$signature_filter" ]]; then
    case "$table" in
      defs)
        where_clauses+=("defs.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")")")
        ;;
      change_defs)
        where_clauses+=("defs.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")")")
        ;;
      api)
        where_clauses+=("(api.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")") OR defs.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")"))")
        ;;
      deps)
        where_clauses+=("(sd.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")") OR dd.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")"))")
        ;;
      refs)
        where_clauses+=("(d.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")") OR rd.signature LIKE $(sql_quote "$(wrap_like "$signature_filter")"))")
        ;;
      *)
        fatal "--signature is not supported for table $table"
        ;;
    esac
  fi

  if [[ -n "$params_filter" ]]; then
    [[ "$table" == "defs" ]] || fatal "--parameters is only valid for defs"
    where_clauses+=("defs.parameters LIKE $(sql_quote "$(wrap_like "$params_filter")")")
  fi

  if [[ -n "$desc_filter" ]]; then
    case "$table" in
      defs) where_clauses+=("defs.description LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      files) where_clauses+=("files.description LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      change_defs) where_clauses+=("change_defs.description LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      api) where_clauses+=("api.description LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      deps) where_clauses+=("deps.description LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      todo) where_clauses+=("todo.description LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      changes) where_clauses+=("changes.context LIKE $(sql_quote "$(wrap_like "$desc_filter")")");;
      *) fatal "--description is not supported for table $table";;
    esac
  fi

  if [[ -n "$file_desc_filter" ]]; then
    case "$table" in
      defs|change_files|change_defs|api)
        where_clauses+=("files.description LIKE $(sql_quote "$(wrap_like "$file_desc_filter")")")
        ;;
      deps)
        where_clauses+=("(sf.description LIKE $(sql_quote "$(wrap_like "$file_desc_filter")") OR df.description LIKE $(sql_quote "$(wrap_like "$file_desc_filter")"))")
        ;;
      *)
        fatal "--file-desc is only valid when files.* is joined"
        ;;
    esac
  fi

  if [[ -n "$change_filter" ]]; then
    case "$table" in
      defs)
        from_clause+=$'\nLEFT JOIN change_files cf ON cf.file_id = files.id\nLEFT JOIN change_defs cd ON cd.def_id = defs.id'
        where_clauses+=("(cf.change_id = $change_filter OR cd.change_id = $change_filter)")
        ;;
      change_files)
        where_clauses+=("change_files.change_id = $change_filter")
        ;;
      change_defs)
        where_clauses+=("change_defs.change_id = $change_filter")
        ;;
      todo)
        where_clauses+=("todo.change_id = $change_filter")
        ;;
      changes)
        where_clauses+=("changes.id = $change_filter")
        ;;
      *)
        fatal "--change not supported for table $table"
        ;;
    esac
  fi

  if [[ -n "$refers_to" && -n "$referenced_by" ]]; then
    fatal "use either --refers-to or --referenced-by, not both"
  fi
  if [[ -n "$refers_to" ]]; then
    [[ "$table" == "defs" ]] || fatal "--refers-to only applies to defs"
    from_clause+=$'\nJOIN refs rft ON rft.def_id = defs.id'
    where_clauses+=("rft.reference_def_id = $refers_to")
  fi
  if [[ -n "$referenced_by" ]]; then
    [[ "$table" == "defs" ]] || fatal "--referenced-by only applies to defs"
    from_clause+=$'\nJOIN refs rby ON rby.reference_def_id = defs.id'
    where_clauses+=("rby.def_id = $referenced_by")
  fi

  for i in "${!filters_cols[@]}"; do
    local col="${filters_cols[$i]}"
    local val="${filters_vals[$i]}"
    [[ -n "$col" ]] || continue
    local ref="$(sanitize_column_ref "$col")"
    where_clauses+=("$ref LIKE $(sql_quote "$(wrap_like "$val")")")
  done

  for term in "${search_terms[@]}"; do
    [[ ${#search_cols[@]} -gt 0 ]] || fatal "search is not supported for table $table"
    local clause="$(build_search_clause "$term" "${search_cols[@]}")"
    where_clauses+=("$clause")
  done

  if [[ -n "$explicit_where" ]]; then
    where_clauses+=("($explicit_where)")
  fi

  local where_sql="WHERE $(join_with ' AND ' "${where_clauses[@]}")"
  local order_clause=""
  [[ $count_mode -eq 0 && -n "$order_sql" ]] && order_clause="ORDER BY $order_sql"
  local limit_clause=""
  [[ -n "$limit_sql" ]] && limit_clause="LIMIT $limit_sql"

  read -r -d '' SQL_BODY <<SQL || true
SELECT $select_clause
$from_clause
$where_sql
$order_clause
$limit_clause;
SQL

  if [[ $raw_sql -eq 1 ]]; then
    echo "/* SQL */" >&2
    echo "$SQL_BODY" >&2
  fi

  run_query_output "$DB_PATH" "$output_mode" "$SQL_BODY"
}

command_search() {
  local -a tables=()
  local limit=20
  local passthrough=()
  local terms=()
  local semantic_query=""
  local semantic_top=""
  local semantic_min_score="0"
  local count_requested=0
  local output_mode_requested=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --table|-t)
        [[ $# -ge 2 ]] || fatal "--table expects a table name"
        tables+=("$2"); shift 2;;
      --limit)
        [[ $# -ge 2 ]] || fatal "--limit expects a value"
        limit="$2"; shift 2;;
      --order-by) passthrough+=("--order-by" "$2"); shift 2;;
      --columns)  passthrough+=("--columns" "$2"); shift 2;;
      --change)   passthrough+=("--change" "$2"); shift 2;;
      --filter)   passthrough+=("--filter" "$2"); shift 2;;
      --where)    passthrough+=("--where" "$2"); shift 2;;
      --semantic)
        [[ $# -ge 2 ]] || fatal "--semantic expects TEXT"
        semantic_query="$2"; shift 2;;
      --semantic-top)
        [[ $# -ge 2 ]] || fatal "--semantic-top expects N"
        semantic_top="$2"; shift 2;;
      --semantic-min-score)
        [[ $# -ge 2 ]] || fatal "--semantic-min-score expects F"
        semantic_min_score="$2"; shift 2;;
      --raw-sql)  passthrough+=("--raw-sql"); shift;;
      --distinct) passthrough+=("--distinct"); shift;;
      --count)    passthrough+=("--count"); count_requested=1; shift;;
      --json)     passthrough+=("--json"); output_mode_requested="json"; shift;;
      --csv)      passthrough+=("--csv"); output_mode_requested="csv"; shift;;
      --tsv)      passthrough+=("--tsv"); output_mode_requested="tsv"; shift;;
      --format)
        [[ $# -ge 2 ]] || fatal "--format expects MODE"
        passthrough+=("--format" "$2"); output_mode_requested="$2"; shift 2;;
      --help|-h)  usage; exit 0;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          terms+=("$1"); shift
        done
        break
        ;;
      -* ) fatal "unknown search option: $1";;
      *)
        terms+=("$1"); shift;;
    esac
  done

  [[ ${#tables[@]} -gt 0 ]] || tables=("defs")
  if [[ -z "$semantic_query" && ${#terms[@]} -eq 0 ]]; then
    fatal "search requires at least one term (or provide --semantic TEXT)"
  fi
  if [[ -z "$semantic_query" && ( -n "$semantic_top" || "$semantic_min_score" != "0" ) ]]; then
    fatal "--semantic-top/--semantic-min-score require --semantic TEXT"
  fi
  [[ "$limit" =~ ^[0-9]+$ ]] || fatal "--limit must be a positive integer"
  if [[ -n "$semantic_query" ]]; then
    if [[ -n "$output_mode_requested" && "$output_mode_requested" != "table" && "$output_mode_requested" != "column" ]]; then
      fatal "--semantic currently supports table output only; remove --json/--csv/--tsv/--format"
    fi
    if [[ $count_requested -eq 1 ]]; then
      fatal "--semantic is not compatible with --count"
    fi
    if [[ -z "$semantic_top" ]]; then
      semantic_top="$limit"
    fi
    [[ "$semantic_top" =~ ^[0-9]+$ ]] || fatal "--semantic-top must be a positive integer"
    [[ "$semantic_min_score" =~ ^[0-9]+([.][0-9]+)?$ ]] || fatal "--semantic-min-score must be a non-negative number"
  fi

  local fetch_limit="$limit"
  if [[ -n "$semantic_query" && "$semantic_top" -gt "$limit" ]]; then
    fetch_limit="$semantic_top"
  fi

  local first_table=1
  for table in "${tables[@]}"; do
    local args=("--table" "$table" "--limit" "$fetch_limit")
    args+=("${passthrough[@]}")
    for term in "${terms[@]}"; do
      args+=("--search" "$term")
    done
    if [[ ${#tables[@]} -gt 1 ]]; then
      if [[ $first_table -eq 0 ]]; then
        printf '\n'
      fi
      printf '%s\n' "-- $table --"
      first_table=0
    fi
    if [[ -n "$semantic_query" ]]; then
      local tsv_in
      local tsv_out
      local table_tsv
      tsv_in="$(mktemp)"
      tsv_out="$(mktemp)"
      if ! table_tsv="$(command_query "${args[@]}" --tsv)"; then
        rm -f "$tsv_in" "$tsv_out"
        fatal "query failed for table $table"
      fi
      printf '%s\n' "$table_tsv" > "$tsv_in"
      semantic_rank_tsv_rows "$tsv_in" "$semantic_query" "$semantic_top" "$semantic_min_score" "$tsv_out"
      if command -v column >/dev/null 2>&1; then
        column -t -s $'\t' "$tsv_out"
      else
        cat "$tsv_out"
      fi
      rm -f "$tsv_in" "$tsv_out"
    else
      command_query "${args[@]}"
    fi
  done
}

parse_assignments() {
  local -n _names_ref="$1"
  local -n _values_ref="$2"
  shift 2
  while [[ $# -gt 0 ]]; do
    local pair="$1"
    if [[ "$pair" != *=* ]]; then
      fatal "expected key=value assignment, got '$pair'"
    fi
    local key="${pair%%=*}"
    local value="${pair#*=}"
    [[ -n "$key" ]] || fatal "empty column name in assignment"
    _names_ref+=("$(sanitize_identifier "$key")")
    _values_ref+=("$value")
    shift
  done
}

command_insert() {
  ensure_db
  [[ $# -ge 2 ]] || fatal "insert requires TABLE and at least one key=value"
  local table="$1"; shift
  table="$(sanitize_identifier "$table")"
  local cols=()
  local vals=()
  parse_assignments cols vals "$@"
  local col_list="$(join_with ', ' "${cols[@]}")"
  local val_list_parts=()
  for v in "${vals[@]}"; do
    val_list_parts+=("$(sql_quote "$v")")
  done
  local val_list="$(join_with ', ' "${val_list_parts[@]}")"
  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO $table ($col_list) VALUES ($val_list);
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

command_update() {
  ensure_db
  [[ $# -ge 1 ]] || fatal "update requires TABLE"
  local table="$1"; shift
  table="$(sanitize_identifier "$table")"
  local id_clause=""
  local where_clause=""
  local sets=()
  local values=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --set)
        [[ $# -ge 2 ]] || fatal "--set expects key=value"
        parse_assignments sets values "$2"
        shift 2
        ;;
      --id)
        id_clause="$2"; shift 2
        ;;
      --where)
        where_clause="$2"; shift 2
        ;;
      --) shift; break;;
      *)
        parse_assignments sets values "$1"
        shift
        ;;
    esac
  done
  [[ ${#sets[@]} -gt 0 ]] || fatal "update requires at least one --set column=value"
  if [[ -n "$id_clause" && -n "$where_clause" ]]; then
    fatal "provide either --id or --where, not both"
  fi
  if [[ -z "$where_clause" && -z "$id_clause" ]]; then
    fatal "update requires --id ID or --where SQL"
  fi
  [[ ${#sets[@]} -eq ${#values[@]} ]] || fatal "internal error: set/value mismatch"
  local set_fragments=()
  for i in "${!sets[@]}"; do
    set_fragments+=("${sets[$i]} = $(sql_quote "${values[$i]}")")
  done
  local set_clause="$(join_with ', ' "${set_fragments[@]}")"
  if [[ -n "$id_clause" ]]; then
    where_clause="$table.id = $id_clause"
  fi
  local sql
  read -r -d '' sql <<EOF || true
UPDATE $table
   SET $set_clause
 WHERE $where_clause;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

command_delete() {
  ensure_db
  [[ $# -ge 1 ]] || fatal "delete requires TABLE"
  local table="$1"; shift
  table="$(sanitize_identifier "$table")"
  local where_clause=""
  local id_clause=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id_clause="$2"; shift 2;;
      --where) where_clause="$2"; shift 2;;
      --) shift; break;;
      *) fatal "unknown delete option: $1";;
    esac
  done
  if [[ -n "$id_clause" && -n "$where_clause" ]]; then
    fatal "provide either --id or --where"
  fi
  if [[ -z "$where_clause" ]]; then
    [[ -n "$id_clause" ]] || fatal "delete requires --id ID or --where SQL"
    where_clause="$table.id = $id_clause"
  fi
  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM $table WHERE $where_clause;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

command_describe() {
  ensure_db
  [[ $# -ge 1 ]] || fatal "describe requires TABLE"
  local table="$1"; shift
  table="$(sanitize_identifier "$table")"
  local show_schema=0
  local row_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --schema) show_schema=1; shift;;
      --id)     row_id="$2"; shift 2;;
      --where)
        local where_clause="$2"; shift 2
        sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT * FROM $table WHERE $where_clause;
EOF
        return
        ;;
      --) shift; break;;
      *) fatal "unknown describe option: $1";;
    esac
  done
  if [[ $show_schema -eq 1 ]]; then
    sqlite3 "$DB_PATH" "PRAGMA table_info($table);"
  fi
  if [[ -n "$row_id" ]]; then
    sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT * FROM $table WHERE id = $row_id;
EOF
  elif [[ $show_schema -eq 0 ]]; then
    sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT * FROM $table LIMIT 20;
EOF
  fi
}

command_plan() {
  ensure_db
  [[ $# -eq 1 ]] || fatal "plan requires CHANGE_ID"
  local change_id="$1"
  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT id, title, status, context FROM changes WHERE id = $change_id;

SELECT cf.id AS change_file_id, cf.file_id, f.relpath, f.description
  FROM change_files cf
  LEFT JOIN files f ON f.id = cf.file_id
 WHERE cf.change_id = $change_id
 ORDER BY cf.id;

SELECT cd.id AS change_def_id, cd.file_id, cd.def_id, cd.description, f.relpath, d.signature
  FROM change_defs cd
  LEFT JOIN files f ON f.id = cd.file_id
  LEFT JOIN defs d ON d.id = cd.def_id
 WHERE cd.change_id = $change_id
 ORDER BY cd.id;

SELECT t.id AS todo_id, t.description, t.change_defs_id, t.change_files_id
  FROM todo t
 WHERE t.change_id = $change_id
 ORDER BY t.id;
EOF
}

command_raw() {
  ensure_db
  if [[ $# -eq 0 ]]; then
    sqlite3 "$DB_PATH"
  else
    local sql="$*"
    sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
$sql
EOF
  fi
}

todo_list() {
  ensure_db
  sqlite3 "$DB_PATH" <<'SQL'
.timer off
.headers on
.mode column
SELECT
  t.id,
  t.change_id,
  COALESCE(t.change_defs_id, '')            AS change_def_id,
  COALESCE(t.change_files_id, '')           AS change_file_id,
  COALESCE(f_cd.relpath, f_cf.relpath, '')  AS relpath,
  COALESCE(d.signature, '')                 AS def_signature,
  t.description
FROM todo t
LEFT JOIN change_defs cd       ON cd.id = t.change_defs_id
LEFT JOIN change_files cf      ON cf.id = t.change_files_id
LEFT JOIN files f_cd           ON f_cd.id = cd.file_id
LEFT JOIN files f_cf           ON f_cf.id = cf.file_id
LEFT JOIN defs d               ON d.id = cd.def_id
ORDER BY t.id;
SQL
}

todo_add() {
  ensure_db
  local description=""
  local file_path=""
  local file_id=""
  local def_signature=""
  local def_id=""
  local change_id=""
  local change_defs_id=""
  local change_files_id=""
  local change_file_id_opt=""
  local change_def_id_opt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --description=*) description="${1#*=}"; shift;;
      --description)   description="$2"; shift 2;;
      --file=*)        file_path="${1#*=}"; shift;;
      --file)          file_path="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --def=*)         def_signature="${1#*=}"; shift;;
      --def)           def_signature="$2"; shift 2;;
      --def_id=*|--def-id=*) def_id="${1#*=}"; shift;;
      --def_id|--def-id)     def_id="$2"; shift 2;;
      --change_id=*|--change-id=*|--change=*) change_id="${1#*=}"; shift;;
      --change_id|--change-id|--change)      change_id="$2"; shift 2;;
      --change_def_id=*|--change-def-id=*|--change_defs_id=*|--change-defs-id=*)
        change_def_id_opt="${1#*=}"; shift;;
      --change_def_id|--change-def-id|--change_defs_id|--change-defs-id)
        change_def_id_opt="$2"; shift 2;;
      --change_file_id=*|--change-file-id=*|--change_files_id=*|--change-files-id=*)
        change_file_id_opt="${1#*=}"; shift;;
      --change_file_id|--change-file-id|--change_files_id|--change-files-id)
        change_file_id_opt="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG todo add --description=TEXT [--file=REL|--file_id=N] [--def=SIG|--def_id=N] [--change-id=N]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for todo add: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for todo add"
        ;;
    esac
  done

  [[ -n "$description" ]] || fatal "todo add requires --description"

  local resolved_file_id
  resolved_file_id="$(resolve_file_id "$file_id" "$file_path" 1)"

  local resolved_def_id
  resolved_def_id="$(resolve_def_id "$def_id" "$def_signature" "$resolved_file_id" 1)"

  if [[ -n "$change_def_id_opt" ]]; then
    require_integer "$change_def_id_opt" "change_defs_id"
    change_defs_id="$change_def_id_opt"
    local info
    info="$(sqlite3 -batch -noheader "$DB_PATH" "SELECT change_id || '|' || IFNULL(def_id,'') || '|' || IFNULL(file_id,'') FROM change_defs WHERE id = $change_defs_id;")" || true
    [[ -n "$info" ]] || fatal "no change_defs row with id $change_defs_id"
    IFS='|' read -r cd_change cd_def cd_file <<<"$info"
    if [[ -n "$change_id" && "$change_id" != "$cd_change" ]]; then
      fatal "change id $change_id disagrees with change_defs $change_defs_id change $cd_change"
    fi
    change_id="${change_id:-$cd_change}"
    if [[ -n "$resolved_def_id" && -n "$cd_def" && "$resolved_def_id" != "$cd_def" ]]; then
      fatal "change_defs $change_defs_id references def $cd_def which conflicts with resolved def $resolved_def_id"
    fi
    if [[ -z "$resolved_def_id" && -n "$cd_def" ]]; then
      resolved_def_id="$cd_def"
    fi
    if [[ -n "$resolved_file_id" && -n "$cd_file" && "$resolved_file_id" != "$cd_file" ]]; then
      fatal "change_defs $change_defs_id references file $cd_file which conflicts with resolved file $resolved_file_id"
    fi
    if [[ -z "$resolved_file_id" && -n "$cd_file" ]]; then
      resolved_file_id="$cd_file"
    fi
  fi

  if [[ -n "$change_file_id_opt" ]]; then
    require_integer "$change_file_id_opt" "change_files_id"
    change_files_id="$change_file_id_opt"
    local info
    info="$(sqlite3 -batch -noheader "$DB_PATH" "SELECT change_id || '|' || file_id FROM change_files WHERE id = $change_files_id;")" || true
    [[ -n "$info" ]] || fatal "no change_files row with id $change_files_id"
    IFS='|' read -r cf_change cf_file <<<"$info"
    if [[ -n "$change_id" && "$change_id" != "$cf_change" ]]; then
      fatal "change id $change_id disagrees with change_files $change_files_id change $cf_change"
    fi
    change_id="${change_id:-$cf_change}"
    if [[ -n "$resolved_file_id" && -n "$cf_file" && "$resolved_file_id" != "$cf_file" ]]; then
      fatal "change_files $change_files_id references file $cf_file which conflicts with resolved file $resolved_file_id"
    fi
    if [[ -z "$resolved_file_id" && -n "$cf_file" ]]; then
      resolved_file_id="$cf_file"
    fi
  fi

  if [[ -z "$change_defs_id" && -n "$resolved_def_id" ]]; then
    local link
    link="$(resolve_change_defs_link "$resolved_def_id" "$change_id" "$resolved_file_id")"
    if [[ -n "$link" ]]; then
      change_defs_id="${link%%|*}"
      local inferred="${link#*|}"
      if [[ -n "$change_id" && "$change_id" != "$inferred" ]]; then
        fatal "change id $change_id disagrees with inferred change_def $change_defs_id change $inferred"
      fi
      change_id="${change_id:-$inferred}"
    fi
  fi

  if [[ -z "$change_files_id" && -n "$resolved_file_id" ]]; then
    local link
    link="$(resolve_change_files_link "$resolved_file_id" "$change_id")"
    if [[ -n "$link" ]]; then
      change_files_id="${link%%|*}"
      local inferred="${link#*|}"
      if [[ -n "$change_id" && "$change_id" != "$inferred" ]]; then
        fatal "change id $change_id disagrees with inferred change_file $change_files_id change $inferred"
      fi
      change_id="${change_id:-$inferred}"
    fi
  fi

  if [[ -z "$change_id" ]]; then
    fatal "unable to determine change id; supply --change-id explicitly"
  fi
  require_integer "$change_id" "change_id"

  local change_defs_sql
  change_defs_sql="$(sql_nullable_int "$change_defs_id")"
  local change_files_sql
  change_files_sql="$(sql_nullable_int "$change_files_id")"
  local description_sql
  description_sql="$(sql_quote "$description")"

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO todo (change_id, change_defs_id, change_files_id, description)
VALUES ($change_id, $change_defs_sql, $change_files_sql, $description_sql);
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

todo_del() {
  ensure_db
  [[ $# -eq 1 ]] || fatal "todo del requires TODO_ID"
  local todo_id="$1"
  require_integer "$todo_id" "todo id"
  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM todo WHERE id = $todo_id;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

todo_search() {
  ensure_db
  local -a terms=()
  local file_filter=""
  local file_id=""
  local def_filter=""
  local def_id=""
  local change_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file=*)    file_filter="${1#*=}"; shift;;
      --file)      file_filter="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --def=*)     def_filter="${1#*=}"; shift;;
      --def)       def_filter="$2"; shift 2;;
      --def_id=*|--def-id=*) def_id="${1#*=}"; shift;;
      --def_id|--def-id)     def_id="$2"; shift 2;;
      --change=*|--change-id=*|--change_id=*) change_id="${1#*=}"; shift;;
      --change|--change-id|--change_id) change_id="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG todo search term... [--file=REL] [--def=SIG] [--file_id=N] [--def_id=N] [--change-id=N]"
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          terms+=("$1"); shift
        done
        break
        ;;
      -*)
        fatal "unknown flag for todo search: $1"
        ;;
      *)
        terms+=("$1"); shift;;
    esac
  done

  [[ ${#terms[@]} -gt 0 ]] || fatal "todo search requires at least one term"

  local where_clauses=("1=1")
  for term in "${terms[@]}"; do
    local like_term="$(wrap_like "$term")"
    local like_sql="$(sql_quote "$like_term")"
    where_clauses+=("(LOWER(t.description) LIKE LOWER($like_sql) OR LOWER(COALESCE(d.signature,'')) LIKE LOWER($like_sql) OR LOWER(COALESCE(f_cf.relpath, f_cd.relpath,'')) LIKE LOWER($like_sql))")
  done

  if [[ -n "$file_id" ]]; then
    require_integer "$file_id" "file_id"
    where_clauses+=("(cf.file_id = $file_id OR cd.file_id = $file_id)")
  elif [[ -n "$file_filter" ]]; then
    local like_file="$(sql_quote "$(wrap_like "$file_filter")")"
    where_clauses+=("LOWER(COALESCE(f_cf.relpath, f_cd.relpath,'')) LIKE LOWER($like_file)")
  fi

  if [[ -n "$def_id" ]]; then
    require_integer "$def_id" "def_id"
    where_clauses+=("cd.def_id = $def_id")
  elif [[ -n "$def_filter" ]]; then
    local like_def="$(sql_quote "$(wrap_like "$def_filter")")"
    where_clauses+=("LOWER(COALESCE(d.signature,'')) LIKE LOWER($like_def)")
  fi

  if [[ -n "$change_id" ]]; then
    require_integer "$change_id" "change_id"
    where_clauses+=("t.change_id = $change_id")
  fi

  local where_sql="$(join_with ' AND ' "${where_clauses[@]}")"

  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT
  t.id,
  t.change_id,
  COALESCE(f_cf.relpath, f_cd.relpath) AS relpath,
  COALESCE(d.signature, '')            AS def_signature,
  t.description
FROM todo t
LEFT JOIN change_defs cd       ON cd.id = t.change_defs_id
LEFT JOIN change_files cf      ON cf.id = t.change_files_id
LEFT JOIN files f_cd           ON f_cd.id = cd.file_id
LEFT JOIN files f_cf           ON f_cf.id = cf.file_id
LEFT JOIN defs d               ON d.id = cd.def_id
WHERE $where_sql
ORDER BY t.id;
EOF
}

command_todo() {
  [[ $# -ge 1 ]] || fatal "todo requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)   todo_list "$@";;
    add)    todo_add "$@";;
    del|delete|rm)
      todo_del "$@"
      ;;
    search)
      todo_search "$@"
      ;;
    --help|-h)
      fatal "todo subcommands: list, add, del, search"
      ;;
    *)
      fatal "unknown todo subcommand: $subcommand"
      ;;
  esac
}

changes_list() {
  ensure_db
  sqlite3 "$DB_PATH" <<'SQL'
.timer off
.headers on
.mode column
SELECT id, title, status, context
FROM changes
ORDER BY id;
SQL
}

changes_add() {
  ensure_db
  local title=""
  local context=""
  local status=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title=*)   title="${1#*=}"; shift;;
      --title)     title="$2"; shift 2;;
      --context=*) context="${1#*=}"; shift;;
      --context)   context="$2"; shift 2;;
      --status=*)  status="${1#*=}"; shift;;
      --status)    status="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG changes add --title=TEXT --status=STATUS [--context=TEXT]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for changes add: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for changes add"
        ;;
    esac
  done
  [[ -n "$title" ]] || fatal "changes add requires --title"
  [[ -n "$status" ]] || fatal "changes add requires --status"

  local title_sql
  title_sql="$(sql_quote "$title")"
  local status_sql
  status_sql="$(sql_quote "$status")"
  local context_sql
  context_sql="$(sql_nullable_text "$context")"

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO changes (title, context, status)
VALUES ($title_sql, $context_sql, $status_sql);
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

changes_update() {
  ensure_db
  [[ $# -ge 1 ]] || fatal "changes update requires CHANGE_ID"
  local change_id="$1"; shift
  require_integer "$change_id" "change id"

  local sets=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title=*)   sets+=("title = $(sql_quote "${1#*=}")"); shift;;
      --title)     sets+=("title = $(sql_quote "$2")"); shift 2;;
      --context=*) sets+=("context = $(sql_nullable_text "${1#*=}")"); shift;;
      --context)   sets+=("context = $(sql_nullable_text "$2")"); shift 2;;
      --status=*)  sets+=("status = $(sql_quote "${1#*=}")"); shift;;
      --status)    sets+=("status = $(sql_quote "$2")"); shift 2;;
      --help|-h)
        fatal "usage: $PROG changes update CHANGE_ID [--title=TEXT] [--context=TEXT] [--status=STATUS]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for changes update: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for changes update"
        ;;
    esac
  done

  [[ ${#sets[@]} -gt 0 ]] || fatal "changes update requires at least one field flag"
  local set_clause="$(join_with ', ' "${sets[@]}")"

  local sql
  read -r -d '' sql <<EOF || true
UPDATE changes
   SET $set_clause
 WHERE id = $change_id;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

command_changes() {
  [[ $# -ge 1 ]] || fatal "changes requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)   changes_list "$@";;
    add)    changes_add "$@";;
    update) changes_update "$@";;
    --help|-h)
      fatal "changes subcommands: list, add, update"
      ;;
    *)
      fatal "unknown changes subcommand: $subcommand"
      ;;
  esac
}

files_list() {
  ensure_db
  sqlite3 "$DB_PATH" <<'SQL'
.timer off
.headers on
.mode column
SELECT id, relpath, description
FROM files
ORDER BY relpath;
SQL
}

files_search() {
  ensure_db
  local -a terms=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        fatal "usage: $PROG files search term..."
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          terms+=("$1"); shift
        done
        break
        ;;
      -*)
        fatal "unknown flag for files search: $1"
        ;;
      *)
        terms+=("$1"); shift;;
    esac
  done

  [[ ${#terms[@]} -gt 0 ]] || fatal "files search requires at least one term"

  local where_clauses=("1=1")
  for term in "${terms[@]}"; do
    local like="$(sql_quote "$(wrap_like "$term")")"
    where_clauses+=("(LOWER(relpath) LIKE LOWER($like) OR LOWER(COALESCE(description,'')) LIKE LOWER($like))")
  done

  local where_sql="$(join_with ' AND ' "${where_clauses[@]}")"

  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT id, relpath, description
FROM files
WHERE $where_sql
ORDER BY relpath;
EOF
}

files_add() {
  ensure_db
  local relpath=""
  local description=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --relpath=*) relpath="${1#*=}"; shift;;
      --relpath)   relpath="$2"; shift 2;;
      --file=*)    relpath="${1#*=}"; shift;;
      --file)      relpath="$2"; shift 2;;
      --description=*) description="${1#*=}"; shift;;
      --description)   description="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG files add --relpath=PATH|--file=PATH [--description=TEXT]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for files add: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for files add"
        ;;
    esac
  done

  [[ -n "$relpath" ]] || fatal "files add requires --relpath/--file"
  local relpath_sql
  relpath_sql="$(sql_quote "$relpath")"
  local description_sql
  description_sql="$(sql_nullable_text "$description")"

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO files (relpath, description)
VALUES ($relpath_sql, $description_sql);
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

files_del() {
  ensure_db
  local file_id=""
  local relpath=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --file=*)               relpath="${1#*=}"; shift;;
      --file)                 relpath="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG files del [--file_id=N | --file=PATH]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for files del: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for files del"
        ;;
    esac
  done

  local resolved_id
  resolved_id="$(resolve_file_id "$file_id" "$relpath")"
  require_integer "$resolved_id" "file_id"

  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM files WHERE id = $resolved_id;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

files_update() {
  ensure_db
  local file_id=""
  local relpath_filter=""
  local new_relpath=""
  local new_description=""
  local relpath_set=0
  local description_set=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --file=*)               relpath_filter="${1#*=}"; shift;;
      --file)                 relpath_filter="$2"; shift 2;;
      --relpath=*)            new_relpath="${1#*=}"; relpath_set=1; shift;;
      --relpath)              new_relpath="$2"; relpath_set=1; shift 2;;
      --description=*)        new_description="${1#*=}"; description_set=1; shift;;
      --description)          new_description="$2"; description_set=1; shift 2;;
      --help|-h)
        fatal "usage: $PROG files update [--file_id=N|--file=PATH] [--relpath=PATH] [--description=TEXT]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for files update: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for files update"
        ;;
    esac
  done

  local resolved_id
  resolved_id="$(resolve_file_id "$file_id" "$relpath_filter")"
  require_integer "$resolved_id" "file_id"

  local -a sets=()
  if [[ $relpath_set -eq 1 ]]; then
    sets+=("relpath = $(sql_quote "$new_relpath")")
  fi
  if [[ $description_set -eq 1 ]]; then
    sets+=("description = $(sql_quote "$new_description")")
  fi
  [[ ${#sets[@]} -gt 0 ]] || fatal "files update requires at least one field to update"
  local set_clause="$(join_with ', ' "${sets[@]}")"

  local sql
  read -r -d '' sql <<EOF || true
UPDATE files
   SET $set_clause
 WHERE id = $resolved_id;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

command_files() {
  [[ $# -ge 1 ]] || fatal "files requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)   files_list "$@";;
    search) files_search "$@";;
    add)    files_add "$@";;
    del|delete|rm)
      files_del "$@"
      ;;
    update) files_update "$@";;
    --help|-h)
      fatal "files subcommands: list, search, add, del, update"
      ;;
    *)
      fatal "unknown files subcommand: $subcommand"
      ;;
  esac
}

defs_list() {
  ensure_db
  local file_filter=""
  local file_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file=*)    file_filter="${1#*=}"; shift;;
      --file)      file_filter="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG defs list [--file=PATH] [--file_id=N]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for defs list: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for defs list"
        ;;
    esac
  done

  local where_clauses=("1=1")
  if [[ -n "$file_id" ]]; then
    require_integer "$file_id" "file_id"
    where_clauses+=("defs.file_id = $file_id")
  elif [[ -n "$file_filter" ]]; then
    local like_file="$(sql_quote "$(wrap_like "$file_filter")")"
    where_clauses+=("LOWER(files.relpath) LIKE LOWER($like_file)")
  fi
  local where_sql="$(join_with ' AND ' "${where_clauses[@]}")"

  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT
  defs.id,
  files.relpath,
  defs.type,
  COALESCE(defs.signature, '')   AS signature,
  COALESCE(defs.parameters, '')  AS parameters,
  COALESCE(defs.description, '') AS description
FROM defs
JOIN files ON files.id = defs.file_id
WHERE $where_sql
ORDER BY files.relpath, defs.type, defs.signature;
EOF
}

defs_search() {
  ensure_db
  local file_filter=""
  local -a terms=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file=*) file_filter="${1#*=}"; shift;;
      --file)   file_filter="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG defs search TERM... [--file=PATH]"
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          terms+=("$1"); shift
        done
        break
        ;;
      -*)
        fatal "unknown flag for defs search: $1"
        ;;
      *)
        terms+=("$1"); shift;;
    esac
  done

  [[ ${#terms[@]} -gt 0 ]] || fatal "defs search requires at least one term"

  local -a where_clauses=("1=1")
  if [[ -n "$file_filter" ]]; then
    local file_like
    file_like="$(sql_quote "$(wrap_like "$file_filter")")"
    where_clauses+=("LOWER(files.relpath) LIKE LOWER($file_like)")
  fi

  for term in "${terms[@]}"; do
    local like_expr
    like_expr="$(sql_quote "$(wrap_like "$term")")"
    local clause="(LOWER(files.relpath) LIKE LOWER($like_expr)"
    clause+=" OR LOWER(COALESCE(defs.signature,'')) LIKE LOWER($like_expr)"
    clause+=" OR LOWER(COALESCE(defs.description,'')) LIKE LOWER($like_expr)"
    clause+=" OR LOWER(COALESCE(defs.parameters,'')) LIKE LOWER($like_expr)"
    clause+=" OR LOWER(COALESCE(defs.type,'')) LIKE LOWER($like_expr))"
    where_clauses+=("$clause")
  done

  local where_sql
  where_sql="$(join_with ' AND ' "${where_clauses[@]}")"

  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT
  defs.id,
  files.relpath,
  defs.type,
  COALESCE(defs.signature, '')   AS signature,
  COALESCE(defs.parameters, '')  AS parameters,
  COALESCE(defs.description, '') AS description
FROM defs
JOIN files ON files.id = defs.file_id
WHERE $where_sql
ORDER BY files.relpath, defs.type, defs.signature;
EOF
}

defs_add() {
  ensure_db
  local file_id=""
  local file_path=""
  local type=""
  local signature=""
  local parameters=""
  local description=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --file=*)               file_path="${1#*=}"; shift;;
      --file)                 file_path="$2"; shift 2;;
      --type=*)               type="${1#*=}"; shift;;
      --type)                 type="$2"; shift 2;;
      --signature=*)          signature="${1#*=}"; shift;;
      --signature)            signature="$2"; shift 2;;
      --parameters=*)         parameters="${1#*=}"; shift;;
      --parameters)           parameters="$2"; shift 2;;
      --description=*)        description="${1#*=}"; shift;;
      --description)          description="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG defs add --file=PATH|--file_id=N --type=TYPE [--signature=SIG] [--parameters=TEXT] [--description=TEXT]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for defs add: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for defs add"
        ;;
    esac
  done

  local resolved_file_id
  resolved_file_id="$(resolve_file_id "$file_id" "$file_path")"

  [[ -n "$type" ]] || fatal "defs add requires --type"

  local type_sql
  type_sql="$(sql_quote "$type")"
  local signature_sql
  signature_sql="$(sql_nullable_text "$signature")"
  local parameters_sql
  parameters_sql="$(sql_nullable_text "$parameters")"
  local description_sql
  description_sql="$(sql_nullable_text "$description")"

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO defs (file_id, type, signature, parameters, description)
VALUES ($resolved_file_id, $type_sql, $signature_sql, $parameters_sql, $description_sql);
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

defs_del() {
  ensure_db
  local def_id=""
  local signature=""
  local file_id=""
  local file_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --def_id=*|--def-id=*) def_id="${1#*=}"; shift;;
      --def_id|--def-id)    def_id="$2"; shift 2;;
      --def=*)              signature="${1#*=}"; shift;;
      --def)                signature="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --file=*)               file_path="${1#*=}"; shift;;
      --file)                 file_path="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG defs del [--def_id=N | --def=SIG [--file=PATH|--file_id=N]]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for defs del: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for defs del"
        ;;
    esac
  done

  local resolved_file_id=""
  if [[ -n "$file_id" || -n "$file_path" ]]; then
    resolved_file_id="$(resolve_file_id "$file_id" "$file_path")"
  fi

  local resolved_def_id
  resolved_def_id="$(resolve_def_id "$def_id" "$signature" "$resolved_file_id")"
  require_integer "$resolved_def_id" "def_id"

  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM defs WHERE id = $resolved_def_id;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

defs_update() {
  ensure_db
  local def_id=""
  local signature=""
  local file_id=""
  local file_path=""
  local new_file_id=""
  local new_file_path=""
  local new_file_flag=0
  local new_type=""
  local new_signature=""
  local new_parameters=""
  local new_description=""
  local type_set=0
  local signature_set=0
  local parameters_set=0
  local description_set=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --def_id=*|--def-id=*) def_id="${1#*=}"; shift;;
      --def_id|--def-id)    def_id="$2"; shift 2;;
      --def=*)              signature="${1#*=}"; shift;;
      --def)                signature="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)    file_id="$2"; shift 2;;
      --file=*)               file_path="${1#*=}"; shift;;
      --file)                 file_path="$2"; shift 2;;
      --new_file_id=*|--new-file-id=*)
        new_file_id="${1#*=}"; new_file_flag=1; shift;;
      --new_file_id|--new-file-id)
        new_file_id="$2"; new_file_flag=1; shift 2;;
      --new_file=*|--new-file=*)
        new_file_path="${1#*=}"; new_file_flag=1; shift;;
      --new_file|--new-file)
        new_file_path="$2"; new_file_flag=1; shift 2;;
      --type=*)
        new_type="${1#*=}"; type_set=1; shift;;
      --type)
        new_type="$2"; type_set=1; shift 2;;
      --signature=*)
        new_signature="${1#*=}"; signature_set=1; shift;;
      --signature)
        new_signature="$2"; signature_set=1; shift 2;;
      --parameters=*)
        new_parameters="${1#*=}"; parameters_set=1; shift;;
      --parameters)
        new_parameters="$2"; parameters_set=1; shift 2;;
      --description=*)
        new_description="${1#*=}"; description_set=1; shift;;
      --description)
        new_description="$2"; description_set=1; shift 2;;
      --help|-h)
        fatal "usage: $PROG defs update [--def_id=N | --def=SIG [--file=PATH|--file_id=N]] [--type=TYPE] [--signature=SIG] [--parameters=TEXT] [--description=TEXT] [--new_file=PATH|--new_file_id=N]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for defs update: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for defs update"
        ;;
    esac
  done

  local resolved_file_id=""
  if [[ -n "$file_id" || -n "$file_path" ]]; then
    resolved_file_id="$(resolve_file_id "$file_id" "$file_path")"
  fi

  local resolved_def_id
  resolved_def_id="$(resolve_def_id "$def_id" "$signature" "$resolved_file_id")"
  require_integer "$resolved_def_id" "def_id"

  local -a sets=()
  if [[ $type_set -eq 1 ]]; then
    sets+=("type = $(sql_quote "$new_type")")
  fi
  if [[ $signature_set -eq 1 ]]; then
    sets+=("signature = $(sql_quote "$new_signature")")
  fi
  if [[ $parameters_set -eq 1 ]]; then
    sets+=("parameters = $(sql_quote "$new_parameters")")
  fi
  if [[ $description_set -eq 1 ]]; then
    sets+=("description = $(sql_quote "$new_description")")
  fi
  if [[ $new_file_flag -eq 1 ]]; then
    local resolved_new_file
    resolved_new_file="$(resolve_file_id "$new_file_id" "$new_file_path")"
    sets+=("file_id = $resolved_new_file")
  fi
  [[ ${#sets[@]} -gt 0 ]] || fatal "defs update requires at least one field flag"
  local set_clause="$(join_with ', ' "${sets[@]}")"

  local sql
  read -r -d '' sql <<EOF || true
UPDATE defs
   SET $set_clause
 WHERE id = $resolved_def_id;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

command_defs() {
  [[ $# -ge 1 ]] || fatal "defs requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)   defs_list "$@";;
    search) defs_search "$@";;
    add)    defs_add "$@";;
    del|delete|rm)
      defs_del "$@"
      ;;
    update) defs_update "$@";;
    --help|-h)
      fatal "defs subcommands: list, search, add, del, update"
      ;;
    *)
      fatal "unknown defs subcommand: $subcommand"
      ;;
  esac
}

resolve_api_id() {
  local provided_id="$1"
  local signature="${2:-}"
  local file_id="${3:-}"

  if [[ -n "$provided_id" ]]; then
    require_integer "$provided_id" "api id"
    printf '%s' "$provided_id"
    return
  fi
  [[ -n "$signature" ]] || fatal "api identifier required; provide --id or --signature"

  ensure_db
  local where_parts=("signature = $(sql_quote "$signature")")
  if [[ -n "$file_id" ]]; then
    where_parts+=("file_id = $file_id")
  fi
  local sql
  sql="SELECT id FROM api WHERE $(join_with ' AND ' "${where_parts[@]}") ORDER BY id;"
  local -a ids=()
  sql_collect ids "$sql"
  if [[ ${#ids[@]} -eq 0 ]]; then
    fatal "no api rows match selector"
  fi
  if [[ ${#ids[@]} -gt 1 ]]; then
    fatal "multiple api rows match selector; add --id or --file"
  fi
  printf '%s' "${ids[0]}"
}

api_list() {
  ensure_db
  local file_filter=""
  local file_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file=*) file_filter="${1#*=}"; shift;;
      --file)   file_filter="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)     file_id="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG api list [--file=REL|--file_id=N]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for api list: $1";;
    esac
  done
  local args=(--table api)
  if [[ -n "$file_id" ]]; then
    require_integer "$file_id" "file_id"
    args+=(--where "api.file_id = $file_id")
  elif [[ -n "$file_filter" ]]; then
    args+=(--relpath "$file_filter")
  fi
  command_query "${args[@]}"
}

api_search() {
  ensure_db
  local file_filter=""
  local -a terms=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file=*) file_filter="${1#*=}"; shift;;
      --file)   file_filter="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG api search TERM... [--file=REL]"
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do terms+=("$1"); shift; done
        break
        ;;
      -*)
        fatal "unknown flag for api search: $1"
        ;;
      *)
        terms+=("$1"); shift;;
    esac
  done
  [[ ${#terms[@]} -gt 0 ]] || fatal "api search requires at least one term"
  local args=(--table api --limit 20)
  [[ -n "$file_filter" ]] && args+=(--relpath "$file_filter")
  for term in "${terms[@]}"; do
    args+=(--search "$term")
  done
  command_query "${args[@]}"
}

api_add() {
  ensure_db
  local file_id=""
  local file_path=""
  local def_id=""
  local def_signature=""
  local signature=""
  local description=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)     file_id="$2"; shift 2;;
      --file=*)                file_path="${1#*=}"; shift;;
      --file)                  file_path="$2"; shift 2;;
      --def_id=*|--def-id=*)   def_id="${1#*=}"; shift;;
      --def_id|--def-id)       def_id="$2"; shift 2;;
      --def=*)                 def_signature="${1#*=}"; shift;;
      --def)                   def_signature="$2"; shift 2;;
      --signature=*)           signature="${1#*=}"; shift;;
      --signature)             signature="$2"; shift 2;;
      --description=*)         description="${1#*=}"; shift;;
      --description)           description="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG api add --file=REL|--file_id=N [--def=SIG|--def_id=N] --signature=SIG [--description=TEXT]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for api add: $1";;
    esac
  done

  local resolved_file_id
  resolved_file_id="$(resolve_file_id "$file_id" "$file_path")"
  local resolved_def_id=""
  if [[ -n "$def_id" || -n "$def_signature" ]]; then
    resolved_def_id="$(resolve_def_id "$def_id" "$def_signature" "$resolved_file_id")"
  fi
  [[ -n "$signature" ]] || fatal "api add requires --signature"

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO api (file_id, def_id, signature, description)
VALUES ($resolved_file_id, $(sql_nullable_int "$resolved_def_id"), $(sql_quote "$signature"), $(sql_nullable_text "$description"));
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

api_del() {
  ensure_db
  local api_id=""
  local signature=""
  local file_id=""
  local file_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*|--api_id=*|--api-id=*) api_id="${1#*=}"; shift;;
      --id|--api_id|--api-id)       api_id="$2"; shift 2;;
      --signature=*)                signature="${1#*=}"; shift;;
      --signature)                  signature="$2"; shift 2;;
      --file_id=*|--file-id=*)      file_id="${1#*=}"; shift;;
      --file_id|--file-id)          file_id="$2"; shift 2;;
      --file=*)                     file_path="${1#*=}"; shift;;
      --file)                       file_path="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG api del [--id=N | --signature=SIG [--file=REL|--file_id=N]]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for api del: $1";;
    esac
  done
  local resolved_file_id=""
  if [[ -n "$file_id" || -n "$file_path" ]]; then
    resolved_file_id="$(resolve_file_id "$file_id" "$file_path")"
  fi
  local resolved_api_id
  resolved_api_id="$(resolve_api_id "$api_id" "$signature" "$resolved_file_id")"
  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM api WHERE id = $resolved_api_id;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

api_update() {
  ensure_db
  local api_id=""
  local signature_filter=""
  local file_id=""
  local file_path=""
  local new_signature=""
  local new_description=""
  local new_file_id=""
  local new_file_path=""
  local new_def_id=""
  local new_def_signature=""
  local signature_set=0
  local description_set=0
  local file_set=0
  local def_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*|--api_id=*|--api-id=*) api_id="${1#*=}"; shift;;
      --id|--api_id|--api-id)       api_id="$2"; shift 2;;
      --signature-filter=*)         signature_filter="${1#*=}"; shift;;
      --signature-filter)           signature_filter="$2"; shift 2;;
      --file_id=*|--file-id=*)      file_id="${1#*=}"; shift;;
      --file_id|--file-id)          file_id="$2"; shift 2;;
      --file=*)                     file_path="${1#*=}"; shift;;
      --file)                       file_path="$2"; shift 2;;
      --signature=*)                new_signature="${1#*=}"; signature_set=1; shift;;
      --signature)                  new_signature="$2"; signature_set=1; shift 2;;
      --description=*)              new_description="${1#*=}"; description_set=1; shift;;
      --description)                new_description="$2"; description_set=1; shift 2;;
      --new_file_id=*|--new-file-id=*) new_file_id="${1#*=}"; file_set=1; shift;;
      --new_file_id|--new-file-id)     new_file_id="$2"; file_set=1; shift 2;;
      --new_file=*|--new-file=*)       new_file_path="${1#*=}"; file_set=1; shift;;
      --new_file|--new-file)           new_file_path="$2"; file_set=1; shift 2;;
      --def_id=*|--def-id=*)        new_def_id="${1#*=}"; def_set=1; shift;;
      --def_id|--def-id)            new_def_id="$2"; def_set=1; shift 2;;
      --def=*)                      new_def_signature="${1#*=}"; def_set=1; shift;;
      --def)                        new_def_signature="$2"; def_set=1; shift 2;;
      --help|-h)
        fatal "usage: $PROG api update [--id=N|--signature-filter=SIG [--file=REL|--file_id=N]] [--signature=SIG] [--description=TEXT] [--new_file=REL|--new_file_id=N] [--def=SIG|--def_id=N]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for api update: $1";;
    esac
  done
  local selector_file_id=""
  if [[ -n "$file_id" || -n "$file_path" ]]; then
    selector_file_id="$(resolve_file_id "$file_id" "$file_path")"
  fi
  local resolved_api_id
  resolved_api_id="$(resolve_api_id "$api_id" "$signature_filter" "$selector_file_id")"

  local -a sets=()
  if [[ $signature_set -eq 1 ]]; then
    [[ -n "$new_signature" ]] || fatal "--signature cannot be empty"
    sets+=("signature = $(sql_quote "$new_signature")")
  fi
  if [[ $description_set -eq 1 ]]; then
    sets+=("description = $(sql_quote "$new_description")")
  fi
  if [[ $file_set -eq 1 ]]; then
    local resolved_new_file
    resolved_new_file="$(resolve_file_id "$new_file_id" "$new_file_path")"
    sets+=("file_id = $resolved_new_file")
  fi
  if [[ $def_set -eq 1 ]]; then
    local resolved_new_def=""
    if [[ -n "$new_def_id" || -n "$new_def_signature" ]]; then
      local def_scope_file=""
      if [[ $file_set -eq 1 ]]; then
        def_scope_file="$(resolve_file_id "$new_file_id" "$new_file_path")"
      fi
      resolved_new_def="$(resolve_def_id "$new_def_id" "$new_def_signature" "$def_scope_file")"
    fi
    sets+=("def_id = $(sql_nullable_int "$resolved_new_def")")
  fi

  [[ ${#sets[@]} -gt 0 ]] || fatal "api update requires at least one field to update"
  local set_clause
  set_clause="$(join_with ', ' "${sets[@]}")"
  local sql
  read -r -d '' sql <<EOF || true
UPDATE api
   SET $set_clause
 WHERE id = $resolved_api_id;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

command_api() {
  [[ $# -ge 1 ]] || fatal "api requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)   api_list "$@";;
    search) api_search "$@";;
    add)    api_add "$@";;
    del|delete|rm) api_del "$@";;
    update) api_update "$@";;
    --help|-h) fatal "api subcommands: list, search, add, del, update";;
    *) fatal "unknown api subcommand: $subcommand";;
  esac
}

deps_list() {
  ensure_db
  local -a where_clauses=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --def_id=*|--def-id=*) where_clauses+=("deps.def_id = ${1#*=}"); shift;;
      --def_id|--def-id)     where_clauses+=("deps.def_id = $2"); shift 2;;
      --file_id=*|--file-id=*) where_clauses+=("deps.file_id = ${1#*=}"); shift;;
      --file_id|--file-id)     where_clauses+=("deps.file_id = $2"); shift 2;;
      --dep_def_id=*|--dep-def-id=*) where_clauses+=("deps.dep_def_id = ${1#*=}"); shift;;
      --dep_def_id|--dep-def-id)     where_clauses+=("deps.dep_def_id = $2"); shift 2;;
      --dep_file_id=*|--dep-file-id=*) where_clauses+=("deps.dep_file_id = ${1#*=}"); shift;;
      --dep_file_id|--dep-file-id)     where_clauses+=("deps.dep_file_id = $2"); shift 2;;
      --help|-h)
        fatal "usage: $PROG deps list [--def_id=N] [--file_id=N] [--dep_def_id=N] [--dep_file_id=N]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for deps list: $1";;
    esac
  done
  local args=(--table deps)
  if [[ ${#where_clauses[@]} -gt 0 ]]; then
    args+=(--where "$(join_with ' AND ' "${where_clauses[@]}")")
  fi
  command_query "${args[@]}"
}

deps_search() {
  ensure_db
  local -a terms=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) fatal "usage: $PROG deps search TERM...";;
      --) shift; while [[ $# -gt 0 ]]; do terms+=("$1"); shift; done; break;;
      -*) fatal "unknown flag for deps search: $1";;
      *) terms+=("$1"); shift;;
    esac
  done
  [[ ${#terms[@]} -gt 0 ]] || fatal "deps search requires at least one term"
  local args=(--table deps --limit 20)
  for term in "${terms[@]}"; do args+=(--search "$term"); done
  command_query "${args[@]}"
}

deps_add() {
  ensure_db
  local def_id=""
  local def_sig=""
  local file_id=""
  local file_path=""
  local dep_def_id=""
  local dep_def_sig=""
  local dep_file_id=""
  local dep_file_path=""
  local description=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --def_id=*|--def-id=*) def_id="${1#*=}"; shift;;
      --def_id|--def-id)     def_id="$2"; shift 2;;
      --def=*)               def_sig="${1#*=}"; shift;;
      --def)                 def_sig="$2"; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; shift;;
      --file_id|--file-id)     file_id="$2"; shift 2;;
      --file=*)                 file_path="${1#*=}"; shift;;
      --file)                   file_path="$2"; shift 2;;
      --dep_def_id=*|--dep-def-id=*) dep_def_id="${1#*=}"; shift;;
      --dep_def_id|--dep-def-id)     dep_def_id="$2"; shift 2;;
      --dep_def=*|--dep-def=*)       dep_def_sig="${1#*=}"; shift;;
      --dep_def|--dep-def)           dep_def_sig="$2"; shift 2;;
      --dep_file_id=*|--dep-file-id=*) dep_file_id="${1#*=}"; shift;;
      --dep_file_id|--dep-file-id)     dep_file_id="$2"; shift 2;;
      --dep_file=*|--dep-file=*)       dep_file_path="${1#*=}"; shift;;
      --dep_file|--dep-file)           dep_file_path="$2"; shift 2;;
      --description=*) description="${1#*=}"; shift;;
      --description)   description="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG deps add [--def=SIG|--def_id=N] [--file=REL|--file_id=N] [--dep_def=SIG|--dep_def_id=N] [--dep_file=REL|--dep_file_id=N] [--description=TEXT]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for deps add: $1";;
    esac
  done
  local resolved_file_id=""
  local resolved_dep_file_id=""
  [[ -n "$file_id" || -n "$file_path" ]] && resolved_file_id="$(resolve_file_id "$file_id" "$file_path")"
  [[ -n "$dep_file_id" || -n "$dep_file_path" ]] && resolved_dep_file_id="$(resolve_file_id "$dep_file_id" "$dep_file_path")"
  local resolved_def_id=""
  local resolved_dep_def_id=""
  [[ -n "$def_id" || -n "$def_sig" ]] && resolved_def_id="$(resolve_def_id "$def_id" "$def_sig" "$resolved_file_id")"
  [[ -n "$dep_def_id" || -n "$dep_def_sig" ]] && resolved_dep_def_id="$(resolve_def_id "$dep_def_id" "$dep_def_sig" "$resolved_dep_file_id")"

  if [[ -z "$resolved_def_id" && -z "$resolved_file_id" && -z "$resolved_dep_def_id" && -z "$resolved_dep_file_id" ]]; then
    fatal "deps add requires at least one source or dependency selector"
  fi

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO deps (def_id, file_id, dep_def_id, dep_file_id, description)
VALUES ($(sql_nullable_int "$resolved_def_id"), $(sql_nullable_int "$resolved_file_id"), $(sql_nullable_int "$resolved_dep_def_id"), $(sql_nullable_int "$resolved_dep_file_id"), $(sql_nullable_text "$description"));
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

deps_del() {
  ensure_db
  [[ $# -ge 1 ]] || fatal "deps del requires --id N"
  local dep_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*|--dep_id=*|--dep-id=*) dep_id="${1#*=}"; shift;;
      --id|--dep_id|--dep-id)       dep_id="$2"; shift 2;;
      --help|-h) fatal "usage: $PROG deps del --id N";;
      --) shift; break;;
      *) fatal "unknown flag for deps del: $1";;
    esac
  done
  [[ -n "$dep_id" ]] || fatal "deps del requires --id"
  require_integer "$dep_id" "dep id"
  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM deps WHERE id = $dep_id;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

deps_update() {
  ensure_db
  local dep_id=""
  local def_id=""
  local def_sig=""
  local file_id=""
  local file_path=""
  local dep_def_id=""
  local dep_def_sig=""
  local dep_file_id=""
  local dep_file_path=""
  local description=""
  local def_set=0
  local file_set=0
  local dep_def_set=0
  local dep_file_set=0
  local description_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*|--dep_id=*|--dep-id=*) dep_id="${1#*=}"; shift;;
      --id|--dep_id|--dep-id)       dep_id="$2"; shift 2;;
      --def_id=*|--def-id=*) def_id="${1#*=}"; def_set=1; shift;;
      --def_id|--def-id)     def_id="$2"; def_set=1; shift 2;;
      --def=*)               def_sig="${1#*=}"; def_set=1; shift;;
      --def)                 def_sig="$2"; def_set=1; shift 2;;
      --file_id=*|--file-id=*) file_id="${1#*=}"; file_set=1; shift;;
      --file_id|--file-id)     file_id="$2"; file_set=1; shift 2;;
      --file=*)                 file_path="${1#*=}"; file_set=1; shift;;
      --file)                   file_path="$2"; file_set=1; shift 2;;
      --dep_def_id=*|--dep-def-id=*) dep_def_id="${1#*=}"; dep_def_set=1; shift;;
      --dep_def_id|--dep-def-id)     dep_def_id="$2"; dep_def_set=1; shift 2;;
      --dep_def=*|--dep-def=*)       dep_def_sig="${1#*=}"; dep_def_set=1; shift;;
      --dep_def|--dep-def)           dep_def_sig="$2"; dep_def_set=1; shift 2;;
      --dep_file_id=*|--dep-file-id=*) dep_file_id="${1#*=}"; dep_file_set=1; shift;;
      --dep_file_id|--dep-file-id)     dep_file_id="$2"; dep_file_set=1; shift 2;;
      --dep_file=*|--dep-file=*)       dep_file_path="${1#*=}"; dep_file_set=1; shift;;
      --dep_file|--dep-file)           dep_file_path="$2"; dep_file_set=1; shift 2;;
      --description=*) description="${1#*=}"; description_set=1; shift;;
      --description)   description="$2"; description_set=1; shift 2;;
      --help|-h)
        fatal "usage: $PROG deps update --id N [--def=SIG|--def_id=N] [--file=REL|--file_id=N] [--dep_def=SIG|--dep_def_id=N] [--dep_file=REL|--dep_file_id=N] [--description=TEXT]"
        ;;
      --) shift; break;;
      *) fatal "unknown flag for deps update: $1";;
    esac
  done
  [[ -n "$dep_id" ]] || fatal "deps update requires --id"
  require_integer "$dep_id" "dep id"

  local -a sets=()
  if [[ $def_set -eq 1 ]]; then
    local resolved_def=""
    [[ -n "$def_id" || -n "$def_sig" ]] && resolved_def="$(resolve_def_id "$def_id" "$def_sig" "")"
    sets+=("def_id = $(sql_nullable_int "$resolved_def")")
  fi
  if [[ $file_set -eq 1 ]]; then
    local resolved_file=""
    [[ -n "$file_id" || -n "$file_path" ]] && resolved_file="$(resolve_file_id "$file_id" "$file_path")"
    sets+=("file_id = $(sql_nullable_int "$resolved_file")")
  fi
  if [[ $dep_def_set -eq 1 ]]; then
    local resolved_dep_def=""
    [[ -n "$dep_def_id" || -n "$dep_def_sig" ]] && resolved_dep_def="$(resolve_def_id "$dep_def_id" "$dep_def_sig" "")"
    sets+=("dep_def_id = $(sql_nullable_int "$resolved_dep_def")")
  fi
  if [[ $dep_file_set -eq 1 ]]; then
    local resolved_dep_file=""
    [[ -n "$dep_file_id" || -n "$dep_file_path" ]] && resolved_dep_file="$(resolve_file_id "$dep_file_id" "$dep_file_path")"
    sets+=("dep_file_id = $(sql_nullable_int "$resolved_dep_file")")
  fi
  if [[ $description_set -eq 1 ]]; then
    sets+=("description = $(sql_quote "$description")")
  fi
  [[ ${#sets[@]} -gt 0 ]] || fatal "deps update requires at least one field to update"
  local set_clause
  set_clause="$(join_with ', ' "${sets[@]}")"
  local sql
  read -r -d '' sql <<EOF || true
UPDATE deps
   SET $set_clause
 WHERE id = $dep_id;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

command_deps() {
  [[ $# -ge 1 ]] || fatal "deps requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)   deps_list "$@";;
    search) deps_search "$@";;
    add)    deps_add "$@";;
    del|delete|rm) deps_del "$@";;
    update) deps_update "$@";;
    --help|-h) fatal "deps subcommands: list, search, add, del, update";;
    *) fatal "unknown deps subcommand: $subcommand";;
  esac
}

module_pattern_to_like() {
  local pattern="$1"
  if [[ "$pattern" == *"*"* || "$pattern" == *"?"* ]]; then
    pattern="${pattern//\*/%}"
    pattern="${pattern//\?/_}"
    printf '%s' "$pattern"
    return
  fi
  wrap_like "$pattern"
}

module_registry_base_dir() {
  local base="."
  if [[ "$DB_PATH" == */* ]]; then
    base="${DB_PATH%/*}"
    [[ -n "$base" ]] || base="."
  fi
  printf '%s' "$base"
}

resolve_registered_module_path() {
  local module_path="$1"
  if [[ "$module_path" == /* ]]; then
    printf '%s' "$module_path"
    return
  fi
  local base
  base="$(module_registry_base_dir)"
  if [[ "$base" == "." ]]; then
    printf '%s' "$module_path"
  else
    printf '%s/%s' "$base" "$module_path"
  fi
}

resolve_module_db_path() {
  local module_path="$1"
  if [[ "$module_path" == *.db || "$module_path" == *.sqlite || "$module_path" == *.sqlite3 ]]; then
    printf '%s' "$module_path"
    return
  fi
  if [[ -f "$module_path" ]]; then
    printf '%s' "$module_path"
    return
  fi
  printf '%s/WHEEL.db' "$module_path"
}

collect_module_rows_by_patterns() {
  local -n out_rows_ref="$1"
  shift
  local -a patterns=("$@")

  ensure_db
  local -a where_clauses=("1=1")
  if [[ ${#patterns[@]} -gt 0 ]]; then
    local -a pattern_clauses=()
    for pattern in "${patterns[@]}"; do
      local like_expr
      like_expr="$(sql_quote "$(module_pattern_to_like "$pattern")")"
      pattern_clauses+=("(LOWER(name) LIKE LOWER($like_expr) OR LOWER(path) LIKE LOWER($like_expr))")
    done
    where_clauses+=("($(join_with ' OR ' "${pattern_clauses[@]}"))")
  fi

  local where_sql
  where_sql="$(join_with ' AND ' "${where_clauses[@]}")"
  local sql=$'SELECT id, name, path, COALESCE(description, \'\'), COALESCE(dependencies, \'\')\n  FROM modules\n WHERE %s\n ORDER BY name, id;'
  sql="$(printf "$sql" "$where_sql")"

  mapfile -t out_rows_ref < <(sqlite3 -batch -noheader -separator $'\t' "$DB_PATH" "$sql")
}

resolve_module_id() {
  local module_id="$1"
  local module_name="$2"
  local module_path="$3"

  local selectors=0
  [[ -n "$module_id" ]] && selectors=$((selectors + 1))
  [[ -n "$module_name" ]] && selectors=$((selectors + 1))
  [[ -n "$module_path" ]] && selectors=$((selectors + 1))
  [[ $selectors -eq 1 ]] || fatal "select exactly one module selector: --id, --name, or --path"

  ensure_db
  if [[ -n "$module_id" ]]; then
    require_integer "$module_id" "module id"
    printf '%s' "$module_id"
    return
  fi

  local where_clause=""
  if [[ -n "$module_name" ]]; then
    where_clause="name = $(sql_quote "$module_name")"
  else
    where_clause="path = $(sql_quote "$module_path")"
  fi

  local -a ids=()
  sql_collect ids "SELECT id FROM modules WHERE $where_clause ORDER BY id"
  if [[ ${#ids[@]} -eq 0 ]]; then
    fatal "no module matches selector"
  fi
  if [[ ${#ids[@]} -gt 1 ]]; then
    fatal "selector matched multiple modules; use --id"
  fi
  printf '%s' "${ids[0]}"
}

modules_list() {
  ensure_db
  sqlite3 "$DB_PATH" <<'SQL'
.timer off
.headers on
.mode column
SELECT id, name, path, COALESCE(description, '') AS description, COALESCE(dependencies, '') AS dependencies
FROM modules
ORDER BY name, id;
SQL
}

modules_search() {
  ensure_db
  local -a terms=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        fatal "usage: $PROG modules search TERM..."
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          terms+=("$1"); shift
        done
        break
        ;;
      -*)
        fatal "unknown flag for modules search: $1"
        ;;
      *)
        terms+=("$1"); shift;;
    esac
  done

  [[ ${#terms[@]} -gt 0 ]] || fatal "modules search requires at least one term"

  local -a where_clauses=("1=1")
  for term in "${terms[@]}"; do
    local like_expr
    like_expr="$(sql_quote "$(wrap_like "$term")")"
    where_clauses+=("(LOWER(name) LIKE LOWER($like_expr) OR LOWER(path) LIKE LOWER($like_expr) OR LOWER(COALESCE(description,'')) LIKE LOWER($like_expr) OR LOWER(COALESCE(dependencies,'')) LIKE LOWER($like_expr))")
  done

  local where_sql
  where_sql="$(join_with ' AND ' "${where_clauses[@]}")"
  sqlite3 "$DB_PATH" <<EOF
.timer off
.headers on
.mode column
SELECT id, name, path, COALESCE(description, '') AS description, COALESCE(dependencies, '') AS dependencies
FROM modules
WHERE $where_sql
ORDER BY name, id;
EOF
}

modules_add() {
  ensure_db
  local name=""
  local path=""
  local description=""
  local dependencies=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name=*) name="${1#*=}"; shift;;
      --name)   name="$2"; shift 2;;
      --path=*) path="${1#*=}"; shift;;
      --path)   path="$2"; shift 2;;
      --description=*) description="${1#*=}"; shift;;
      --description)   description="$2"; shift 2;;
      --dependencies=*) dependencies="${1#*=}"; shift;;
      --dependencies)   dependencies="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG modules add --name=NAME --path=PATH [--description=TEXT] [--dependencies=CSV]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for modules add: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for modules add"
        ;;
    esac
  done

  [[ -n "$name" ]] || fatal "modules add requires --name"
  [[ -n "$path" ]] || fatal "modules add requires --path"

  local sql
  read -r -d '' sql <<EOF || true
BEGIN;
INSERT INTO modules (name, path, description, dependencies)
VALUES ($(sql_quote "$name"), $(sql_quote "$path"), $(sql_nullable_text "$description"), $(sql_nullable_text "$dependencies"));
SELECT last_insert_rowid() AS last_insert_rowid;
COMMIT;
EOF
  run_mutation_sql "$sql"
}

modules_update() {
  ensure_db
  local selector_id=""
  local selector_name=""
  local selector_path=""
  local new_name=""
  local new_path=""
  local description=""
  local dependencies=""
  local name_set=0
  local path_set=0
  local description_set=0
  local dependencies_set=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*) selector_id="${1#*=}"; shift;;
      --id)   selector_id="$2"; shift 2;;
      --name=*) selector_name="${1#*=}"; shift;;
      --name)   selector_name="$2"; shift 2;;
      --path=*) selector_path="${1#*=}"; shift;;
      --path)   selector_path="$2"; shift 2;;
      --new-name=*) new_name="${1#*=}"; name_set=1; shift;;
      --new-name)   new_name="$2"; name_set=1; shift 2;;
      --new-path=*) new_path="${1#*=}"; path_set=1; shift;;
      --new-path)   new_path="$2"; path_set=1; shift 2;;
      --description=*) description="${1#*=}"; description_set=1; shift;;
      --description)   description="$2"; description_set=1; shift 2;;
      --dependencies=*) dependencies="${1#*=}"; dependencies_set=1; shift;;
      --dependencies)   dependencies="$2"; dependencies_set=1; shift 2;;
      --help|-h)
        fatal "usage: $PROG modules update [--id=ID|--name=NAME|--path=PATH] [--new-name=NAME] [--new-path=PATH] [--description=TEXT] [--dependencies=CSV]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for modules update: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for modules update"
        ;;
    esac
  done

  local resolved_id
  resolved_id="$(resolve_module_id "$selector_id" "$selector_name" "$selector_path")"
  require_integer "$resolved_id" "module id"

  local -a sets=()
  if [[ $name_set -eq 1 ]]; then
    [[ -n "$new_name" ]] || fatal "--new-name cannot be empty"
    sets+=("name = $(sql_quote "$new_name")")
  fi
  if [[ $path_set -eq 1 ]]; then
    [[ -n "$new_path" ]] || fatal "--new-path cannot be empty"
    sets+=("path = $(sql_quote "$new_path")")
  fi
  if [[ $description_set -eq 1 ]]; then
    sets+=("description = $(sql_quote "$description")")
  fi
  if [[ $dependencies_set -eq 1 ]]; then
    sets+=("dependencies = $(sql_quote "$dependencies")")
  fi
  [[ ${#sets[@]} -gt 0 ]] || fatal "modules update requires at least one field to update"
  local set_clause
  set_clause="$(join_with ', ' "${sets[@]}")"

  local sql
  read -r -d '' sql <<EOF || true
UPDATE modules
   SET $set_clause
 WHERE id = $resolved_id;
SELECT changes() AS rows_changed;
EOF
  run_mutation_sql "$sql"
}

modules_del() {
  ensure_db
  local selector_id=""
  local selector_name=""
  local selector_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*) selector_id="${1#*=}"; shift;;
      --id)   selector_id="$2"; shift 2;;
      --name=*) selector_name="${1#*=}"; shift;;
      --name)   selector_name="$2"; shift 2;;
      --path=*) selector_path="${1#*=}"; shift;;
      --path)   selector_path="$2"; shift 2;;
      --help|-h)
        fatal "usage: $PROG modules del [--id=ID|--name=NAME|--path=PATH]"
        ;;
      --) shift; break;;
      -*)
        fatal "unknown flag for modules del: $1"
        ;;
      *)
        fatal "unexpected positional argument '$1' for modules del"
        ;;
    esac
  done

  local resolved_id
  resolved_id="$(resolve_module_id "$selector_id" "$selector_name" "$selector_path")"
  require_integer "$resolved_id" "module id"

  local sql
  read -r -d '' sql <<EOF || true
DELETE FROM modules WHERE id = $resolved_id;
SELECT changes() AS rows_deleted;
EOF
  run_mutation_sql "$sql"
}

run_across_modules() {
  local mode="$1"
  shift
  local -a module_patterns=()
  local -a passthrough=()
  local strict_mode=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --module=*) module_patterns+=("${1#*=}"); shift;;
      --module|-m)
        [[ $# -ge 2 ]] || fatal "--module expects a pattern"
        module_patterns+=("$2"); shift 2;;
      --strict) strict_mode=1; shift;;
      --help|-h)
        if [[ "$mode" == "query" ]]; then
          fatal "usage: $PROG modules query [--module PATTERN]... [--strict] [QUERY ARGS...]"
        else
          fatal "usage: $PROG modules xsearch [--module PATTERN]... [--strict] [SEARCH ARGS...]"
        fi
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          passthrough+=("$1"); shift
        done
        break
        ;;
      *)
        passthrough+=("$1"); shift;;
    esac
  done

  if [[ ${#module_patterns[@]} -eq 0 ]]; then
    module_patterns=("*")
  fi
  if [[ "$mode" == "query" && ${#passthrough[@]} -eq 0 ]]; then
    passthrough=("defs" "--limit" "20")
  fi
  if [[ "$mode" == "search" && ${#passthrough[@]} -eq 0 ]]; then
    fatal "modules xsearch requires search terms or explicit search args"
  fi

  local -a module_rows=()
  collect_module_rows_by_patterns module_rows "${module_patterns[@]}"
  if [[ ${#module_rows[@]} -eq 0 ]]; then
    fatal "no modules match requested pattern(s)"
  fi

  local first_section=1
  local had_errors=0
  local ran_count=0
  for row in "${module_rows[@]}"; do
    local module_id=""
    local module_name=""
    local module_path=""
    local module_desc=""
    local module_deps=""
    IFS=$'\t' read -r module_id module_name module_path module_desc module_deps <<< "$row"

    if [[ -z "$module_path" ]]; then
      warn "module '$module_name' has empty path; skipping"
      had_errors=1
      continue
    fi

    local absolute_module_path
    absolute_module_path="$(resolve_registered_module_path "$module_path")"
    local module_db
    module_db="$(resolve_module_db_path "$absolute_module_path")"
    if [[ ! -f "$module_db" ]]; then
      warn "module '$module_name' database not found at $module_db; skipping"
      had_errors=1
      continue
    fi

    if [[ $first_section -eq 0 ]]; then
      printf '\n'
    fi
    printf '%s\n' "-- module:$module_name db:$module_db --"
    first_section=0

    if [[ "$mode" == "query" ]]; then
      (DB_PATH="$module_db" PARAM_STATE="" SQLITE_PRAGMA_DB_PATH="" command_query "${passthrough[@]}")
    else
      (DB_PATH="$module_db" PARAM_STATE="" SQLITE_PRAGMA_DB_PATH="" command_search "${passthrough[@]}")
    fi
    local rc=$?
    if [[ $rc -ne 0 ]]; then
      warn "command failed for module '$module_name'"
      had_errors=1
      if [[ $strict_mode -eq 1 ]]; then
        fatal "aborting due to --strict after module command failure"
      fi
    else
      ran_count=$((ran_count + 1))
    fi
  done

  if [[ $ran_count -eq 0 ]]; then
    fatal "no module databases were successfully queried"
  fi
  if [[ $strict_mode -eq 1 && $had_errors -eq 1 ]]; then
    fatal "aborting due to --strict after module command errors"
  fi
}

command_modules() {
  [[ $# -ge 1 ]] || fatal "modules requires subcommand"
  local subcommand="$1"; shift
  case "$subcommand" in
    list)    modules_list "$@";;
    search)  modules_search "$@";;
    add)     modules_add "$@";;
    update)  modules_update "$@";;
    del|delete|rm)
      modules_del "$@"
      ;;
    query)
      run_across_modules "query" "$@"
      ;;
    xsearch|cross-search|cross_search)
      run_across_modules "search" "$@"
      ;;
    --help|-h)
      fatal "modules subcommands: list, search, add, update, del, query, xsearch"
      ;;
    *)
      fatal "unknown modules subcommand: $subcommand"
      ;;
  esac
}

main() {
  require_integer "$SQLITE_BUSY_TIMEOUT_MS" "WHEEL_SQLITE_BUSY_TIMEOUT_MS"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --database) DB_PATH="$2"; PARAM_STATE=""; shift 2;;
      --force-params) PARAM_PREF="on"; PARAM_STATE=""; shift;;
      --no-params) PARAM_PREF="off"; PARAM_STATE=""; shift;;
      --verbose) VERBOSE=1; shift;;
      -h|--help) usage; exit 0;;
      query|search|insert|update|delete|describe|plan|raw)
        local command="$1"; shift
        case "$command" in
          query)    command_query "$@"; return;;
          search)   command_search "$@"; return;;
          insert)   command_insert "$@"; return;;
          update)   command_update "$@"; return;;
          delete)   command_delete "$@"; return;;
          describe) command_describe "$@"; return;;
          plan)     command_plan "$@"; return;;
          raw)      command_raw "$@"; return;;
        esac
        ;;
      module|modules|dep|deps|api|apis|todo|changes|files|defs)
        local shortcut="$1"; shift
        case "$shortcut" in
          module|modules) command_modules "$@"; return;;
          dep|deps)       command_deps "$@"; return;;
          api|apis)       command_api "$@"; return;;
          todo)    command_todo "$@"; return;;
          changes) command_changes "$@"; return;;
          files)   command_files "$@"; return;;
          defs)    command_defs "$@"; return;;
        esac
        ;;
      --*)
        command_query "$@"
        return
        ;;
      *)
        command_query "$@"
        return
        ;;
    esac
  done
  command_query --limit 50
}

main "$@"
