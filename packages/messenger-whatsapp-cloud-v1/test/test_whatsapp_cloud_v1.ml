open Messenger_core

let fail msg = raise (Failure msg)

module Mock_http = struct
  let post_responses = ref []
  let get_responses = ref []
  let post_calls = ref 0
  let last_post_url = ref None
  let last_post_headers = ref []
  let last_post_body = ref None
  let last_get_url = ref None
  let last_get_headers = ref []

  let reset () =
    post_responses := [];
    get_responses := [];
    post_calls := 0;
    last_post_url := None;
    last_post_headers := [];
    last_post_body := None;
    last_get_url := None;
    last_get_headers := []

  let dequeue responses =
    match !responses with
    | value :: rest ->
        responses := rest;
        value
    | [] -> Error "no queued mock response"

  let request ~meth ?headers ?body url on_success on_error =
    match meth with
    | Http_client.GET ->
        last_get_url := Some url;
        last_get_headers := Option.value ~default:[] headers;
        (match dequeue get_responses with
         | Ok response -> on_success response
         | Error err -> on_error err)
    | Http_client.POST ->
        incr post_calls;
        last_post_url := Some url;
        last_post_headers := Option.value ~default:[] headers;
        last_post_body := body;
        (match dequeue post_responses with
         | Ok response -> on_success response
         | Error err -> on_error err)
    | _ -> on_error "unsupported mock method"

  let get ?headers url on_success on_error =
    request ~meth:Http_client.GET ?headers url on_success on_error

  let post ?headers ?body url on_success on_error =
    request ~meth:Http_client.POST ?headers ?body url on_success on_error

  let post_multipart ?headers:_ ~parts:_ _url _on_success on_error =
    on_error "not implemented"

  let put ?headers:_ ?body:_ _url _on_success on_error =
    on_error "not implemented"

  let delete ?headers:_ _url _on_success on_error =
    on_error "not implemented"
end

module Connector = Messenger_whatsapp_cloud_v1.Make (struct
  module Http = Mock_http

  let get_access_token ~account_id =
    match account_id with
    | "missing" -> Ok None
    | _ -> Ok (Some "test-token")
end)

let sample_message ?(text = "hello") ?(media_urls = []) recipient =
  { Platform_types.recipient; text; media_urls; metadata = [] }

let expect_header headers key expected =
  match List.assoc_opt key headers with
  | Some value when value = expected -> ()
  | Some value -> fail ("expected header " ^ key ^ "=" ^ expected ^ ", got " ^ value)
  | None -> fail ("missing header " ^ key)

let expect_media_payload ?caption ~media_type ~media_field ~link () =
  match !(Mock_http.last_post_body) with
  | None -> fail "expected request body"
  | Some body ->
      let json = Yojson.Basic.from_string body in
      let open Yojson.Basic.Util in
      if json |> member "type" |> to_string <> media_type then
        fail ("expected payload type=" ^ media_type);
      if json |> member media_field |> member "link" |> to_string <> link then
        fail ("expected payload " ^ media_field ^ ".link=" ^ link);
      (match caption with
       | None ->
           (match json |> member media_field |> member "caption" with
            | `Null -> ()
            | _ -> fail "expected media caption to be omitted")
       | Some expected_caption ->
           if json |> member media_field |> member "caption" |> to_string <> expected_caption then
             fail ("expected media caption=" ^ expected_caption))

let test_send_message_text_success () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{\"id\":\"wamid.HBgM\"}]}"
        }
    ];
  Connector.send_message
    ~account_id:"acct"
    (sample_message (Phone_number "15551234567"))
    (function
      | Ok "wamid.HBgM" -> ()
      | Ok value -> fail ("expected message id wamid.HBgM, got " ^ value)
      | Error err -> fail ("expected success, got " ^ Error_types.to_string err));
  (match !(Mock_http.last_post_url) with
   | Some "https://graph.facebook.com/v19.0/acct/messages" -> ()
   | Some url -> fail ("unexpected URL: " ^ url)
   | None -> fail "expected POST URL to be recorded");
  expect_header !(Mock_http.last_post_headers) "Authorization" "Bearer test-token";
  expect_header !(Mock_http.last_post_headers) "Content-Type" "application/json";
  match !(Mock_http.last_post_body) with
  | None -> fail "expected request body"
  | Some body ->
      let json = Yojson.Basic.from_string body in
      let open Yojson.Basic.Util in
      if json |> member "messaging_product" |> to_string <> "whatsapp" then
        fail "expected messaging_product=whatsapp";
      if json |> member "to" |> to_string <> "15551234567" then
        fail "expected payload recipient phone";
      if json |> member "type" |> to_string <> "text" then
        fail "expected payload type=text";
      if json |> member "text" |> member "body" |> to_string <> "hello" then
        fail "expected payload text.body=hello"

let test_send_message_media_image_payload () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{\"id\":\"wamid.image\"}]}"
        }
    ];
  let media_url = "https://example.invalid/photo.JPEG?download=1" in
  Connector.send_message
    ~account_id:"acct"
    (sample_message ~text:"see photo" ~media_urls:[ media_url ] (Phone_number "15551234567"))
    (function
      | Ok "wamid.image" -> ()
      | Ok value -> fail ("expected message id wamid.image, got " ^ value)
      | Error err -> fail ("expected success, got " ^ Error_types.to_string err));
  expect_media_payload
    ~media_type:"image"
    ~media_field:"image"
    ~link:media_url
    ~caption:"see photo"
    ()

let test_send_message_media_video_payload_without_caption () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{\"id\":\"wamid.video\"}]}"
        }
    ];
  let media_url = "https://example.invalid/clip.mp4" in
  Connector.send_message
    ~account_id:"acct"
    (sample_message ~text:"" ~media_urls:[ media_url ] (Phone_number "15551234567"))
    (function
      | Ok "wamid.video" -> ()
      | Ok value -> fail ("expected message id wamid.video, got " ^ value)
      | Error err -> fail ("expected success, got " ^ Error_types.to_string err));
  expect_media_payload ~media_type:"video" ~media_field:"video" ~link:media_url ()

let test_send_message_media_document_payload () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{\"id\":\"wamid.doc\"}]}"
        }
    ];
  let media_url = "https://example.invalid/report.PDF#page=2" in
  Connector.send_message
    ~account_id:"acct"
    (sample_message ~text:"monthly report" ~media_urls:[ media_url ] (Phone_number "15551234567"))
    (function
      | Ok "wamid.doc" -> ()
      | Ok value -> fail ("expected message id wamid.doc, got " ^ value)
      | Error err -> fail ("expected success, got " ^ Error_types.to_string err));
  expect_media_payload
    ~media_type:"document"
    ~media_field:"document"
    ~link:media_url
    ~caption:"monthly report"
    ()

let test_send_message_media_multiple_urls_unsupported () =
  Mock_http.reset ();
  Connector.send_message
    ~account_id:"acct"
    (sample_message
       ~media_urls:[ "https://example.invalid/one.png"; "https://example.invalid/two.png" ]
       (Phone_number "15551234567"))
    (function
      | Ok _ -> fail "expected validation error"
      | Error (Error_types.Validation_error errors) ->
          if
            not
              (List.exists
                 (fun err ->
                   err.Error_types.field = "media_urls"
                   && err.message = "only one media URL is supported in MVP")
                 errors)
          then
            fail "expected clear multi-media validation error"
      | Error err -> fail ("expected Validation_error, got " ^ Error_types.to_string err));
  if !(Mock_http.post_calls) <> 0 then
    fail "send_message should not call HTTP when multiple media URLs are provided"

let test_send_message_media_unknown_extension_unsupported () =
  Mock_http.reset ();
  Connector.send_message
    ~account_id:"acct"
    (sample_message ~media_urls:[ "https://example.invalid/archive.bin" ] (Phone_number "15551234567"))
    (function
      | Ok _ -> fail "expected validation error"
      | Error (Error_types.Validation_error errors) ->
          if
            not
              (List.exists
                 (fun err ->
                   err.Error_types.field = "media_urls"
                   && err.message
                        = "unable to infer media type from URL extension (supported: image, video, document)")
                 errors)
          then
            fail "expected unsupported extension validation error"
      | Error err -> fail ("expected Validation_error, got " ^ Error_types.to_string err));
  if !(Mock_http.post_calls) <> 0 then
    fail "send_message should not call HTTP when media type cannot be inferred"

let test_validate_access_success () =
  Mock_http.reset ();
  Mock_http.get_responses := [ Ok { Http_client.status = 200; headers = []; body = "{}" } ];
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> ()
    | Error err -> fail ("expected validate_access success, got " ^ Error_types.to_string err));
  (match !(Mock_http.last_get_url) with
   | Some "https://graph.facebook.com/v19.0/acct?fields=id" -> ()
   | Some url -> fail ("unexpected validate URL: " ^ url)
   | None -> fail "expected GET URL to be recorded")

let test_validate_access_invalid_token () =
  Mock_http.reset ();
  Mock_http.get_responses :=
    [ Ok
        { Http_client.status = 401
        ; headers = []
        ; body = "{\"error\":{\"message\":\"Invalid OAuth access token\"}}"
        }
    ];
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> fail "expected auth error"
    | Error (Error_types.Auth_error Error_types.Invalid_token) -> ()
    | Error err -> fail ("expected Invalid_token, got " ^ Error_types.to_string err))

let test_send_message_api_error_payload_200 () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body =
            "{\"error\":{\"message\":\"(#100) Invalid parameter\",\"type\":\"OAuthException\",\"code\":400}}"
        }
    ];
  Connector.send_message
    ~account_id:"acct"
    (sample_message (Phone_number "15551234567"))
    (function
      | Ok _ -> fail "expected API error"
      | Error (Error_types.Api_error { code; message; retriable }) ->
          if code <> 400 then fail "expected Api_error code=400";
          if retriable then fail "expected non-retriable API error";
          if message <> "(#100) Invalid parameter" then fail "unexpected API error message"
       | Error err -> fail ("expected Api_error, got " ^ Error_types.to_string err))

(* Ported behavior intent: Cloud API error handling patterns inspired by
   netflie/bindambc/secreto reference suites (2xx error objects, retry-after,
   malformed success payloads). *)
let test_send_message_rate_limited_retry_after_header () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 429
        ; headers = [ ("Retry-After", "11") ]
        ; body = "{\"error\":{\"message\":\"Rate limit\"}}"
        }
    ];
  Connector.send_message
    ~account_id:"acct"
    (sample_message (Phone_number "15551234567"))
    (function
      | Ok _ -> fail "expected rate-limited error"
      | Error (Error_types.Rate_limited { retry_after_seconds = Some 11; _ }) -> ()
      | Error err -> fail ("expected Rate_limited with retry_after=11, got " ^ Error_types.to_string err))

let test_send_message_success_missing_message_id () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{}]}"
        }
    ];
  Connector.send_message
    ~account_id:"acct"
    (sample_message (Phone_number "15551234567"))
    (function
      | Ok _ -> fail "expected internal error for missing message id"
      | Error (Error_types.Internal_error _) -> ()
      | Error err -> fail ("expected Internal_error, got " ^ Error_types.to_string err))

let test_send_message_invalid_json_success_body () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{not-json"
        }
    ];
  Connector.send_message
    ~account_id:"acct"
    (sample_message (Phone_number "15551234567"))
    (function
      | Ok _ -> fail "expected internal error for invalid JSON"
      | Error (Error_types.Internal_error _) -> ()
      | Error err -> fail ("expected Internal_error, got " ^ Error_types.to_string err))

let test_validate_access_auth_error_payload_200 () =
  Mock_http.reset ();
  Mock_http.get_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body =
            "{\"error\":{\"message\":\"Invalid OAuth access token\",\"type\":\"OAuthException\",\"code\":401}}"
        }
    ];
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> fail "expected auth error"
    | Error (Error_types.Auth_error Error_types.Invalid_token) -> ()
    | Error err -> fail ("expected Invalid_token, got " ^ Error_types.to_string err))

let test_validate_access_forbidden_maps_unauthorized () =
  Mock_http.reset ();
  Mock_http.get_responses :=
    [ Ok
        { Http_client.status = 403
        ; headers = []
        ; body =
            "{\"error\":{\"message\":\"Insufficient permission\",\"type\":\"OAuthException\",\"code\":403}}"
        }
    ];
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> fail "expected auth error"
    | Error (Error_types.Auth_error (Error_types.Unauthorized "Insufficient permission")) -> ()
    | Error err -> fail ("expected Unauthorized, got " ^ Error_types.to_string err))

let test_validate_access_rate_limited_retry_after_header () =
  Mock_http.reset ();
  Mock_http.get_responses :=
    [ Ok
        { Http_client.status = 429
        ; headers = [ ("Retry-After", "17") ]
        ; body = "{\"error\":{\"message\":\"Rate limit\"}}"
        }
    ];
  Connector.validate_access ~account_id:"acct" (function
    | Ok () -> fail "expected rate-limited auth check"
    | Error (Error_types.Rate_limited { retry_after_seconds = Some 17; _ }) -> ()
    | Error err -> fail ("expected Rate_limited with retry_after=17, got " ^ Error_types.to_string err))

let test_send_thread_partial_result () =
  Mock_http.reset ();
  Mock_http.post_responses :=
    [ Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{\"id\":\"wamid.first\"}]}"
        }
    ; Ok
        { Http_client.status = 200
         ; headers = []
         ; body =
             "{\"error\":{\"message\":\"(#100) Invalid parameter\",\"type\":\"OAuthException\",\"code\":400}}"
         }
    ; Ok
        { Http_client.status = 200
        ; headers = []
        ; body = "{\"messages\":[{\"id\":\"wamid.third\"}]}"
        }
    ];
  let thread =
    { Platform_types.posts =
        [ sample_message ~text:"one" (Phone_number "15550000001")
        ; sample_message ~text:"two" (Phone_number "15550000002")
        ; sample_message ~text:"three" (Phone_number "15550000003")
        ]
    }
  in
  Connector.send_thread ~account_id:"acct" thread (function
    | Error err -> fail ("expected thread_result, got " ^ Error_types.to_string err)
    | Ok result ->
        if result.posted_ids <> [ "wamid.first" ] then
          fail "expected one successful id before failure";
        if result.failed_at_index <> Some 1 then
          fail "expected failure at index 1";
        if result.total_requested <> 3 then
          fail "expected total_requested=3");
  if !(Mock_http.post_calls) <> 2 then
    fail "expected send_thread to stop after first failure"

let test_missing_token_error () =
  Mock_http.reset ();
  Connector.send_message
    ~account_id:"missing"
    (sample_message (Phone_number "15550000001"))
    (function
      | Ok _ -> fail "expected auth error"
      | Error (Error_types.Auth_error Error_types.Missing_token) -> ()
      | Error err -> fail ("expected Missing_token, got " ^ Error_types.to_string err))

let () =
  test_send_message_text_success ();
  test_send_message_media_image_payload ();
  test_send_message_media_video_payload_without_caption ();
  test_send_message_media_document_payload ();
  test_send_message_media_multiple_urls_unsupported ();
  test_send_message_media_unknown_extension_unsupported ();
  test_validate_access_success ();
  test_validate_access_invalid_token ();
  test_send_message_api_error_payload_200 ();
  test_send_message_rate_limited_retry_after_header ();
  test_send_message_success_missing_message_id ();
  test_send_message_invalid_json_success_body ();
  test_validate_access_auth_error_payload_200 ();
  test_validate_access_forbidden_maps_unauthorized ();
  test_validate_access_rate_limited_retry_after_header ();
  test_send_thread_partial_result ();
  test_missing_token_error ()
