#!/usr/bin/env bash
set -euo pipefail

DIR="."
LIMIT=100
COMMENTS=all
VARS_ARGS=()

usage() {
    cat >&2 <<'EOF'
Usage: jira-issues-yaml.sh [-d DIR] [-l LIMIT] [-c COMMENTS] [-f] JQL_OR_ALIAS [-V key=value ...]

Export each Jira issue matching a JQL query (or configured alias) to its own
YAML file <ISSUE_KEY>.yaml in DIR, using jflow for full issue detail.

  -d DIR        output directory (default: .; created if missing)
  -l LIMIT      max issues to export (default: 100)
  -c COMMENTS   comment mode for jflow show: none|last|all|N (default: all)
  -V key=value  JQL variable substitution, repeatable (forwarded to jflow query)
  -f            accepted for compatibility; files are always overwritten

Files are always overwritten silently; re-running refreshes them.
EOF
}

while getopts "d:l:c:V:f" opt; do
    case "$opt" in
        d) DIR=$OPTARG ;;
        l) LIMIT=$OPTARG ;;
        c) COMMENTS=$OPTARG ;;
        V) VARS_ARGS+=(--var "$OPTARG") ;;
        f) : ;;
        *) usage; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
    usage
    exit 2
fi
JQL=$1
shift

# Options may also appear after JQL_OR_ALIAS (e.g. ... "JQL" -l 3 -V foo=bar)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -V|--var) [[ $# -ge 2 ]] || { usage; exit 2; }; VARS_ARGS+=(--var "$2"); shift 2 ;;
        -V*) VARS_ARGS+=(--var "${1#-V}"); shift ;;
        -d|-l|-c) [[ $# -ge 2 ]] || { usage; exit 2; }
            case "$1" in
                -d) DIR=$2 ;; -l) LIMIT=$2 ;; -c) COMMENTS=$2 ;;
            esac
            shift 2 ;;
        -f) shift ;;
        *) echo "unexpected argument: $1" >&2; usage; exit 2 ;;
    esac
done

echo "Running query." >&2
if ! keys_json=$(jflow -f json query "$JQL" "${VARS_ARGS[@]}" --limit "$LIMIT"); then
    echo "jflow query failed" >&2
    exit 1
fi

mapfile -t KEYS < <(printf '%s' "$keys_json" | python3 -c 'import json,sys; [print(i["Key"]) for i in json.load(sys.stdin) if i.get("Key")]')

if [[ ${#KEYS[@]} -eq 0 ]]; then
    echo "no issues matched" >&2
    exit 0
fi
mkdir -p -- "$DIR"
echo "Pulling ${#KEYS[@]} issue(s)." >&2

failed=0
exported=0
for key in "${KEYS[@]}"; do
    echo "  : $key" >&2
    if jflow -f yaml show "$key" --comments "$COMMENTS" > "$DIR/$key.yaml"; then
        ((exported++)) || true
    else
        echo "warning: failed to export $key" >&2
        rm -f -- "$DIR/$key.yaml"
        ((failed++)) || true
    fi
done

if ((failed > 0)); then
    echo "exported $exported issue(s) to $DIR/; $failed failed" >&2
    exit 1
fi
echo "exported $exported issue(s) to $DIR/" >&2
