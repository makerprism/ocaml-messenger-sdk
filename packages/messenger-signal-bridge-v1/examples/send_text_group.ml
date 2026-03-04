(* send_text_group.ml — Send text messages to Signal groups via bridge.

   Demonstrates two group routing approaches:
   1. metadata group_id — overrides recipient routing to group
   2. recipient "group:<id>" — alternative group routing via recipient field

   Both produce a payload with "groupIds" instead of "recipients".

   Expected output:
     --- Group send via metadata ---
     POST http://signal.bridge.test/v2/send
     Body: {"number":"my-account","message":"Hello group (metadata)!","groupIds":["dGVzdC1ncm91cC1pZA=="]}
     OK: message_id = ts-1234567890

     --- Group send via recipient prefix ---
     POST http://signal.bridge.test/v2/send
     Body: {"number":"my-account","message":"Hello group (prefix)!","groupIds":["YW5vdGhlci1ncm91cA=="]}
     OK: message_id = ts-1234567890
*)

open Messenger_core

module Mock_http : Http_client.HTTP_CLIENT = struct
  let post ?headers:_ ?body url on_success _on_error =
    Printf.printf "POST %s\n" url;
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

let send_and_print message =
  Connector.send_message ~account_id:"my-account" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))

let () =
  (* Group send via metadata group_id *)
  Printf.printf "--- Group send via metadata ---\n";
  send_and_print
    { Platform_types.recipient = User_id "ignored-when-group-set"
    ; text = "Hello group (metadata)!"
    ; media_urls = []
    ; metadata = [ ("group_id", "dGVzdC1ncm91cC1pZA==") ]
    };
  print_newline ();

  (* Group send via recipient prefix *)
  Printf.printf "--- Group send via recipient prefix ---\n";
  send_and_print
    { Platform_types.recipient = User_id "group:YW5vdGhlci1ncm91cA=="
    ; text = "Hello group (prefix)!"
    ; media_urls = []
    ; metadata = []
    }
