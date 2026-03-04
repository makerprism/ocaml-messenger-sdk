# Signal Bridge v1 Examples

Runnable examples demonstrating the `messenger-signal-bridge-v1` connector.

All examples use mock HTTP clients with deterministic output. No bridge endpoint or tokens required.

**Bridge-only scope:** This package targets `signal-cli` compatible HTTP bridges, not the official Signal cloud API. Examples assume a running bridge endpoint configured via `get_bridge_endpoint`.

## Examples

| File | Purpose |
|------|---------|
| `send_text_direct.ml` | Send a text message to a direct (individual) recipient |
| `send_text_group.ml` | Send to groups via `group_id` metadata or `group:<id>` recipient prefix |
| `normalize_signal_uuid.ml` | Demonstrate `signal:uuid:` prefix normalization to bridge recipient format |
| `validate_access.ml` | Validate access via bridge `/v1/health` endpoint, with auth error mapping |

## Running

Build all examples:

```bash
dune build packages/messenger-signal-bridge-v1/examples
```

Run a specific example:

```bash
dune exec packages/messenger-signal-bridge-v1/examples/send_text_direct.exe
dune exec packages/messenger-signal-bridge-v1/examples/send_text_group.exe
dune exec packages/messenger-signal-bridge-v1/examples/normalize_signal_uuid.exe
dune exec packages/messenger-signal-bridge-v1/examples/validate_access.exe
```

## Architecture

Each example follows this pattern:

1. Define a mock `HTTP_CLIENT` module that prints request details and returns synthetic bridge responses
2. Define a config module with `get_bridge_endpoint` and `get_access_token`
3. Instantiate the connector via `Messenger_signal_bridge_v1.Make(Config)`
4. Call `send_message` or `validate_access` with a CPS callback

## Recipient routing

- **Direct send:** Uses `"recipients"` field in payload
- **Group send (metadata):** Set `group_id` in metadata to route via `"groupIds"` field
- **Group send (prefix):** Use `group:<id>` as the recipient value
- **UUID normalization:** `signal:uuid:<UUID>` is stripped to plain UUID (lowercased)

## Supported metadata keys

- `group_id` (string) — overrides recipient routing to group send

## MVP scope

- Text-only: `media_urls` are rejected in this MVP
- These examples reflect current bridge-compatible support only
- Bridge API behavior may vary by deployment
