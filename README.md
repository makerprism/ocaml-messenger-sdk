# ocaml-messenger-sdk

OCaml SDK workspace for messenger API clients.

## Status

This repository is currently authored by LLM-assisted workflows and is an active work in progress.

It is not production-ready and should not be used as a stable SDK yet.

## Platform matrix

| Platform package | Implementation state | Battle-testedness |
|---|---|---|
| `messenger-whatsapp-cloud-v1` | Scaffold only (module layout + docs + references) | None in this repo yet |
| `messenger-telegram-bot-v1` | Early MVP (text send + access validation) | None in this repo yet |
| `messenger-signal-bridge-v1` | Scaffold only (module layout + docs + references) | None in this repo yet |

`Battle-testedness` in this table refers to this repository's implementation maturity. Reference implementations listed in package docs are battle-tested upstream projects, but this codebase has not reached that state.

## Supported platform features

| Platform | Auth model | Send text | Send media URL | Thread/batch send | Validate access | Webhook ingest |
|---|---|---|---|---|---|---|
| WhatsApp Cloud | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Telegram Bot | ⚠️ | ⚠️ | ❌ | ⚠️ | ⚠️ | ❌ |
| Signal Bridge | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ |

✅ = used successfully in production workflows, ⚠️ = implemented/scaffolded with limited validation, ❌ = not implemented yet

## Packages

- `messenger-core`: shared core interfaces and types scaffold
- `messenger-lwt`: runtime adapter scaffold for future Lwt-backed implementations
- `messenger-whatsapp-cloud-v1`: WhatsApp Cloud API connector scaffold
- `messenger-telegram-bot-v1`: Telegram Bot API connector scaffold
- `messenger-signal-bridge-v1`: Signal bridge connector scaffold

Each package includes:

- `README.md` with scope and policy notes
- `REFERENCE_IMPLEMENTATIONS.md` with permissive-license references only
- `CHANGES.md` for package-level changelog history

## Build

```bash
dune build
```
