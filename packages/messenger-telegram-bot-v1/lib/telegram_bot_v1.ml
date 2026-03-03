open Messenger_core

let platform = Platform_types.Telegram_bot
let api_base = "https://api.telegram.org"

module type CONFIG = sig
  module Http : Http_client.HTTP_CLIENT

  val get_bot_token : account_id:string -> (string option, string) result
end

module Make (Config : CONFIG) : Connector_intf.S = struct
  let platform = platform

  let parse_message_id json =
    let open Yojson.Basic.Util in
    let result = json |> member "result" in
    match result |> member "message_id" with
    | `Int i -> Some (string_of_int i)
    | `String s when String.trim s <> "" -> Some s
    | _ -> None

  let parse_api_error status body =
    let default_message = "Telegram API error" in
    let json_opt =
      try Some (Yojson.Basic.from_string body) with _ -> None
    in
    let error_code_opt =
      match json_opt with
      | Some json ->
          (try
             let open Yojson.Basic.Util in
             Some (json |> member "error_code" |> to_int)
           with _ -> None)
      | None -> None
    in
    let message =
      match json_opt with
      | Some json ->
          (try
             let open Yojson.Basic.Util in
             json |> member "description" |> to_string
           with _ -> default_message)
      | None -> default_message
    in
    let retry_after_seconds =
      match json_opt with
      | Some json ->
          (try
             let open Yojson.Basic.Util in
             Some (json |> member "parameters" |> member "retry_after" |> to_int)
           with _ -> None)
      | None -> None
    in
    let code =
      match error_code_opt with
      | Some value when status >= 200 && status < 300 -> value
      | _ -> status
    in
    if status = 429 || error_code_opt = Some 429 then
      Error_types.Rate_limited
        { retry_after_seconds; limit = None; remaining = Some 0 }
    else if status = 401 || error_code_opt = Some 401 then
      Error_types.Auth_error Error_types.Invalid_token
    else if status = 403 || error_code_opt = Some 403 then
      Error_types.Auth_error (Error_types.Unauthorized message)
    else
      let retriable = code >= 500 || status >= 500 in
      Error_types.Api_error { code; message; retriable }

  let with_token ~account_id on_ok on_error =
    match Config.get_bot_token ~account_id with
    | Ok (Some token) when String.trim token <> "" -> on_ok token
    | Ok _ -> on_error Error_types.(Auth_error Missing_token)
    | Error msg -> on_error Error_types.(Internal_error msg)

  let recipient_to_chat_id = function
    | Platform_types.User_id v
    | Platform_types.Channel_id v
    | Platform_types.Phone_number v -> v

  let telegram_url ~token method_name =
    Printf.sprintf "%s/bot%s/%s" api_base token method_name

  let validation_error field message =
    Error_types.Validation_error [ { Error_types.field; message } ]

  type media_kind =
    | Photo
    | Video

  let media_kind_of_url media_url =
    let strip_after marker value =
      match String.index_opt value marker with
      | Some idx -> String.sub value 0 idx
      | None -> value
    in
    let extension =
      media_url
      |> strip_after '#'
      |> strip_after '?'
      |> String.lowercase_ascii
      |> Filename.extension
    in
    match extension with
    | ".jpg"
    | ".jpeg"
    | ".png"
    | ".webp" -> Some Photo
    | ".mp4"
    | ".mov"
    | ".m4v"
    | ".webm"
    | ".mpeg"
    | ".mpg" -> Some Video
    | _ -> None

  let append_caption_if_non_empty fields text =
    if String.trim text = "" then fields else fields @ [ ("caption", `String text) ]

  let metadata_value key metadata =
    metadata
    |> List.find_map (fun (k, v) -> if String.lowercase_ascii k = key then Some (String.trim v) else None)

  let metadata_int key metadata =
    match metadata_value key metadata with
    | Some value when value <> "" ->
        (try Some (int_of_string value) with _ -> None)
    | _ -> None

  let metadata_bool key metadata =
    match metadata_value key metadata with
    | Some value ->
        (match String.lowercase_ascii value with
         | "true" | "1" | "yes" -> Some true
         | "false" | "0" | "no" -> Some false
         | _ -> None)
    | None -> None

  let append_common_metadata fields metadata =
    let with_thread =
      match metadata_int "message_thread_id" metadata with
      | Some value -> fields @ [ ("message_thread_id", `Int value) ]
      | None -> fields
    in
    let with_parse_mode =
      match metadata_value "parse_mode" metadata with
      | Some value when value <> "" -> with_thread @ [ ("parse_mode", `String value) ]
      | _ -> with_thread
    in
    match metadata_bool "disable_web_page_preview" metadata with
    | Some value -> with_parse_mode @ [ ("disable_web_page_preview", `Bool value) ]
    | None -> with_parse_mode

  let post_message_request ~token ~method_name ~payload on_result =
    Config.Http.post
      ~headers:[ ("Content-Type", "application/json") ]
      ~body:(Yojson.Basic.to_string payload)
      (telegram_url ~token method_name)
      (fun resp ->
        if resp.status >= 200 && resp.status < 300 then
          (try
             let json = Yojson.Basic.from_string resp.body in
             let open Yojson.Basic.Util in
             let ok = try json |> member "ok" |> to_bool with _ -> false in
             if ok then
               (match parse_message_id json with
                | Some message_id -> on_result (Ok message_id)
                | None ->
                    on_result
                      (Error
                         (Error_types.Internal_error
                            (Printf.sprintf
                               "Telegram %s response missing result.message_id"
                               method_name))))
             else
               on_result
                 (Error (parse_api_error resp.status resp.body))
           with _ ->
             on_result
               (Error
                  (Error_types.Internal_error
                     (Printf.sprintf "Failed to parse Telegram %s response" method_name))))
        else
          on_result (Error (parse_api_error resp.status resp.body)))
      (fun err_msg ->
        on_result
          (Error Error_types.(Network_error (Connection_failed err_msg))))

  let send_message ~account_id message on_result =
    match Connector_intf.validate_outbound_message message with
    | Error errors -> on_result (Error (Error_types.Validation_error errors))
    | Ok () ->
        let chat_id = recipient_to_chat_id message.Platform_types.recipient in
        let request =
           match message.Platform_types.media_urls with
           | [] ->
               Ok
                 ( "sendMessage"
                 , `Assoc
                    (append_common_metadata
                       [ ("chat_id", `String chat_id)
                       ; ("text", `String message.text)
                       ]
                       message.metadata) )
           | [ media_url ] ->
               (match media_kind_of_url media_url with
                | Some Photo ->
                    Ok
                      ( "sendPhoto"
                      , `Assoc
                         (append_common_metadata
                            (append_caption_if_non_empty
                               [ ("chat_id", `String chat_id); ("photo", `String media_url) ]
                               message.text)
                            message.metadata) )
                | Some Video ->
                    Ok
                      ( "sendVideo"
                      , `Assoc
                         (append_common_metadata
                            (append_caption_if_non_empty
                               [ ("chat_id", `String chat_id); ("video", `String media_url) ]
                               message.text)
                            message.metadata) )
                | None ->
                   Error
                     (validation_error "media_urls"
                        "only image and video URLs are supported in telegram-bot-v1 MVP"))
          | _ ->
              Error
                (validation_error "media_urls"
                   "multiple media URLs are not supported in telegram-bot-v1 MVP")
        in
        (match request with
         | Error err -> on_result (Error err)
         | Ok (method_name, payload) ->
             with_token ~account_id
               (fun token -> post_message_request ~token ~method_name ~payload on_result)
               (fun err -> on_result (Error err)))

  let send_thread ~account_id thread on_result =
    let total_requested = List.length thread.Platform_types.posts in
    let rec loop index acc = function
      | [] ->
          on_result
            (Ok
               { Platform_types.posted_ids = List.rev acc
               ; failed_at_index = None
               ; total_requested
               })
      | post :: rest ->
          send_message ~account_id post (function
            | Ok id -> loop (index + 1) (id :: acc) rest
            | Error _ ->
                on_result
                  (Ok
                     { Platform_types.posted_ids = List.rev acc
                     ; failed_at_index = Some index
                     ; total_requested
                     }))
    in
    loop 0 [] thread.Platform_types.posts

  let validate_access ~account_id on_result =
    with_token ~account_id
      (fun token ->
        Config.Http.get
          (telegram_url ~token "getMe")
          (fun resp ->
            if resp.status >= 200 && resp.status < 300 then
              (try
                 let json = Yojson.Basic.from_string resp.body in
                 let open Yojson.Basic.Util in
                 let ok = try json |> member "ok" |> to_bool with _ -> false in
                 if ok then on_result (Ok ())
                 else on_result (Error (parse_api_error resp.status resp.body))
               with _ -> on_result (Error (Error_types.Internal_error "Failed to parse Telegram getMe response")))
            else
              on_result (Error (parse_api_error resp.status resp.body)))
          (fun err_msg ->
            on_result
              (Error Error_types.(Network_error (Connection_failed err_msg)))))
      (fun err -> on_result (Error err))
end
