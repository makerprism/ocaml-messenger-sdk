(* send_media_url.ml — Send photo and video URLs via mock Telegram Bot API.

   Demonstrates:
   - Photo URL send (extension-based inference: .jpeg -> sendPhoto)
   - Video URL send (extension-based inference: .mp4 -> sendVideo)
   - Unsupported media type and expected validation error
   - Caption omission when text is empty

   Expected output:
     --- Photo with caption ---
     POST https://api.telegram.org/bot000000:ABCDEF-example/sendPhoto
     Body: {"chat_id":"-100123456","photo":"https://example.com/photo.jpeg","caption":"A nice photo"}
     OK: message_id = 42

     --- Video without caption ---
     POST https://api.telegram.org/bot000000:ABCDEF-example/sendVideo
     Body: {"chat_id":"-100123456","video":"https://example.com/clip.mp4"}
     OK: message_id = 42

     --- Unsupported media type (.zip) ---
     Error: validation error: media_urls: only image and video URLs are supported in telegram-bot-v1 MVP
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
  (* Photo with caption *)
  Printf.printf "--- Photo with caption ---\n";
  send_and_print
    { Platform_types.recipient = Channel_id "-100123456"
    ; text = "A nice photo"
    ; media_urls = [ "https://example.com/photo.jpeg" ]
    ; metadata = []
    };
  print_newline ();

  (* Video without caption *)
  Printf.printf "--- Video without caption ---\n";
  send_and_print
    { Platform_types.recipient = Channel_id "-100123456"
    ; text = ""
    ; media_urls = [ "https://example.com/clip.mp4" ]
    ; metadata = []
    };
  print_newline ();

  (* Unsupported media type *)
  Printf.printf "--- Unsupported media type (.zip) ---\n";
  send_and_print
    { Platform_types.recipient = Channel_id "-100123456"
    ; text = "hello"
    ; media_urls = [ "https://example.com/archive.zip" ]
    ; metadata = []
    }
