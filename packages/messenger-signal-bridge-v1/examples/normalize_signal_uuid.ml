(* normalize_signal_uuid.ml — Demonstrate signal:uuid: prefix normalization.

   The Signal bridge connector normalizes recipient identifiers:
   - "signal:uuid:<UUID>" is stripped to just the UUID (lowercased)
   - "SIGNAL:UUID:<UUID>" works the same (case-insensitive prefix)
   - Plain phone numbers pass through unchanged

   Expected output:
     --- UUID with signal:uuid: prefix ---
     POST http://signal.bridge.test/v2/send
     Body: {"number":"my-account","message":"Hello UUID recipient!","recipients":["a1b2c3d4-e5f6-7890-abcd-ef1234567890"]}
     OK: message_id = ts-1234567890

     --- UUID with uppercase prefix ---
     POST http://signal.bridge.test/v2/send
     Body: {"number":"my-account","message":"Hello uppercase UUID!","recipients":["a1b2c3d4-e5f6-7890-abcd-ef1234567890"]}
     OK: message_id = ts-1234567890

     --- Plain phone number (no normalization) ---
     POST http://signal.bridge.test/v2/send
     Body: {"number":"my-account","message":"Hello phone!","recipients":["+15559876543"]}
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
  (* UUID with signal:uuid: prefix — stripped and lowercased *)
  Printf.printf "--- UUID with signal:uuid: prefix ---\n";
  send_and_print
    { Platform_types.recipient =
        User_id "signal:uuid:A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    ; text = "Hello UUID recipient!"
    ; media_urls = []
    ; metadata = []
    };
  print_newline ();

  (* Uppercase prefix — also normalized *)
  Printf.printf "--- UUID with uppercase prefix ---\n";
  send_and_print
    { Platform_types.recipient =
        User_id "SIGNAL:UUID:A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    ; text = "Hello uppercase UUID!"
    ; media_urls = []
    ; metadata = []
    };
  print_newline ();

  (* Plain phone number — no normalization needed *)
  Printf.printf "--- Plain phone number (no normalization) ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "+15559876543"
    ; text = "Hello phone!"
    ; media_urls = []
    ; metadata = []
    }
