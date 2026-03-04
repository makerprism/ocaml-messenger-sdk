# Telegram Bot v1 Examples

Runnable examples demonstrating the `messenger-telegram-bot-v1` connector.

All examples use mock HTTP clients with deterministic output. No API tokens or network access required.

## Examples

| File | Purpose |
|------|---------|
| `basic_send_text.ml` | Send a plain text message to a chat |
| `send_media_url.ml` | Send photo and video URLs with extension-based type inference |
| `send_with_metadata.ml` | Use `message_thread_id`, `parse_mode`, and `disable_web_page_preview` metadata |
| `validate_access.ml` | Validate bot token via `getMe` endpoint, with auth error mapping |

## Running

Build all examples:

```bash
dune build packages/messenger-telegram-bot-v1/examples
```

Run a specific example:

```bash
dune exec packages/messenger-telegram-bot-v1/examples/basic_send_text.exe
dune exec packages/messenger-telegram-bot-v1/examples/send_media_url.exe
dune exec packages/messenger-telegram-bot-v1/examples/send_with_metadata.exe
dune exec packages/messenger-telegram-bot-v1/examples/validate_access.exe
```

## Architecture

Each example follows this pattern:

1. Define a mock `HTTP_CLIENT` module that prints request details and returns synthetic responses
2. Define a config module with `get_bot_token` returning a test token
3. Instantiate the connector via `Messenger_telegram_bot_v1.Make(Config)`
4. Call `send_message` or `validate_access` with a CPS callback

## Supported metadata keys (text sends)

- `message_thread_id` (int as string) — topic/forum thread ID
- `parse_mode` (string) — `HTML`, `Markdown`, or `MarkdownV2`
- `disable_web_page_preview` (bool as string) — `true` or `false`

For media sends, only `message_thread_id` applies.

## MVP scope

These examples reflect current MVP support only. See the package README for implementation status.
