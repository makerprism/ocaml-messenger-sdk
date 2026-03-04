(* send_with_metadata.ml — Demonstrate metadata keys supported by Telegram Bot API.

   Supported metadata keys for text sends:
   - message_thread_id : int — topic/forum thread ID
   - parse_mode : string — "HTML", "Markdown", or "MarkdownV2"
   - disable_web_page_preview : bool — "true" or "false"

   Note: For media sends, only message_thread_id applies.
   parse_mode and disable_web_page_preview are text-send-only fields.

   Expected output:
     --- Text with all metadata ---
     POST https://api.telegram.org/bot000000:ABCDEF-example/sendMessage
     Body: {"chat_id":"-100123456","text":"<b>Bold</b> text","message_thread_id":77,"parse_mode":"HTML","disable_web_page_preview":true}
     OK: message_id = 42

     --- Photo with thread metadata ---
     POST https://api.telegram.org/bot000000:ABCDEF-example/sendPhoto
     Body: {"chat_id":"-100123456","photo":"https://example.com/img.png","caption":"Thread photo","message_thread_id":99}
     OK: message_id = 42
*)

open Messenger_core

module Mock_http : Http_client.HTTP_CLIENT = struct
  let post ?headers:_ ?body url on_success _on_error =
    Printf.printf "POST %s\n" url;
    (match body with Some b -> Printf.printf "Body: %s\n" b | None -> ());
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

let send_and_print message =
  Connector.send_message ~account_id:"my-bot" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))

let () =
  (* Text with all three metadata keys *)
  Printf.printf "--- Text with all metadata ---\n";
  send_and_print
    { Platform_types.recipient = Channel_id "-100123456"
    ; text = "<b>Bold</b> text"
    ; media_urls = []
    ; metadata =
        [ ("message_thread_id", "77")
        ; ("parse_mode", "HTML")
        ; ("disable_web_page_preview", "true")
        ]
    };
  print_newline ();

  (* Photo with thread ID only (parse_mode and disable_web_page_preview
     are not applicable to media sends) *)
  Printf.printf "--- Photo with thread metadata ---\n";
  send_and_print
    { Platform_types.recipient = Channel_id "-100123456"
    ; text = "Thread photo"
    ; media_urls = [ "https://example.com/img.png" ]
    ; metadata = [ ("message_thread_id", "99") ]
    }
