# WhatsApp Cloud v1 Examples

Runnable examples demonstrating the `messenger-whatsapp-cloud-v1` connector.

All examples use mock HTTP clients with deterministic output. No API tokens or network access required.

## Examples

| File | Purpose |
|------|---------|
| `send_text.ml` | Send a plain text message to a phone number |
| `send_media_url.ml` | Send image, video, and document URLs with extension-based type inference |
| `reply_with_context.ml` | Reply with `context_message_id` and `biz_opaque_callback_data` metadata |
| `validate_access.ml` | Validate access token via phone number ID endpoint, with auth error mapping |

## Running

Build all examples:

```bash
dune build packages/messenger-whatsapp-cloud-v1/examples
```

Run a specific example:

```bash
dune exec packages/messenger-whatsapp-cloud-v1/examples/send_text.exe
dune exec packages/messenger-whatsapp-cloud-v1/examples/send_media_url.exe
dune exec packages/messenger-whatsapp-cloud-v1/examples/reply_with_context.exe
dune exec packages/messenger-whatsapp-cloud-v1/examples/validate_access.exe
```

## Architecture

Each example follows this pattern:

1. Define a mock `HTTP_CLIENT` module that prints request details and returns synthetic Graph API responses
2. Define a config module with `get_access_token` returning a test token
3. Instantiate the connector via `Messenger_whatsapp_cloud_v1.Make(Config)`
4. Call `send_message` or `validate_access` with a CPS callback

## Supported metadata keys

- `context_message_id` (string) — maps to `{"context":{"message_id":"..."}}` in the payload
- `biz_opaque_callback_data` (string) — top-level tracking/correlation field

## MVP scope

These examples reflect current MVP support only. See the package README for implementation status.
