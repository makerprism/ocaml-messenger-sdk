(* send_text_direct.ml — Send a text message to a direct recipient via Signal bridge.

   Demonstrates:
   - CONFIG module with bridge endpoint, access token, and account number
   - Mock HTTP_CLIENT printing outgoing URL, headers, and payload
   - Connector instantiation via Make(Config)
   - send_message with direct (individual) recipient routing

   The payload uses "recipients" for direct sends and "number" for the
   sender account ID.

   Expected output:
     POST http://signal.bridge.test/v2/send
     Authorization: Bearer test-signal-token
     Body: {"number":"my-account","message":"Hello from OCaml!","recipients":["+15551234567"]}
     OK: message_id = ts-1234567890
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
      ; body = {|{"timestamp":"ts-1234567890"}|}
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

module Connector = Messenger_signal_bridge_v1.Make (struct
  module Http = Mock_http

  let get_bridge_endpoint ~account_id:_ = Ok (Some "http://signal.bridge.test")
  let get_access_token ~account_id:_ = Ok (Some "test-signal-token")
end)

let () =
  let message =
    { Platform_types.recipient = Phone_number "+15551234567"
    ; text = "Hello from OCaml!"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"my-account" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))
