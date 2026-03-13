#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
LANGUAGE="${DEEPL_TARGET:-EN}"
LANGUAGE_SOURCE="${DEEPL_SOURCE:-auto}"
KEY="${DEEPL_KEY:-}"
PRO="${DEEPL_PRO:-0}"
FORMALITY="${DEEPL_FORMALITY:-prefer_less}"
POSTFIX="${DEEPL_POSTFIX:-.}"
VERSION="3.0.0"
DEBUG="${DEEPL_DEBUG:-0}"
DEEPL_HOST="${DEEPL_HOST:-}"

PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log() {
  if [[ "$DEBUG" == "1" ]]; then
    echo >&2 "[deepl.sh] $*"
  fi
}

print_json_item() {
  local title="$1"
  local arg="$2"

  python3 - "$title" "$arg" <<'PY'
import json, sys
title = sys.argv[1]
arg = sys.argv[2]
print(json.dumps({
    "items": [{
        "uid": None,
        "title": title,
        "arg": arg,
        "valid": True,
        "autocomplete": "autocomplete"
    }]
}, ensure_ascii=False))
PY
}

print_json_error() {
  local message="$1"

  python3 - "$message" <<'PY'
import json, sys
message = sys.argv[1]
print(json.dumps({
    "items": [{
        "uid": None,
        "title": message,
        "arg": "error",
        "valid": False
    }]
}, ensure_ascii=False))
PY
}

trim() {
  python3 -c 'import sys; print(sys.stdin.read().strip())'
}

usage() {
  cat <<EOF
Home made DeepL CLI (${VERSION})

SYNTAX:
  $0 [-l language] <query>

Example:
  $0 -l DE "This is just an example."

Required:
  Set DEEPL_KEY to use the official DeepL API.

Optional env vars:
  DEEPL_TARGET       Target language (default: EN)
  DEEPL_SOURCE       Source language (default: auto)
  DEEPL_FORMALITY    default | prefer_more | prefer_less | less | more
  DEEPL_PRO          1 to use api.deepl.com, otherwise api-free.deepl.com
  DEEPL_HOST         Custom DeepL-compatible host
  DEEPL_POSTFIX      Postfix required by Alfred workflow UI (default: .)
  DEEPL_DEBUG        1 to enable debug logs
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print_json_error "Error: required command not found: $cmd"
    exit 20
  fi
}

parse_response() {
  local response="$1"

  python3 - "$response" <<'PY'
import json, sys

raw = sys.argv[1]

try:
    parsed = json.loads(raw)
except Exception as e:
    print(json.dumps({
        "items": [{
            "title": f"Error parsing JSON response: {e}",
            "arg": "error",
            "valid": False
        }]
    }, ensure_ascii=False))
    sys.exit(0)

if isinstance(parsed, dict) and "message" in parsed and "translations" not in parsed:
    print(json.dumps({
        "items": [{
            "title": f"DeepL error: {parsed.get('message', 'unknown error')}",
            "arg": "error",
            "valid": False
        }]
    }, ensure_ascii=False))
    sys.exit(0)

translations = parsed.get("translations")
if not translations:
    print(json.dumps({
        "items": [{
            "title": "Error: no translations found in DeepL response",
            "arg": "error",
            "valid": False
        }]
    }, ensure_ascii=False))
    sys.exit(0)

items = []
for t in translations:
    text = t.get("text")
    detected = t.get("detected_source_language")
    if text:
        subtitle = f"Detected source: {detected}" if detected else None
        item = {
            "title": text,
            "arg": text,
            "valid": True
        }
        if subtitle:
            item["subtitle"] = subtitle
        items.append(item)

if not items:
    print(json.dumps({
        "items": [{
            "title": "Error: translation text missing in response",
            "arg": "error",
            "valid": False
        }]
    }, ensure_ascii=False))
    sys.exit(0)

print(json.dumps({"items": items}, ensure_ascii=False, indent=2))
PY
}

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--lang)
      [[ $# -lt 2 ]] && { print_json_error "Error: missing value for $1"; exit 21; }
      LANGUAGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

# -----------------------------------------------------------------------------
# Input validation
# -----------------------------------------------------------------------------
if [[ $# -eq 0 ]] || [[ -z "${1:-}" ]]; then
  usage
  exit 1
fi

require_cmd curl
require_cmd python3

query="$(printf '%s' "$1" | trim)"

if [[ -z "$query" ]]; then
  print_json_error "Error: empty query"
  exit 2
fi

# Keep postfix behavior for the Alfred UX, but only as UI sugar.
if [[ "$query" == *"$POSTFIX" ]]; then
  query="${query%$POSTFIX}"
  query="$(printf '%s' "$query" | trim)"
fi

if [[ -z "$KEY" ]]; then
  print_json_error "Error: set DEEPL_KEY to use the official DeepL API"
  exit 3
fi

# -----------------------------------------------------------------------------
# Endpoint selection
# -----------------------------------------------------------------------------
if [[ -n "$DEEPL_HOST" ]]; then
  url="${DEEPL_HOST%/}/v2/translate"
elif [[ "$PRO" == "1" ]]; then
  url="https://api.deepl.com/v2/translate"
else
  url="https://api-free.deepl.com/v2/translate"
fi

log "Using URL: $url"
log "Target language: $LANGUAGE"
log "Source language: $LANGUAGE_SOURCE"
log "Formality: $FORMALITY"
log "Query: $query"

# -----------------------------------------------------------------------------
# Request
# -----------------------------------------------------------------------------
curl_args=(
  -sS
  -X POST "$url"
  -H "Authorization: DeepL-Auth-Key $KEY"
  --data-urlencode "text=$query"
  --data-urlencode "target_lang=$LANGUAGE"
  --data-urlencode "formality=$FORMALITY"
)

if [[ "${LANGUAGE_SOURCE,,}" != "auto" ]]; then
  curl_args+=( --data-urlencode "source_lang=$LANGUAGE_SOURCE" )
fi

# Capture body and status separately
tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

http_code="$(
  curl "${curl_args[@]}" \
    -o "$tmp_body" \
    -w '%{http_code}'
)"

response="$(cat "$tmp_body")"

log "HTTP code: $http_code"
log "Response: $response"

# -----------------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------------
if [[ "$http_code" == "403" ]]; then
  print_json_error "Error: invalid DeepL API key"
  exit 4
fi

if [[ "$http_code" == "456" ]]; then
  print_json_error "Error: quota exceeded"
  exit 5
fi

if [[ "$http_code" == "429" ]]; then
  print_json_error "Error: too many requests"
  exit 6
fi

if [[ ! "$http_code" =~ ^2 ]]; then
  message="$(
    python3 - "$response" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    parsed = json.loads(raw)
    print(parsed.get("message") or f"HTTP error with unexpected response")
except Exception:
    print("HTTP error with non-JSON response")
PY
  )"
  print_json_error "Error: $message (HTTP $http_code)"
  exit 7
fi

# -----------------------------------------------------------------------------
# Success
# -----------------------------------------------------------------------------
parse_response "$response"