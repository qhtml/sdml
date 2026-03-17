#!/usr/bin/env bash

set -o pipefail

DEFAULT_FILTERS=(
  "*.c" "*.cc" "*.cpp" "*.cxx" "*.h" "*.hpp" "*.hh" "*.hxx"
  "*.qml" "*.py" "*.sh" "*.js" "*.mjs" "*.html" "*.rs"
)
FIELD_SEP=$'\x1f'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEEL_SH="$SCRIPT_DIR/wheel.sh"
PLACEHOLDER_DESCRIPTION="AGENTS: please update this description with more accurate information next time this file is scanned"
RESULT_ROWS=()
EXCLUDES=()

usage() {
  cat <<'EOF'
Usage: ./wheel-scan.sh [--path PATH] [--max-depth N] [--filter PATTERN]... [--exclude DIR]...

Scan source files for function- and definition-like constructs and emit a JSON array to stdout.

Options:
  --path PATH       Base directory to scan (default: .)
  --max-depth N     Maximum directory depth (default: unlimited). Must be a positive integer when provided.
  --filter PATTERN  File glob filter passed to find -name. Can be repeated.
  --exclude DIR     Directory to skip (relative to --path or absolute). Can be repeated.
  -h, --help        Show this help text.

Notes:
  - If no --filter is supplied, the defaults are: *.c *.cc *.cpp *.cxx *.h *.hpp *.hh *.hxx *.qml *.py *.sh *.js *.mjs *.html *.rs
  - JSON goes to stdout; warnings and errors go to stderr.
EOF
}

log_error() {
  echo "Error: $*" >&2
}

log_warn() {
  echo "Warning: $*" >&2
}

json_escape() {
  local s=${1:-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  echo -n "$s"
}

add_result() {
  local file=$1
  local line=$2
  local text=$3
  local type=$4
  local signature=$5
  local language=$6

  local esc_file esc_text esc_type esc_sig esc_lang
  esc_file=$(json_escape "$file")
  esc_text=$(json_escape "$text")
  esc_type=$(json_escape "$type")
  esc_sig=$(json_escape "$signature")
  esc_lang=$(json_escape "$language")

  RESULTS+=("{\"file\":\"$esc_file\",\"line\":$line,\"text\":\"$esc_text\",\"type\":\"$esc_type\",\"signature\":\"$esc_sig\",\"language\":\"$esc_lang\"}")
  RESULT_ROWS+=("$file$FIELD_SEP$type$FIELD_SEP$signature")
}

sql_escape() {
  local s=${1:-}
  s=${s//\'/\'\'}
  echo -n "$s"
}

normalize_relpath() {
  local base=$1
  local file=$2
  base=${base%/}
  if [[ "$file" == "$base/"* ]]; then
    echo "${file#"$base"/}"
    return
  fi
  if [[ "$file" == "$base" ]]; then
    echo "."
    return
  fi
  if [[ "$file" == ./* ]]; then
    echo "${file#./}"
    return
  fi
  echo "$file"
}

wheel_call() {
  local -a cmd=("$WHEEL_SH")
  if [[ -n "${WHEEL_DB_PATH:-}" ]]; then
    cmd+=(--database "$WHEEL_DB_PATH")
  fi
  WHEEL_SKIP_AUTO_SCAN=1 "${cmd[@]}" "$@"
}

wheel_query_list() {
  local sql_body=$1
  local sql=$'.headers off\n.mode list\n'"$sql_body"
  wheel_call raw "$sql"
}

wheel_file_id() {
  local relpath=$1
  local rel_escaped
  rel_escaped="$(sql_escape "$relpath")"
  local output
  output="$(wheel_query_list "SELECT id FROM files WHERE relpath = '$rel_escaped' LIMIT 1;")" || return 1
  output=${output//$'\r'/}
  IFS=$'\n' read -r output _ <<< "$output"
  echo -n "$output"
}

wheel_def_exists() {
  local file_id=$1
  local type=$2
  local signature=$3
  local type_escaped sig_escaped
  type_escaped="$(sql_escape "$type")"
  sig_escaped="$(sql_escape "$signature")"
  local output
  output="$(wheel_query_list "SELECT id FROM defs WHERE file_id = $file_id AND type = '$type_escaped' AND COALESCE(signature, '') = '$sig_escaped' LIMIT 1;")" || return 1
  [[ -n "$output" ]]
}

wheel_add_file() {
  local relpath=$1
  wheel_call files add --relpath "$relpath" --description "$PLACEHOLDER_DESCRIPTION" >/dev/null
}

wheel_add_def() {
  local file_id=$1
  local type=$2
  local signature=$3
  wheel_call defs add --file_id "$file_id" --type "$type" --signature "$signature" --description "$PLACEHOLDER_DESCRIPTION" >/dev/null
}

sync_database() {
  local base_path=$1

  if ! command -v sqlite3 >/dev/null 2>&1; then
    return
  fi

  if [[ ${#RESULT_ROWS[@]} -eq 0 ]]; then
    return
  fi

  if [[ ! -f "$WHEEL_SH" ]]; then
    log_warn "wheel.sh not found at $WHEEL_SH; skipping database sync"
    return
  fi

  declare -A result_dirs=()
  local entry
  local file
  local type
  local signature
  local dir
  for entry in "${RESULT_ROWS[@]}"; do
    IFS="$FIELD_SEP" read -r file type signature <<< "$entry"
    dir=${file%/*}
    [[ "$dir" == "$file" ]] && dir="."
    result_dirs["$dir"]=1
  done

  if [[ ${#result_dirs[@]} -eq 0 ]]; then
    return
  fi

  declare -A file_ids=()
  local relpath
  local file_id
  for file in "${FILES[@]}"; do
    dir=${file%/*}
    [[ "$dir" == "$file" ]] && dir="."
    [[ -n "${result_dirs[$dir]:-}" ]] || continue

    relpath="$(normalize_relpath "$base_path" "$file")"
    file_id="$(wheel_file_id "$relpath")"
    if [[ -z "$file_id" ]]; then
      wheel_add_file "$relpath"
      file_id="$(wheel_file_id "$relpath")"
    fi
    [[ -n "$file_id" ]] && file_ids["$relpath"]="$file_id"
  done

  declare -A def_seen=()
  local key
  for entry in "${RESULT_ROWS[@]}"; do
    IFS="$FIELD_SEP" read -r file type signature <<< "$entry"
    relpath="$(normalize_relpath "$base_path" "$file")"
    file_id="${file_ids[$relpath]:-}"
    if [[ -z "$file_id" ]]; then
      file_id="$(wheel_file_id "$relpath")"
      if [[ -z "$file_id" ]]; then
        wheel_add_file "$relpath"
        file_id="$(wheel_file_id "$relpath")"
      fi
      [[ -n "$file_id" ]] && file_ids["$relpath"]="$file_id"
    fi
    [[ -n "$file_id" ]] || continue

    key="$relpath$FIELD_SEP$type$FIELD_SEP$signature"
    [[ -n "${def_seen[$key]:-}" ]] && continue
    def_seen["$key"]=1

    if ! wheel_def_exists "$file_id" "$type" "$signature"; then
      wheel_add_def "$file_id" "$type" "$signature"
    fi
  done
}

discover_files() {
  local base_path=$1
  local max_depth=$2
  shift 2
  local filters=("$@")

  local cmd=(find "$base_path")
  if (( max_depth > 0 )); then
    cmd+=(-maxdepth "$max_depth")
  fi

  if ((${#EXCLUDES[@]} > 0)); then
    local -a prune_expr=()
    local ex
    local ex_path
    for ex in "${EXCLUDES[@]}"; do
      ex_path="$ex"
      if [[ "$ex_path" != /* ]]; then
        ex_path="${base_path%/}/${ex_path#/}"
      fi
      ex_path="${ex_path%/}"
      if ((${#prune_expr[@]} > 0)); then
        prune_expr+=(-o)
      fi
      prune_expr+=(-path "$ex_path" -o -path "$ex_path/*")
    done
    cmd+=("(" "${prune_expr[@]}" ")" -prune -o)
  fi

  if ((${#filters[@]} > 0)); then
    cmd+=("(")
    for i in "${!filters[@]}"; do
      cmd+=(-name "${filters[$i]}")
      if (( i < ${#filters[@]} - 1 )); then
        cmd+=(-o)
      fi
    done
    cmd+=(")")
  fi

  cmd+=(-type f -print0)

  "${cmd[@]}"
}

scan_cpp_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    {
      line=$0
      trimmed=line
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)

      if (match(trimmed,/^(class|struct)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "class" sep trimmed sep sig
      } else if (match(trimmed,/^[A-Za-z_][A-Za-z0-9_:<>~*& \t]*[ \t]+[A-Za-z_][A-Za-z0-9_:<>~]*[ \t]*\([^;{}]*\)[ \t]*(const)?[ \t]*(noexcept[^{]*)?\{/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (index(trimmed,";") == 0 && match(trimmed,/^[A-Za-z_][A-Za-z0-9_:<>~*& \t]*[ \t]+[A-Za-z_][A-Za-z0-9_:<>~]*[ \t]*\([^)]*\)[ \t]*(const)?[ \t]*(noexcept[^{]*)?$/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      }
    }
  ' "$file"
}

scan_python_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    {
      trimmed=$0
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)

      if (match(trimmed,/^class[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "class" sep trimmed sep sig
      } else if (match(trimmed,/^def[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^)]*\)[ \t]*:/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      }
    }
  ' "$file"
}

scan_shell_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    {
      trimmed=$0
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)

      if (match(trimmed,/^function[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(\(\))?[ \t]*\{?/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (match(trimmed,/^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)[ \t]*\{?/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      }
    }
  ' "$file"
}

scan_qml_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    {
      trimmed=$0
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)

      if (match(trimmed,/^function[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^)]*\)[ \t]*\{?/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (match(trimmed,/^signal[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^)]*\)?/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "signal" sep trimmed sep sig
      } else if (match(trimmed,/^property[ \t]+[A-Za-z0-9_<>\.]+[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "property" sep trimmed sep sig
      } else if (match(trimmed,/^on[A-Z][A-Za-z0-9_]*[ \t]*:/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "handler" sep trimmed sep sig
      }
    }
  ' "$file"
}

scan_javascript_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    {
      trimmed=$0
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)

      if (match(trimmed,/^(export[ \t]+)?(default[ \t]+)?class[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "class" sep trimmed sep sig
      } else if (match(trimmed,/^(export[ \t]+)?default[ \t]+class/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "class" sep trimmed sep sig
      } else if (match(trimmed,/^(export[ \t]+)?(async[ \t]+)?function[ \t]*\*?[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^)]*\)/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (match(trimmed,/^(export[ \t]+)?default[ \t]+(async[ \t]+)?function[ \t]*\*?[ \t]*\([^)]*\)/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (match(trimmed,/^(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(async[ \t]+)?(function[ \t]*\*?[ \t]*\([^)]*\)|\([^)]*\)[ \t]*=>|[A-Za-z_][A-Za-z0-9_]*[ \t]*=>)/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (match(trimmed,/^export[ \t]+const[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "const" sep trimmed sep sig
      }
    }
  ' "$file"
}

scan_html_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    BEGIN { in_script=0 }
    {
      trimmed=$0
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)
      lower=tolower(trimmed)

      if (match(lower,/<script[^>]*>/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "script" sep trimmed sep sig
        in_script=1
      }
      if (match(lower,/<style[^>]*>/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "style" sep trimmed sep sig
      }
      if (match(lower,/<template[^>]*>/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "template" sep trimmed sep sig
      }
      if (match(trimmed,/(id|name)[ \t]*=[ \t]*"[^"]+"/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "attribute" sep trimmed sep sig
      } else if (match(trimmed,/(id|name)[ \t]*=[ \t]*'\''[^'\'']+'\''/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "attribute" sep trimmed sep sig
      }

      if (in_script) {
        if (match(trimmed,/^(export[ \t]+)?(default[ \t]+)?class[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
          sig=substr(trimmed,RSTART,RLENGTH)
          print NR sep "class" sep trimmed sep sig
        } else if (match(trimmed,/^(export[ \t]+)?default[ \t]+class/)) {
          sig=substr(trimmed,RSTART,RLENGTH)
          print NR sep "class" sep trimmed sep sig
        } else if (match(trimmed,/^(export[ \t]+)?(async[ \t]+)?function[ \t]*\*?[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^)]*\)/)) {
          sig=substr(trimmed,RSTART,RLENGTH)
          print NR sep "function" sep trimmed sep sig
        } else if (match(trimmed,/^(export[ \t]+)?default[ \t]+(async[ \t]+)?function[ \t]*\*?[ \t]*\([^)]*\)/)) {
          sig=substr(trimmed,RSTART,RLENGTH)
          print NR sep "function" sep trimmed sep sig
        } else if (match(trimmed,/^(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(async[ \t]+)?(function[ \t]*\*?[ \t]*\([^)]*\)|\([^)]*\)[ \t]*=>|[A-Za-z_][A-Za-z0-9_]*[ \t]*=>)/)) {
          sig=substr(trimmed,RSTART,RLENGTH)
          print NR sep "function" sep trimmed sep sig
        } else if (match(trimmed,/^export[ \t]+const[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
          sig=substr(trimmed,RSTART,RLENGTH)
          print NR sep "const" sep trimmed sep sig
        }
      }

      if (match(lower,/<\/script[ \t]*>/)) {
        in_script=0
      }
    }
  ' "$file"
}

scan_rust_file() {
  local file=$1
  local sep=$2
  awk -v sep="$sep" '
    {
      trimmed=$0
      sub(/^[ \t]+/,"",trimmed)
      gsub(/[ \t]+$/,"",trimmed)

      if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?((async|const|unsafe)[ \t]+)*fn[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "function" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?struct[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "struct" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?enum[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "enum" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?trait[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "trait" sep trimmed sep sig
      } else if (match(trimmed,/^impl([ \t]*<[^>]+>)?[ \t]+[A-Za-z_][A-Za-z0-9_:<>]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "impl" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?type[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "type" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?const[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "const" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?static[ \t]+(mut[ \t]+)?[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "static" sep trimmed sep sig
      } else if (match(trimmed,/^macro_rules![ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "macro" sep trimmed sep sig
      } else if (match(trimmed,/^macro[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "macro" sep trimmed sep sig
      } else if (match(trimmed,/^(pub(\([^)]*\))?[ \t]+)?mod[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        sig=substr(trimmed,RSTART,RLENGTH)
        print NR sep "module" sep trimmed sep sig
      }
    }
  ' "$file"
}

emit_results() {
  local first=1
  printf '['
  for entry in "${RESULTS[@]}"; do
    if (( first )); then
      first=0
    else
      printf ','
    fi
    printf '%s' "$entry"
  done
  printf ']\n'
}

process_file() {
  local file=$1
  local ext=${file##*.}
  local sep=$FIELD_SEP
  local scanner=
  local language=

  ext=${ext,,}
  case "$ext" in
    c|cc|cpp|cxx|h|hpp|hh|hxx)
      scanner=scan_cpp_file
      language=cpp
      ;;
    py)
      scanner=scan_python_file
      language=python
      ;;
    sh)
      scanner=scan_shell_file
      language=shell
      ;;
    qml)
      scanner=scan_qml_file
      language=qml
      ;;
    js|mjs)
      scanner=scan_javascript_file
      language=javascript
      ;;
    html)
      scanner=scan_html_file
      language=html
      ;;
    rs)
      scanner=scan_rust_file
      language=rust
      ;;
    *)
      return
      ;;
  esac

  if [[ ! -r "$file" ]]; then
    log_warn "Skipping unreadable file: $file"
    return
  fi

  local scan_tmp
  scan_tmp=$(mktemp) || {
    log_warn "Unable to create temp buffer for $file"
    return
  }

  if ! "$scanner" "$file" "$sep" >"$scan_tmp"; then
    log_warn "Scanner exited with status $? for $file"
  fi

  while IFS="$sep" read -r line type text sig; do
    [[ -z "$line" || -z "$type" ]] && continue
    sig=${sig:-$text}
    add_result "$file" "$line" "$text" "$type" "$sig" "$language"
  done <"$scan_tmp"

  rm -f "$scan_tmp"
}

main() {
  local path="."
  local max_depth=0
  local filters=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "--path requires a value"
          usage >&2
          exit 1
        fi
        path=$1
        ;;
      --max-depth)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "--max-depth requires a value"
          usage >&2
          exit 1
        fi
        if [[ ! $1 =~ ^[0-9]+$ ]] || (( $1 <= 0 )); then
          log_error "--max-depth must be a positive integer"
          usage >&2
          exit 1
        fi
        max_depth=$1
        ;;
      --filter)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "--filter requires a value"
          usage >&2
          exit 1
        fi
        filters+=("$1")
        ;;
      --exclude)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "--exclude requires a value"
          usage >&2
          exit 1
        fi
        EXCLUDES+=("$1")
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ ! -d "$path" ]]; then
    log_error "Path is not a directory: $path"
    exit 1
  fi

  if [[ "$path" != "/" ]]; then
    path="${path%/}"
  fi

  if ((${#filters[@]} == 0)); then
    filters=("${DEFAULT_FILTERS[@]}")
  fi

  local tmp_out
  local tmp_err
  tmp_out=$(mktemp) || {
    log_error "Failed to create temporary file"
    exit 1
  }
  tmp_err=$(mktemp) || {
    log_error "Failed to create temporary file"
    rm -f "$tmp_out"
    exit 1
  }

  discover_files "$path" "$max_depth" "${filters[@]}" >"$tmp_out" 2>"$tmp_err"
  local find_status=$?

  if [[ -s "$tmp_err" ]]; then
    while IFS= read -r line; do
      log_warn "$line"
    done <"$tmp_err"
  fi
  rm -f "$tmp_err"

  mapfile -d '' FILES < <(LC_ALL=C sort -z "$tmp_out")
  rm -f "$tmp_out"

  if (( find_status != 0 )); then
    log_warn "File discovery reported status $find_status"
  fi

  if ((${#FILES[@]} == 0)); then
    printf '[]\n'
    exit 0
  fi

  RESULTS=()
  RESULT_ROWS=()
  for file in "${FILES[@]}"; do
    process_file "$file"
  done

  sync_database "$path"
  emit_results
}

main "$@"
