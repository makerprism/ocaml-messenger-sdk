(* validate_access.ml — Demonstrate access validation via Telegram getMe endpoint.

   Shows two scenarios:
   1. Successful validation (token accepted)
   2. Auth error mapping (Invalid_token from 401 response)

   Expected output:
     --- Successful access validation ---
     GET https://api.telegram.org/bot000000:ABCDEF-example/getMe
     Access OK

     --- Auth error (invalid token) ---
     Access error: auth error: invalid token
*)

open Messenger_core

(* Mutable response ref allows switching between success and error responses. *)
let mock_get_response =
  ref (Ok { Http_client.status = 200; headers = []; body = {|{"ok":true}|} })

module Mock_http : Http_client.HTTP_CLIENT = struct
  let get ?headers:_ url on_success on_error =
    Printf.printf "GET %s\n" url;
    match !mock_get_response with
    | Ok response -> on_success response
    | Error msg -> on_error msg

  let post ?headers:_ ?body:_ _url on_success _on_error =
    on_success { Http_client.status = 200; headers = []; body = {|{"ok":true}|} }

  let request ~meth:_ ?headers ?body url on_success on_error =
    post ?headers ?body url on_success on_error

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
  (* Success path *)
  Printf.printf "--- Successful access validation ---\n";
  mock_get_response :=
    Ok { Http_client.status = 200; headers = []; body = {|{"ok":true}|} };
  Connector.validate_access ~account_id:"my-bot" (function
    | Ok () -> print_endline "Access OK"
    | Error err -> Printf.printf "Access error: %s\n" (Error_types.to_string err));
  print_newline ();

  (* Auth error path *)
  Printf.printf "--- Auth error (invalid token) ---\n";
  mock_get_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = {|{"ok":false,"error_code":401,"description":"Unauthorized"}|}
      };
  Connector.validate_access ~account_id:"my-bot" (function
    | Ok () -> print_endline "Access OK (unexpected)"
    | Error err -> Printf.printf "Access error: %s\n" (Error_types.to_string err))
