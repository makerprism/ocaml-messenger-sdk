(* validate_access.ml — Demonstrate access validation via WhatsApp Cloud API.

   validate_access checks the phone number ID endpoint:
   GET https://graph.facebook.com/v19.0/{account_id}?fields=id

   Shows:
   1. Successful validation
   2. Auth error mapping (Invalid_token from 401 response)
   3. Rate-limit scenario (simulated via Retry-After header comment)

   Note on rate limiting: The WhatsApp Cloud API may return 429 with a
   Retry-After header. The connector extracts retry_after_seconds from
   both the header and the error payload's error_data.retry_after field.

   Expected output:
     --- Successful access validation ---
     GET https://graph.facebook.com/v19.0/1234567890?fields=id
     Access OK

     --- Auth error (invalid token) ---
     GET https://graph.facebook.com/v19.0/1234567890?fields=id
     Access error: auth error: invalid token
*)

open Messenger_core

let mock_get_response =
  ref
    (Ok
       { Http_client.status = 200
       ; headers = []
       ; body = {|{"id":"1234567890"}|}
       })

module Mock_http : Http_client.HTTP_CLIENT = struct
  let get ?headers:_ url on_success on_error =
    Printf.printf "GET %s\n" url;
    match !mock_get_response with
    | Ok response -> on_success response
    | Error msg -> on_error msg

  let post ?headers:_ ?body:_ _url on_success _on_error =
    on_success
      { Http_client.status = 200
      ; headers = []
      ; body = {|{"messages":[{"id":"wamid.test123"}]}|}
      }

  let request ~meth:_ ?headers ?body url on_success on_error =
    post ?headers ?body url on_success on_error

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
  (* Success path *)
  Printf.printf "--- Successful access validation ---\n";
  mock_get_response :=
    Ok { Http_client.status = 200; headers = []; body = {|{"id":"1234567890"}|} };
  Connector.validate_access ~account_id:"1234567890" (function
    | Ok () -> print_endline "Access OK"
    | Error err -> Printf.printf "Access error: %s\n" (Error_types.to_string err));
  print_newline ();

  (* Auth error path *)
  Printf.printf "--- Auth error (invalid token) ---\n";
  mock_get_response :=
    Ok
      { Http_client.status = 401
      ; headers = []
      ; body = {|{"error":{"message":"Invalid OAuth access token","type":"OAuthException","code":190}}|}
      };
  Connector.validate_access ~account_id:"1234567890" (function
    | Ok () -> print_endline "Access OK (unexpected)"
    | Error err -> Printf.printf "Access error: %s\n" (Error_types.to_string err))
