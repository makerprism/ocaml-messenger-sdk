(* validate_access.ml — Demonstrate access validation via Signal bridge health endpoint.

   validate_access checks the bridge health endpoint:
   GET {bridge_url}/v1/health

   Shows:
   1. Successful health check
   2. Auth error mapping (Missing_token when token is not configured)

   Expected output:
     --- Successful health check ---
     GET http://signal.bridge.test/v1/health
     Access OK

     --- Auth error (missing token) ---
     Access error: auth error: missing token
*)

open Messenger_core

let mock_get_response =
  ref (Ok { Http_client.status = 200; headers = []; body = {|{"ok":true}|} })

let mock_token = ref (Ok (Some "test-signal-token"))

module Mock_http : Http_client.HTTP_CLIENT = struct
  let get ?headers:_ url on_success on_error =
    Printf.printf "GET %s\n" url;
    match !mock_get_response with
    | Ok response -> on_success response
    | Error msg -> on_error msg

  let post ?headers:_ ?body:_ _url on_success _on_error =
    on_success { Http_client.status = 200; headers = []; body = {|{}|} }

  let request ~meth:_ ?headers ?body url on_success on_error =
    post ?headers ?body url on_success on_error

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
  let get_access_token ~account_id:_ = !mock_token
end)

let () =
  (* Success path *)
  Printf.printf "--- Successful health check ---\n";
  mock_token := Ok (Some "test-signal-token");
  mock_get_response :=
    Ok { Http_client.status = 200; headers = []; body = {|{"ok":true}|} };
  Connector.validate_access ~account_id:"my-account" (function
    | Ok () -> print_endline "Access OK"
    | Error err -> Printf.printf "Access error: %s\n" (Error_types.to_string err));
  print_newline ();

  (* Missing token error *)
  Printf.printf "--- Auth error (missing token) ---\n";
  mock_token := Ok None;
  Connector.validate_access ~account_id:"my-account" (function
    | Ok () -> print_endline "Access OK (unexpected)"
    | Error err -> Printf.printf "Access error: %s\n" (Error_types.to_string err))
