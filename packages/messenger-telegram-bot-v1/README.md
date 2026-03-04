# messenger-telegram-bot-v1

Telegram Bot API connector package for `ocaml-messenger-sdk`.

This package focuses on bot/channel/group messaging operations and deterministic send behavior for automation workflows.

## Reference Implementations

Detailed reference notes are maintained in `REFERENCE_IMPLEMENTATIONS.md`.

The following repositories are used as behavioral and API-contract references.

Only permissive-licensed references are listed.

| Repository | Why trusted | License |
|---|---|---|
| https://github.com/tdlib/telegram-bot-api | Official Telegram Bot API server implementation and protocol reference | BSL-1.0 |
| https://github.com/telegraf/telegraf | Highly adopted Telegram bot framework with broad endpoint coverage | MIT |
| https://github.com/yagop/node-telegram-bot-api | Long-running and battle-tested Telegram bot ecosystem project | MIT |
| https://github.com/go-telegram-bot-api/telegram-bot-api | Stable API mapping with clear request/response patterns | MIT |
| https://github.com/aiogram/aiogram | Mature async Telegram framework with strong API parity practices | MIT |

See `packages/messenger-telegram-bot-v1/REFERENCE_IMPLEMENTATIONS.md` for trust rationale, maintenance notes, and licensing details.

## Examples

Runnable examples are in `examples/`. All use mock HTTP clients with deterministic output — no API tokens or network access required.

| File | Purpose |
|------|---------|
| `examples/basic_send_text.ml` | Send a plain text message to a chat |
| `examples/send_media_url.ml` | Send photo and video URLs with extension-based type inference |
| `examples/send_with_metadata.ml` | Use `message_thread_id`, `parse_mode`, and `disable_web_page_preview` metadata |
| `examples/validate_access.ml` | Validate bot token via `getMe` endpoint, with auth error mapping |

Build all examples:

```bash
dune build packages/messenger-telegram-bot-v1/examples
```

Run a specific example:

```bash
dune exec packages/messenger-telegram-bot-v1/examples/basic_send_text.exe
```

See `examples/README.md` for full details.

## Reuse Policy

- We use reference implementations for endpoint behavior, payload shape validation, and error semantics.
- We only adapt code patterns from permissive licenses compatible with this repository's MIT license.
- We do not copy code from repositories with incompatible licenses.
