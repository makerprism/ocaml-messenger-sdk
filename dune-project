(lang dune 3.16)
(name ocaml-messenger-sdk)

(generate_opam_files true)

(source (github makerprism/ocaml-messenger-sdk))
(license MIT)
(authors "Sabine Schmaltz")
(maintainers "sabine@makerprism.com")
(documentation "https://github.com/makerprism/ocaml-messenger-sdk")
(bug_reports "https://github.com/makerprism/ocaml-messenger-sdk/issues")

(package
 (name messenger-core)
 (synopsis "Core interfaces for messenger API clients")
 (description
  "Runtime-agnostic and HTTP-client-agnostic core types and interfaces for messenger platform connectors")
 (depends
  (ocaml (>= 4.14))))

(package
 (name messenger-lwt)
 (synopsis "Lwt runtime adapter scaffold for messenger-core")
 (description
  "Lwt-oriented adapter package intended to host runtime-specific implementations for messenger-core")
 (depends
  (ocaml (>= 4.14))
  (messenger-core (= :version))
  lwt
  (lwt_ppx (>= 2.0.0))
  cohttp-lwt-unix))

(package
 (name messenger-whatsapp-cloud-v1)
 (synopsis "WhatsApp Cloud API v1 client")
 (description
  "WhatsApp Cloud API connector for business messaging workflows, including text/template/media sends and webhook-oriented delivery semantics")
 (depends
  (ocaml (>= 4.14))
  (messenger-core (= :version))
  yojson
  uri
  ptime
  digestif
  base64))

(package
 (name messenger-telegram-bot-v1)
 (synopsis "Telegram Bot API v1 connector")
 (description
  "Telegram Bot API connector for bot and channel or group messaging workflows with deterministic send behavior")
 (depends
  (ocaml (>= 4.14))
  (messenger-core (= :version))
  yojson))

(package
 (name messenger-signal-bridge-v1)
 (synopsis "Signal bridge API v1 client")
 (description
  "Signal bridge connector targeting signal-cli compatible HTTP bridges with send operations and event parsing")
 (depends
  (ocaml (>= 4.14))
  (messenger-core (= :version))
  yojson
  uri
  ptime
  base64))
