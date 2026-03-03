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
  let last_post_url : string option ref = ref None
  let last_post_body : string option ref = ref None
  let post_call_count = ref 0

  let reset () =
    next_get_response := Ok { Http_client.status = 200; headers = []; body = "{}" };
    next_post_response :=
      Ok
         { Http_client.status = 200
         ; headers = []
         ; body = "{\"ok\":true,\"result\":{\"message_id\":42}}"
         };
    queued_post_responses := [];
    last_post_url := None;
    last_post_body := None;
    post_call_count := 0

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

  let post ?headers:_ ?body url on_success on_error =
    incr post_call_count;
    last_post_url := Some url;
    last_post_body := body;
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

let sent_payload () =
  match !(Mock_http.last_post_body) with
  | Some body -> Yojson.Basic.from_string body
  | None -> fail "expected a POST payload"

let expect_field_string ~field ~expected json =
  let open Yojson.Basic.Util in
  let actual = json |> member field |> to_string in
  if actual <> expected then
    fail (Printf.sprintf "expected %s=%s, got %s" field expected actual)

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

let test_send_message_photo_success () =
  Mock_http.reset ();
  let photo_url = "https://example.test/path/IMAGE.JPEG?token=abc" in
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "caption text"
    ; media_urls = [ photo_url ]
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok "42" -> ()
    | Ok value -> fail ("expected message id 42, got " ^ value)
    | Error err -> fail ("expected photo send success, got " ^ Error_types.to_string err));
  (match !(Mock_http.last_post_url) with
   | Some "https://api.telegram.org/bot123456:ABCDEF/sendPhoto" -> ()
   | Some url -> fail ("expected sendPhoto endpoint, got " ^ url)
   | None -> fail "expected POST request URL");
  let payload = sent_payload () in
  expect_field_string ~field:"chat_id" ~expected:"-100123" payload;
  expect_field_string ~field:"photo" ~expected:photo_url payload;
  expect_field_string ~field:"caption" ~expected:"caption text" payload

let test_send_message_video_success_without_caption () =
  Mock_http.reset ();
  let video_url = "https://example.test/video/clip.mp4" in
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = ""
    ; media_urls = [ video_url ]
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok "42" -> ()
    | Ok value -> fail ("expected message id 42, got " ^ value)
    | Error err -> fail ("expected video send success, got " ^ Error_types.to_string err));
  (match !(Mock_http.last_post_url) with
   | Some "https://api.telegram.org/bot123456:ABCDEF/sendVideo" -> ()
   | Some url -> fail ("expected sendVideo endpoint, got " ^ url)
   | None -> fail "expected POST request URL");
  let payload = sent_payload () in
  let open Yojson.Basic.Util in
  expect_field_string ~field:"chat_id" ~expected:"-100123" payload;
  expect_field_string ~field:"video" ~expected:video_url payload;
  if payload |> member "caption" <> `Null then
    fail "expected caption to be omitted when text is empty"

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

let test_send_message_media_type_unsupported () =
  Mock_http.reset ();
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = [ "https://example.test/archive.zip" ]
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected validation error for unsupported media"
    | Error (Error_types.Validation_error errors) ->
        if not (List.exists (fun err -> err.Error_types.field = "media_urls") errors) then
          fail "expected media_urls validation error"
    | Error err -> fail ("expected validation error, got " ^ Error_types.to_string err));
  if !(Mock_http.post_call_count) <> 0 then
    fail "send_message should not call HTTP for unsupported media URLs"

(* Ported behavior intent: media validation and malformed/error payload handling
   aligned with mature Telegram SDK suites (e.g. aiogram/node-telegram-bot-api). *)
let test_send_message_multiple_media_urls_unsupported () =
  Mock_http.reset ();
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = [ "https://example.test/a.jpg"; "https://example.test/b.jpg" ]
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected validation error for multiple media URLs"
    | Error (Error_types.Validation_error errors) ->
        if not (List.exists (fun err -> err.Error_types.field = "media_urls") errors) then
          fail "expected media_urls validation error"
    | Error err -> fail ("expected validation error, got " ^ Error_types.to_string err));
  if !(Mock_http.post_call_count) <> 0 then
    fail "send_message should not call HTTP for multiple media URLs"

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
    | Error (Error_types.Api_error { code; _ }) when code = 400 -> ()
    | Error err -> fail ("expected Api_error, got " ^ Error_types.to_string err))

let test_send_message_invalid_json_response () =
  Mock_http.reset ();
  Mock_http.next_post_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = "{not-json"
      };
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected parse/internal error"
    | Error (Error_types.Internal_error _) -> ()
    | Error err -> fail ("expected Internal_error, got " ^ Error_types.to_string err))

let test_send_message_success_missing_message_id () =
  Mock_http.reset ();
  Mock_http.next_post_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = "{\"ok\":true,\"result\":{}}"
      };
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected internal error for missing message_id"
    | Error (Error_types.Internal_error _) -> ()
    | Error err -> fail ("expected Internal_error, got " ^ Error_types.to_string err))

let test_send_message_rate_limited_payload () =
  Mock_http.reset ();
  Mock_http.next_post_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body =
          "{\"ok\":false,\"error_code\":429,\"description\":\"Too Many Requests\",\"parameters\":{\"retry_after\":9}}"
      };
  let message =
    { Platform_types.recipient = Channel_id "-100123"
    ; text = "hello"
    ; media_urls = []
    ; metadata = []
    }
  in
  Connector.send_message ~account_id:"acct" message (function
    | Ok _ -> fail "expected rate limit error"
    | Error (Error_types.Rate_limited { retry_after_seconds = Some 9; _ }) -> ()
    | Error err -> fail ("expected Rate_limited retry_after=9, got " ^ Error_types.to_string err))

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

let test_validate_access_invalid_json_response () =
  Mock_http.reset ();
  Mock_http.next_get_response :=
    Ok
      { Http_client.status = 200
      ; headers = []
      ; body = "{invalid-json"
      };
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> fail "expected parse/internal error"
    | Error (Error_types.Internal_error _) -> ()
    | Error err -> fail ("expected Internal_error, got " ^ Error_types.to_string err))

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
  test_send_message_photo_success ();
  test_send_message_video_success_without_caption ();
  test_send_message_validation_error ();
  test_send_message_media_type_unsupported ();
  test_send_message_multiple_media_urls_unsupported ();
  test_validate_access_success ();
  test_send_message_api_error_payload ();
  test_send_message_invalid_json_response ();
  test_send_message_success_missing_message_id ();
  test_send_message_rate_limited_payload ();
  test_send_message_auth_error_payload ();
  test_validate_access_api_payload_error ();
  test_validate_access_invalid_json_response ();
  test_send_thread_partial_result ()
