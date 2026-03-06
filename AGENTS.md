# Agent Workspace Rules

These rules apply to all coding agents working in this repository.

## Purpose

This is an OCaml SDK for messenger platform APIs (WhatsApp, Telegram, Signal). 
It provides runtime-agnostic interfaces with Lwt adapters for posting messages and validating access.

**Scope:** Send-side messaging only. No webhook ingest, no read APIs.

See `README.md` for platform support matrix and package structure.

## Building

```bash
dune build
```

If dependency metadata is stale, regenerate lock data first:

```bash
dune pkg lock
dune build
```

## Dune Lockfile Workflow

- If dependencies changed, or Dune reports stale lock data, run `dune pkg lock`.
- Do not manually edit files under `dune.lock/`.
- Regenerate lock data only via `dune pkg lock`.
- **Never use `--only-packages` flag** with `dune pkg lock`. It causes package resolution failures in CI.

## Dependency Policy

- `dune` must not be listed as a package dependency in `dune-project` package stanzas.

## Build Directory Safety

- Never run `dune clean`.
- Never delete or mutate `_build/` manually.

## Security and Sensitive Data

- Never print or commit real API tokens, bot secrets, phone numbers, chat IDs, or webhook secrets.
- Redact token-like strings in logs and surfaced errors.
- Treat message payloads as sensitive user data; prefer minimal structured logs.

## Upstream PR Workflow

- Canonical upstream is `makerprism/ocaml-messenger-sdk`.
- Before opening/updating a PR to `upstream/main`, rebase your branch onto `upstream/main`.
- If already pushed, update with `git push --force-with-lease`.

## Documentation Maintenance

Docs that don't evolve with code become lies. Stale docs are bugs.

**After completing significant work:**

1. If you added a new platform package, update `README.md` platform matrix
2. If you changed API signatures, update usage examples in package READMEs
3. If you fixed a bug that was documented as a limitation, remove the limitation note

**Rules:**
- Update docs in the same PR as code changes — never as a separate task
- README.md is the primary doc; keep it accurate

## Definition of Done

- [ ] `dune build` passes
- [ ] Affected README sections updated
- [ ] You can explain the change in one sentence
