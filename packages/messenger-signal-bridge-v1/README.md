# messenger-signal-bridge-v1

Signal bridge connector package for `ocaml-messenger-sdk`.

This package targets Signal integration through bridge/daemon APIs (for example `signal-cli` HTTP bridges), not a direct official cloud API.

## Reference Implementations

Detailed reference notes are maintained in `REFERENCE_IMPLEMENTATIONS.md`.

The following repositories are used as behavioral and integration-contract references.

Only permissive-licensed references are listed.

| Repository | Why trusted | License |
|---|---|---|
| https://github.com/openclaw/openclaw | Very high-adoption production-grade integration that uses Signal via `signal-cli` JSON-RPC + SSE | MIT |
| https://github.com/bbernhard/signal-cli-rest-api | Widely used Signal bridge surface for HTTP-based automation workflows | MIT |

See `packages/messenger-signal-bridge-v1/REFERENCE_IMPLEMENTATIONS.md` for trust rationale, maintenance notes, and licensing details.

## Scope Note

- This package is intentionally named `signal-bridge` because it integrates with bridge-compatible APIs.
- It does not claim to be an official first-party Signal cloud SDK.

## MVP Connector Surface

- `send_message`: text-only send over bridge-compatible HTTP (`media_urls` are rejected in this MVP).
- `validate_access`: health/check probe using configured bridge endpoint and token.
- `send_thread`: sequential message posting over `posts` with `thread_result` completion status.

## Currently Supported Operations

- Send text: `send_message` posts plain text messages to a single recipient.
- Thread partial completion: `send_thread` posts sequentially and returns a `thread_result` with `posted_ids` plus `failed_at_index` when a later post fails.
- Access validation: `validate_access` performs bridge health/auth validation using configured endpoint and bearer token.

## Examples

Runnable examples are in `examples/`. All use mock HTTP clients with deterministic output — no bridge endpoint or tokens required.

| File | Purpose |
|------|---------|
| `examples/send_text_direct.ml` | Send a text message to a direct (individual) recipient |
| `examples/send_text_group.ml` | Send to groups via `group_id` metadata or `group:<id>` recipient prefix |
| `examples/normalize_signal_uuid.ml` | Demonstrate `signal:uuid:` prefix normalization to bridge recipient format |
| `examples/validate_access.ml` | Validate access via bridge `/v1/health` endpoint, with auth error mapping |

Build all examples:

```bash
dune build packages/messenger-signal-bridge-v1/examples
```

Run a specific example:

```bash
dune exec packages/messenger-signal-bridge-v1/examples/send_text_direct.exe
```

See `examples/README.md` for full details.

## Reuse Policy

- We use reference implementations for runtime behavior, bridge protocol semantics, and error handling expectations.
- We only adapt code patterns from permissive licenses compatible with this repository's MIT license.
- We do not copy code from repositories with incompatible licenses.
