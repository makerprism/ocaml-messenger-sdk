(* basic_send_text.ml — Send a plain text message via mock Telegram Bot API.

   Demonstrates:
   - CONFIG module with bot token getter
   - Mock HTTP_CLIENT that prints outgoing payload
   - Connector instantiation via Make(Config)
   - send_message with Ok/Error callback handling

   Expected output:
     POST https://api.telegram.org/bot000000:ABCDEF-example/sendMessage
     Body: {"chat_id":"-100123456","text":"Hello from OCaml!"}
     OK: message_id = 42
*)

open Messenger_core

(* Mock HTTP client that prints request details and returns a synthetic
   Telegram-style success response. *)
module Mock_http : Http_client.HTTP_CLIENT = struct
  let post ?headers:_ ?body url on_success _on_error =
    Printf.printf "POST %s\n" url;
    (match body with
     | Some b -> Printf.printf "Body: %s\n" b
     | None -> ());
    on_success
      { Http_client.status = 200
      ; headers = []
      ; body = {|{"ok":true,"result":{"message_id":42}}|}
      }

  let request ~meth:_ ?headers ?body url on_success on_error =
    post ?headers ?body url on_success on_error

  let get ?headers:_ _url on_success _on_error =
    on_success { Http_client.status = 200; headers = []; body = {|{"ok":true}|} }

  let post_multipart ?headers:_ ~parts:_ _url _on_success on_error =
    on_error "not implemented"

  let put ?headers:_ ?body:_ _url _on_success on_error =
    on_error "not implemented"

  let delete ?headers:_ _url _on_success on_error =
    on_error "not implemented"
end

module Connector = Messenger_telegram_bot_v1.Make (struct
  module Http = Mock_http

  let get_bot_token ~account_id:_ = Ok (Some "000000:ABCDEF-example")
end)

let () =
  let message =
    { Platform_types.recipient = Channel_id "-100123456"
    ; text = "Hello from OCaml!"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"my-bot" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))
