(* reply_with_context.ml — Demonstrate context/tracker metadata for WhatsApp.

   Supported metadata keys:
   - context_message_id : maps to {"context":{"message_id":"..."}} in payload
   - biz_opaque_callback_data : top-level tracking/correlation field

   Expected output:
     --- Reply with context and tracker ---
     POST https://graph.facebook.com/v19.0/1234567890/messages
     Body: {"messaging_product":"whatsapp","to":"15551234567","biz_opaque_callback_data":"order-42-confirm","context":{"message_id":"wamid.orig456"},"type":"text","text":{"preview_url":false,"body":"Your order is confirmed!"}}
     OK: message_id = wamid.test123

     --- Context only (no tracker) ---
     POST https://graph.facebook.com/v19.0/1234567890/messages
     Body: {"messaging_product":"whatsapp","to":"15551234567","context":{"message_id":"wamid.orig789"},"type":"text","text":{"preview_url":false,"body":"Thanks for your feedback."}}
     OK: message_id = wamid.test123
*)

open Messenger_core

module Mock_http : Http_client.HTTP_CLIENT = struct
  let post ?headers:_ ?body url on_success _on_error =
    Printf.printf "POST %s\n" url;
    (match body with Some b -> Printf.printf "Body: %s\n" b | None -> ());
    on_success
      { Http_client.status = 200
      ; headers = []
      ; body = {|{"messages":[{"id":"wamid.test123"}]}|}
      }

  let request ~meth:_ ?headers ?body url on_success on_error =
    post ?headers ?body url on_success on_error

  let get ?headers:_ _url on_success _on_error =
    on_success { Http_client.status = 200; headers = []; body = {|{"id":"1234567890"}|} }

  let post_multipart ?headers:_ ~parts:_ _url _on_success on_error =
    on_error "not implemented"

  let put ?headers:_ ?body:_ _url _on_success on_error =
    on_error "not implemented"

  let delete ?headers:_ _url _on_success on_error =
    on_error "not implemented"
end

module Connector = Messenger_whatsapp_cloud_v1.Make (struct
  module Http = Mock_http

  let get_access_token ~account_id:_ = Ok (Some "test-access-token")
end)

let send_and_print message =
  Connector.send_message ~account_id:"1234567890" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))

let () =
  (* Reply with both context and business tracker *)
  Printf.printf "--- Reply with context and tracker ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "Your order is confirmed!"
    ; media_urls = []
    ; metadata =
        [ ("context_message_id", "wamid.orig456")
        ; ("biz_opaque_callback_data", "order-42-confirm")
        ]
    };
  print_newline ();

  (* Reply with context only *)
  Printf.printf "--- Context only (no tracker) ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "Thanks for your feedback."
    ; media_urls = []
    ; metadata = [ ("context_message_id", "wamid.orig789") ]
    }
