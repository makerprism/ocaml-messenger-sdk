open Messenger_core

let fail message = raise (Failure message)

module Mock_http = struct
  type request_record = {
    url : string;
    headers : (string * string) list;
  }

  let requests : request_record list ref = ref []

  let next_get_response =
    ref (Ok { Http_client.status = 200; headers = []; body = "{\"ok\":true}" })

  let next_post_responses : (Http_client.response, string) result list ref =
    ref []

  let reset () =
    requests := [];
    next_get_response := Ok { Http_client.status = 200; headers = []; body = "{\"ok\":true}" };
    next_post_responses := []

  let record_request ~url ?headers () =
    let normalized_headers = match headers with Some value -> value | None -> [] in
    requests := { url; headers = normalized_headers } :: !requests

  let dispatch result on_success on_error =
    match result with
    | Ok response -> on_success response
    | Error message -> on_error message

  let pop_post_response () =
    match !next_post_responses with
    | response :: rest ->
        next_post_responses := rest;
        response
    | [] -> Error "no POST response queued"

  let rec request ~meth ?headers ?body url on_success on_error =
    match meth with
    | Http_client.GET -> get ?headers url on_success on_error
    | Http_client.POST -> post ?headers ?body url on_success on_error
    | _ ->
        record_request ~url ?headers ();
        on_error "mock HTTP method not supported"

  and get ?headers url on_success on_error =
    record_request ~url ?headers ();
    dispatch !next_get_response on_success on_error

  and post ?headers ?body:_ url on_success on_error =
    record_request ~url ?headers ();
    dispatch (pop_post_response ()) on_success on_error

  and post_multipart ?headers:_ ~parts:_ _url _on_success on_error =
    on_error "not implemented"

  and put ?headers:_ ?body:_ _url _on_success on_error =
    on_error "not implemented"

  and delete ?headers:_ _url _on_success on_error =
    on_error "not implemented"
end

module Config_state = struct
  let endpoint_result = ref (Ok (Some "http://signal.bridge.test"))
  let token_result = ref (Ok (Some "test-token"))

  let reset () =
    endpoint_result := Ok (Some "http://signal.bridge.test");
    token_result := Ok (Some "test-token")
end

module Connector = Messenger_signal_bridge_v1.Make (struct
  module Http = Mock_http

  let get_bridge_endpoint ~account_id:_ = !Config_state.endpoint_result
  let get_access_token ~account_id:_ = !Config_state.token_result
end)

let find_header name headers =
  let lowercase_name = String.lowercase_ascii name in
  let rec loop = function
    | [] -> None
    | (key, value) :: rest ->
        if String.lowercase_ascii key = lowercase_name then Some value else loop rest
  in
  loop headers

let reset_env () =
  Mock_http.reset ();
  Config_state.reset ()

let sample_message text =
  { Platform_types.recipient = Phone_number "+12025550199"
  ; text
  ; media_urls = []
  ; metadata = []
  }

let test_send_message_success () =
  reset_env ();
  Mock_http.next_post_responses :=
    [ Ok { Http_client.status = 201; headers = []; body = "{\"timestamp\":123456789}" } ];
  let message = sample_message "hello from bridge" in
  Connector.send_message ~account_id:"+12025550000" message (function
    | Ok "123456789" -> ()
    | Ok value -> fail ("expected parsed message id 123456789, got " ^ value)
    | Error err -> fail ("expected send success, got " ^ Error_types.to_string err));
  match !Mock_http.requests with
  | [] -> fail "expected one HTTP request"
  | request :: _ ->
      if request.url <> "http://signal.bridge.test/v2/send" then
        fail ("unexpected URL: " ^ request.url);
      (match find_header "Authorization" request.headers with
       | Some "Bearer test-token" -> ()
       | Some other -> fail ("unexpected authorization header: " ^ other)
       | None -> fail "missing authorization header")

let test_send_message_rejects_media_urls () =
  reset_env ();
  let message =
    { Platform_types.recipient = User_id "user-1"
    ; text = "text"
    ; media_urls = [ "https://example.test/image.jpg" ]
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"+12025550000" message (function
    | Ok _ -> fail "expected media validation error"
    | Error (Error_types.Validation_error [ { field; _ } ]) when field = "media_urls" -> ()
    | Error err ->
        fail
          ("expected media_urls validation error, got "
         ^ Error_types.to_string err));
  if !Mock_http.requests <> [] then
    fail "send_message should not call HTTP when media_urls is present"

let test_validate_access_success () =
  reset_env ();
  Mock_http.next_get_response :=
    Ok { Http_client.status = 200; headers = []; body = "{\"status\":\"ok\"}" };
  Connector.validate_access ~account_id:"+12025550000" (function
    | Ok () -> ()
    | Error err -> fail ("expected validate_access success, got " ^ Error_types.to_string err));
  match !Mock_http.requests with
  | [] -> fail "expected health-check HTTP request"
  | request :: _ ->
      if request.url <> "http://signal.bridge.test/v1/health" then
        fail ("unexpected health URL: " ^ request.url)

let test_validate_access_missing_token () =
  reset_env ();
  Config_state.token_result := Ok None;
  Connector.validate_access ~account_id:"+12025550000" (function
    | Ok () -> fail "expected auth error"
    | Error (Error_types.Auth_error Error_types.Missing_token) -> ()
    | Error err -> fail ("expected missing token error, got " ^ Error_types.to_string err));
  if !Mock_http.requests <> [] then
    fail "validate_access should not call HTTP when token is missing"

let test_send_thread_partial_failure_returns_thread_result () =
  reset_env ();
  Mock_http.next_post_responses :=
    [ Ok { Http_client.status = 201; headers = []; body = "{\"id\":\"first-id\"}" }
    ; Ok { Http_client.status = 500; headers = []; body = "{\"message\":\"bridge down\"}" }
    ];
  let post text =
    { Platform_types.recipient = Phone_number "+12025550199"
    ; text
    ; media_urls = []
    ; metadata = []
    }
  in
  let request =
    Platform_types.
      { posts = [ post "one"; post "two"; post "three" ] }
  in
  Connector.send_thread ~account_id:"+12025550000" request (function
    | Error err -> fail ("expected thread_result, got " ^ Error_types.to_string err)
    | Ok result ->
        if result.posted_ids <> [ "first-id" ] then
          fail "expected only first message ID in posted_ids";
        if result.failed_at_index <> Some 1 then
          fail "expected failed_at_index = Some 1";
        if result.total_requested <> 3 then
          fail "expected total_requested = 3");
  if List.length !Mock_http.requests <> 2 then
    fail "expected thread send to stop after second post failure"

let test_send_message_payload_error_on_http_2xx () =
  reset_env ();
  Mock_http.next_post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body =
            "{\"ok\":false,\"error\":\"recipient not registered\",\"code\":400}"
        }
    ];
  Connector.send_message ~account_id:"+12025550000" (sample_message "hello")
    (function
      | Ok _ -> fail "expected API error for 2xx payload error"
      | Error
          (Error_types.Api_error
            { code = 400; message; retriable = false }) ->
          if message <> "recipient not registered" then
            fail ("unexpected API error message: " ^ message)
      | Error err ->
          fail
            ("expected Api_error code 400 for payload-level error, got "
           ^ Error_types.to_string err))

let test_send_message_payload_auth_mapping () =
  reset_env ();
  Mock_http.next_post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"ok\":false,\"error\":\"unauthorized\",\"code\":401}"
        }
    ];
  Connector.send_message ~account_id:"+12025550000" (sample_message "hello")
    (function
      | Ok _ -> fail "expected auth error mapping"
      | Error (Error_types.Auth_error Error_types.Invalid_token) -> ()
      | Error err ->
          fail
            ("expected Invalid_token from payload-level auth error, got "
           ^ Error_types.to_string err))

let test_send_message_payload_rate_limit_with_retry_after () =
  reset_env ();
  Mock_http.next_post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body =
            "{\"ok\":false,\"error\":\"rate limit\",\"code\":429,\"retry_after\":7}"
        }
    ];
  Connector.send_message ~account_id:"+12025550000" (sample_message "hello")
    (function
      | Ok _ -> fail "expected rate limit mapping"
      | Error
          (Error_types.Rate_limited
            { retry_after_seconds = Some 7; limit = None; remaining = None }) ->
          ()
      | Error err ->
          fail
            ("expected Rate_limited with retry_after_seconds=Some 7, got "
           ^ Error_types.to_string err))

let () =
  test_send_message_success ();
  test_send_message_rejects_media_urls ();
  test_validate_access_success ();
  test_validate_access_missing_token ();
  test_send_thread_partial_failure_returns_thread_result ();
  test_send_message_payload_error_on_http_2xx ();
  test_send_message_payload_auth_mapping ();
  test_send_message_payload_rate_limit_with_retry_after ()
