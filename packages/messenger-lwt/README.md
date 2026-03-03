# messenger-lwt

`messenger-lwt` is currently a thin runtime bridge for `messenger-core`.

## What works today

- The CPS -> Lwt adapter is implemented.
- `Messenger_lwt.Adapt_http_client` converts any
  `Messenger_core.Http_client.HTTP_CLIENT` implementation into a Lwt-facing module
  (`request`, `get`, `post`, `post_multipart`, `put`, `delete`) returning
  `(response, error) result Lwt.t`.

## What is intentionally stubbed

- `Messenger_lwt.Http_client_stub.Make` is a deliberate placeholder backend.
- Its methods always return an error indicating no concrete HTTP backend is
  wired.
- This package does not currently ship a production HTTP runtime.

## Injecting your own HTTP client

Implement `Messenger_core.Http_client.HTTP_CLIENT` in your app, then adapt it:

```ocaml
module My_http_client : Messenger_core.Http_client.HTTP_CLIENT = struct
  (* your CPS HTTP implementation *)
end

module My_http_client_lwt = Messenger_lwt.Adapt_http_client (My_http_client)
```

Use your own client module(s) in consumers; treat `Http_client_stub` as scaffold
only.
