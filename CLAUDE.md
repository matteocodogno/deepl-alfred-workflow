# deepl-alfred-workflow

Alfred workflow for DeepL translation on macOS.

## Scripts

- `deepl.sh` — translation script (DeepL Translate API)
- `deepl-write.sh` — rephrasing script (DeepL Write API)

Both scripts support two modes:
- **No API key:** uses DeepL's internal JSON-RPC endpoint; query must end with `.` (configurable via `DEEPL_POSTFIX`)
- **With API key:** uses the official DeepL REST API (`api-free.deepl.com` or `api.deepl.com` for Pro)

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DEEPL_KEY` | _(empty)_ | DeepL API key; enables authenticated mode |
| `DEEPL_PRO` | _(empty)_ | Set to `1` for Pro account |
| `DEEPL_TARGET` | `EN` | Target language code |
| `DEEPL_SOURCE` | `auto` | Source language code |
| `DEEPL_FORMALITY` | `prefer_less` | Formality level |
| `DEEPL_POSTFIX` | `.` | Required suffix when no API key |
| `DEEPL_HOST` | _(empty)_ | Override API base URL |

## Build

```sh
make workflow   # packages .alfredworkflow (v4) and .alfred5workflow (v5)
```

Requires: `zip`

## Testing

```sh
make bats       # dynamic integration tests (requires bats-core: brew install bats-core)
make test       # static analysis (requires shellcheck + shellharden)
make style      # format scripts (requires shfmt)
```

Tests in `deepl.bats` hit the live DeepL API (no key required). A `teardown` sleep of 1s between tests avoids rate limiting.

## Alfred keywords

- `dl` — translate text
- `dll` — change target language
- `⌃⌥⌘D` — translate selected text system-wide
