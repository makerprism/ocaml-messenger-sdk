open Messenger_core

let fail msg = raise (Failure msg)

module Mock_http = struct
  let next_get_response = ref (Ok { Http_client.status = 200; headers = []; body = "{}" })
  let next_post_response =
    ref
      (Ok
         { Http_client.status = 200
          ; headers = []
          ; body = "{\"ok\":true,\"result\":{\"message_id\":42}}"
          })
  let queued_post_responses : (Http_client.response, string) result list ref = ref []

  let reset () =
    next_get_response := Ok { Http_client.status = 200; headers = []; body = "{}" };
    next_post_response :=
      Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"ok\":true,\"result\":{\"message_id\":42}}"
        };
    queued_post_responses := []

  let dequeue_post () =
    match !queued_post_responses with
    | [] -> !next_post_response
    | head :: rest ->
        queued_post_responses := rest;
        head

  let request ~meth:_ ?headers:_ ?body:_ _url on_success on_error =
    match !next_post_response with
    | Ok response -> on_success response
    | Error err -> on_error err

  let get ?headers:_ _url on_success on_error =
    match !next_get_response with
    | Ok response -> on_success response
    | Error err -> on_error err

  let post ?headers:_ ?body:_ _url on_success on_error =
    match dequeue_post () with
    | Ok response -> on_success response
    | Error err -> on_error err

  let post_multipart ?headers:_ ~parts:_ _url _on_success on_error =
    on_error "not implemented"

  let put ?headers:_ ?body:_ _url _on_success on_error =
    on_error "not implemented"

  let delete ?headers:_ _url _on_success on_error =
    on_error "not implemented"
end

module Connector = Messenger_telegram_bot_v1.Make (struct
  module Http = Mock_http

  let get_bot_token ~account_id:_ = Ok (Some "123456:ABCDEF")
end)

let test_send_message_success () =
  Mock_http.reset ();
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok "42" -> ()
    | Ok value -> fail ("expected message id 42, got " ^ value)
    | Error err -> fail ("expected success, got " ^ Error_types.to_string err))

let test_send_message_validation_error () =
  Mock_http.reset ();
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = ""
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected validation error"
    | Error (Error_types.Validation_error _) -> ()
    | Error err -> fail ("expected validation error, got " ^ Error_types.to_string err))

let test_validate_access_success () =
  Mock_http.reset ();
  Mock_http.next_get_response := Ok { Http_client.status = 200; headers = []; body = "{\"ok\":true}" };
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> ()
    | Error err -> fail ("expected access validation success, got " ^ Error_types.to_string err))

let test_send_message_api_error_payload () =
  Mock_http.reset ();
  Mock_http.next_post_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = "{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: chat not found\"}"
      };
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected API error"
    | Error (Error_types.Api_error _) -> ()
    | Error err -> fail ("expected Api_error, got " ^ Error_types.to_string err))

let test_send_message_auth_error_payload () =
  Mock_http.reset ();
  Mock_http.next_post_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = "{\"ok\":false,\"error_code\":401,\"description\":\"Unauthorized\"}"
      };
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected auth error"
    | Error (Error_types.Auth_error Error_types.Invalid_token) -> ()
    | Error err -> fail ("expected Invalid_token, got " ^ Error_types.to_string err))

let test_validate_access_api_payload_error () =
  Mock_http.reset ();
  Mock_http.next_get_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = "{\"ok\":false,\"error_code\":401,\"description\":\"Unauthorized\"}"
      };
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> fail "expected access validation error"
    | Error (Error_types.Auth_error Error_types.Invalid_token) -> ()
    | Error err -> fail ("expected Invalid_token, got " ^ Error_types.to_string err))

let test_send_thread_partial_result () =
  Mock_http.reset ();
  Mock_http.queued_post_responses :=
    [ Ok { Http_client.status = 200; headers = []; body = "{\"ok\":true,\"result\":{\"message_id\":1}}" }
    ; Ok { Http_client.status = 500; headers = []; body = "{\"ok\":false,\"description\":\"Server error\"}" }
    ];
  let post text =
    { Platform_types.recipient = Channel_id "-100123"
    ; text
    ; media_urls = []
    ; metadata = []
    }
  in
  let thread = Platform_types.{ posts = [ post "one"; post "two"; post "three" ] } in
  Connector.send_thread ~account_id:"acct" thread (function
    | Error err -> fail ("expected partial thread result, got " ^ Error_types.to_string err)
    | Ok result ->
        if result.posted_ids <> [ "1" ] then fail "expected first post id only";
        if result.failed_at_index <> Some 1 then fail "expected failed_at_index=Some 1";
        if result.total_requested <> 3 then fail "expected total_requested=3")

let () =
  test_send_message_success ();
  test_send_message_validation_error ();
  test_validate_access_success ();
  test_send_message_api_error_payload ();
  test_send_message_auth_error_payload ();
  test_validate_access_api_payload_error ();
  test_send_thread_partial_result ()
