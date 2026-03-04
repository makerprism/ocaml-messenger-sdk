# messenger-whatsapp-cloud-v1

WhatsApp Cloud API client package for `ocaml-messenger-sdk`.

This package targets business messaging workflows (text/template/media send, webhook verification, and delivery status handling) while following the runtime-agnostic patterns used across the SDK.

Current implementation status: MVP connector support is available for text-only send, access validation, and sequential thread send. Media send paths are not implemented yet.

## Reference Implementations

Detailed reference notes are maintained in `REFERENCE_IMPLEMENTATIONS.md`.

The following repositories are used as behavioral and API-contract references.

Only permissive-licensed references are listed.

| Repository | Why trusted | License |
|---|---|---|
| https://github.com/netflie/whatsapp-cloud-api | Widely used SDK focused on WhatsApp Cloud API with active maintenance | MIT |
| https://github.com/Bindambc/whatsapp-business-java-api | Comprehensive WhatsApp Business Cloud API + management coverage | MIT |
| https://github.com/Secreto31126/whatsapp-api-js | Modern TypeScript implementation focused on official WhatsApp APIs | MIT |

See `packages/messenger-whatsapp-cloud-v1/REFERENCE_IMPLEMENTATIONS.md` for trust rationale, maintenance notes, and licensing details.

## Examples

Runnable examples are in `examples/`. All use mock HTTP clients with deterministic output — no API tokens or network access required.

| File | Purpose |
|------|---------|
| `examples/send_text.ml` | Send a plain text message to a phone number |
| `examples/send_media_url.ml` | Send image, video, and document URLs with extension-based type inference |
| `examples/reply_with_context.ml` | Reply with `context_message_id` and `biz_opaque_callback_data` metadata |
| `examples/validate_access.ml` | Validate access token via phone number ID endpoint, with auth error mapping |

Build all examples:

```bash
dune build packages/messenger-whatsapp-cloud-v1/examples
```

Run a specific example:

```bash
dune exec packages/messenger-whatsapp-cloud-v1/examples/send_text.exe
```

See `examples/README.md` for full details.

## Reuse Policy

- We use reference implementations for endpoint behavior, payload shape validation, and error semantics.
- We only adapt code patterns from permissive licenses compatible with this repository's MIT license.
- We do not copy code from repositories with incompatible licenses.
