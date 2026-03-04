(* send_text.ml — Send a plain text message via mock WhatsApp Cloud API.

   Demonstrates:
   - CONFIG module with access token getter
   - Mock HTTP_CLIENT printing outgoing payload and URL
   - Connector instantiation via Make(Config)
   - send_message success/error handling

   Expected output:
     POST https://graph.facebook.com/v19.0/1234567890/messages
     Authorization: Bearer test-access-token
     Body: {"messaging_product":"whatsapp","to":"15551234567","type":"text","text":{"preview_url":false,"body":"Hello from OCaml!"}}
     OK: message_id = wamid.test123
*)

open Messenger_core

module Mock_http : Http_client.HTTP_CLIENT = struct
  let post ?headers ?body url on_success _on_error =
    Printf.printf "POST %s\n" url;
    (match headers with
     | Some hdrs ->
         List.iter
           (fun (k, v) ->
             if String.lowercase_ascii k = "authorization" then
               Printf.printf "%s: %s\n" k v)
           hdrs
     | None -> ());
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

let () =
  let message =
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "Hello from OCaml!"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"1234567890" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))
