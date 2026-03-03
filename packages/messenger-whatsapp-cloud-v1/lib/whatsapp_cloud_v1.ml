open Messenger_core

let platform = Platform_types.Whatsapp_cloud
let api_base = "https://graph.facebook.com"
let api_version = "v19.0"

module type CONFIG = sig
  module Http : Http_client.HTTP_CLIENT

  val get_access_token : account_id:string -> (string option, string) result
end

module Make (Config : CONFIG) : Connector_intf.S = struct
  let platform = platform

  let with_token ~account_id on_ok on_error =
    match Config.get_access_token ~account_id with
    | Ok (Some token) when String.trim token <> "" -> on_ok token
    | Ok _ -> on_error Error_types.(Auth_error Missing_token)
    | Error msg -> on_error Error_types.(Internal_error msg)

  let recipient_to_phone = function
    | Platform_types.User_id value
    | Platform_types.Channel_id value
    | Platform_types.Phone_number value -> value

  let account_url account_id =
    Printf.sprintf "%s/%s/%s" api_base api_version account_id

  let messages_url ~account_id = account_url account_id ^ "/messages"
  let validate_url ~account_id = account_url account_id ^ "?fields=id"

  let parse_retry_after headers =
    let rec find = function
      | [] -> None
      | (name, value) :: rest ->
          if String.lowercase_ascii name = "retry-after" then
            (try Some (int_of_string (String.trim value)) with _ -> None)
          else
            find rest
    in
    find headers

  let parse_json body =
    try Some (Yojson.Basic.from_string body) with _ -> None

  let int_of_json = function
    | `Int value -> Some value
    | `String value ->
        (try Some (int_of_string (String.trim value)) with _ -> None)
    | _ -> None

  let has_api_error_payload body =
    match parse_json body with
    | Some json ->
        (match Yojson.Basic.Util.(json |> member "error") with
         | `Assoc _ -> true
         | _ -> false)
    | None -> false

  let parse_api_error status headers body =
    let default_message = "WhatsApp Cloud API error" in
    let json_opt = parse_json body in
    let message =
      match json_opt with
      | Some json ->
          (try
             let open Yojson.Basic.Util in
             json |> member "error" |> member "message" |> to_string
           with _ -> default_message)
      | None -> default_message
    in
    let error_code_opt =
      match json_opt with
      | Some json ->
          (try
             let open Yojson.Basic.Util in
             json |> member "error" |> member "code" |> int_of_json
           with _ -> None)
      | None -> None
    in
    let payload_retry_after =
      match json_opt with
      | Some json ->
          (try
             let open Yojson.Basic.Util in
             json |> member "error" |> member "error_data" |> member "retry_after" |> int_of_json
           with _ -> None)
      | None -> None
    in
    let retry_after_seconds =
      match parse_retry_after headers with
      | Some _ as value -> value
      | None -> payload_retry_after
    in
    let error_code =
      match error_code_opt with
      | Some value when status >= 200 && status < 300 -> value
      | _ -> status
    in
    if status = 429 || error_code_opt = Some 429 then
      Error_types.Rate_limited
        { retry_after_seconds; limit = None; remaining = Some 0 }
    else if status = 401 || error_code_opt = Some 401 then
      Error_types.Auth_error Invalid_token
    else if status = 403 || error_code_opt = Some 403 then
      Error_types.Auth_error (Unauthorized message)
    else
      Error_types.Api_error { code = error_code; message; retriable = error_code >= 500 }

  let parse_message_id body =
    try
      let json = Yojson.Basic.from_string body in
      let open Yojson.Basic.Util in
      match json |> member "messages" |> to_list with
      | first :: _ ->
          (match first |> member "id" with
           | `String value when String.trim value <> "" -> Some value
           | `Int value -> Some (string_of_int value)
           | _ -> None)
      | [] -> None
    with _ -> None

  type media_kind =
    | Image
    | Video
    | Document

  let media_type_and_field = function
    | Image -> ("image", "image")
    | Video -> ("video", "video")
    | Document -> ("document", "document")

  let last_index_of_opt input target =
    let rec loop index =
      if index < 0 then None
      else if input.[index] = target then Some index
      else loop (index - 1)
    in
    loop (String.length input - 1)

  let strip_url_query_and_fragment url =
    let length = String.length url in
    let rec find_cutoff index =
      if index >= length then length
      else
        match url.[index] with
        | '?' | '#' -> index
        | _ -> find_cutoff (index + 1)
    in
    String.sub url 0 (find_cutoff 0)

  let infer_media_kind_from_url url =
    let cleaned_url = String.trim url |> strip_url_query_and_fragment in
    match last_index_of_opt cleaned_url '.' with
    | None -> None
    | Some dot_index ->
        let slash_index = Option.value (last_index_of_opt cleaned_url '/') ~default:(-1) in
        if dot_index <= slash_index || dot_index = String.length cleaned_url - 1 then
          None
        else
          let extension =
            String.sub cleaned_url (dot_index + 1) (String.length cleaned_url - dot_index - 1)
            |> String.lowercase_ascii
          in
          match extension with
          | "jpg" | "jpeg" | "png" | "webp" | "gif" -> Some Image
          | "mp4" | "3gp" | "mov" -> Some Video
          | "pdf" | "doc" | "docx" | "ppt" | "pptx" | "xls" | "xlsx" | "txt"
          | "csv" | "rtf" -> Some Document
          | _ -> None

  let build_message_payload message =
    let base_fields =
      [ ("messaging_product", `String "whatsapp")
      ; ("to", `String (recipient_to_phone message.Platform_types.recipient))
      ]
    in
    match message.Platform_types.media_urls with
    | [] ->
        Ok
          (`Assoc
             (base_fields
             @ [ ("type", `String "text")
               ; ("text", `Assoc [ ("preview_url", `Bool false); ("body", `String message.text) ])
               ]))
    | [ media_url ] ->
        (match infer_media_kind_from_url media_url with
         | None ->
             Error
               [ { Error_types.field = "media_urls"
                 ; message =
                     "unable to infer media type from URL extension (supported: image, video, document)"
                 }
               ]
         | Some media_kind ->
             let message_type, media_field = media_type_and_field media_kind in
             let media_payload =
               if String.trim message.text = "" then
                 `Assoc [ ("link", `String media_url) ]
               else
                 `Assoc [ ("link", `String media_url); ("caption", `String message.text) ]
             in
             Ok (`Assoc (base_fields @ [ ("type", `String message_type); (media_field, media_payload) ])))
    | _ ->
        Error
          [ { Error_types.field = "media_urls"
            ; message = "only one media URL is supported in MVP"
            }
          ]

  let send_message ~account_id message on_result =
    match Connector_intf.validate_outbound_message message with
    | Error errors -> on_result (Error (Error_types.Validation_error errors))
    | Ok () ->
        (match build_message_payload message with
         | Error errors -> on_result (Error (Error_types.Validation_error errors))
         | Ok payload ->
             with_token ~account_id
               (fun token ->
                 Config.Http.post
                   ~headers:
                     [ ("Authorization", "Bearer " ^ token)
                     ; ("Content-Type", "application/json")
                     ]
                   ~body:(Yojson.Basic.to_string payload)
                   (messages_url ~account_id)
                   (fun response ->
                     if response.status >= 200 && response.status < 300 then
                       if has_api_error_payload response.body then
                         on_result
                           (Error
                              (parse_api_error response.status response.headers response.body))
                       else
                         (match parse_message_id response.body with
                          | Some message_id -> on_result (Ok message_id)
                          | None ->
                              on_result
                                (Error
                                   (Error_types.Internal_error
                                      "WhatsApp Cloud API response missing messages[0].id")))
                     else
                       on_result
                         (Error
                            (parse_api_error response.status response.headers response.body)))
                   (fun err_msg ->
                     on_result
                       (Error Error_types.(Network_error (Connection_failed err_msg)))))
               (fun err -> on_result (Error err)))

  let send_thread ~account_id thread on_result =
    let total_requested = List.length thread.Platform_types.posts in
    let rec loop index posted = function
      | [] ->
          on_result
            (Ok
               { Platform_types.posted_ids = List.rev posted
               ; failed_at_index = None
               ; total_requested
               })
      | post :: rest ->
          send_message ~account_id post (function
            | Ok message_id -> loop (index + 1) (message_id :: posted) rest
            | Error _ ->
                on_result
                  (Ok
                     { Platform_types.posted_ids = List.rev posted
                     ; failed_at_index = Some index
                     ; total_requested
                     }))
    in
    loop 0 [] thread.Platform_types.posts

  let validate_access ~account_id on_result =
    with_token ~account_id
      (fun token ->
        Config.Http.get
          ~headers:[ ("Authorization", "Bearer " ^ token) ]
          (validate_url ~account_id)
          (fun response ->
            if response.status >= 200 && response.status < 300 then
              if has_api_error_payload response.body then
                on_result
                  (Error
                     (parse_api_error response.status response.headers response.body))
              else
                on_result (Ok ())
            else
              on_result
                (Error (parse_api_error response.status response.headers response.body)))
          (fun err_msg ->
            on_result
              (Error Error_types.(Network_error (Connection_failed err_msg)))))
      (fun err -> on_result (Error err))
end
