open Messenger_core

let platform = Platform_types.Signal_bridge

module type CONFIG = sig
  module Http : Http_client.HTTP_CLIENT

  val get_bridge_endpoint : account_id:string -> (string option, string) result
  val get_access_token : account_id:string -> (string option, string) result
end

module Make (Config : CONFIG) : Connector_intf.S = struct
  let platform = platform

  let send_path = "/v2/send"
  let health_path = "/v1/health"

  let trim_trailing_slashes value =
    let rec loop idx =
      if idx >= 0 && value.[idx] = '/' then loop (idx - 1) else idx
    in
    if value = "" then value
    else
      let last = loop (String.length value - 1) in
      if last < 0 then "" else String.sub value 0 (last + 1)

  let with_endpoint ~account_id on_ok on_error =
    match Config.get_bridge_endpoint ~account_id with
    | Ok (Some endpoint) ->
        let base = trim_trailing_slashes (String.trim endpoint) in
        if base = "" then
          on_error
            Error_types.
              (Internal_error
                 ("bridge endpoint is blank for account " ^ account_id))
        else
          on_ok base
    | Ok None ->
        on_error
          Error_types.
            (Internal_error
               ("bridge endpoint is not configured for account " ^ account_id))
    | Error message -> on_error Error_types.(Internal_error message)

  let with_token ~account_id on_ok on_error =
    match Config.get_access_token ~account_id with
    | Ok (Some token) when String.trim token <> "" -> on_ok (String.trim token)
    | Ok _ -> on_error Error_types.(Auth_error Missing_token)
    | Error message -> on_error Error_types.(Internal_error message)

  let endpoint_url ~base path = base ^ path

  let recipient_string = function
    | Platform_types.User_id v
    | Platform_types.Phone_number v
    | Platform_types.Channel_id v -> v

  let validation_error field message =
    Error_types.Validation_error [ { Error_types.field; message } ]

  let parse_int_header headers name =
    let lname = String.lowercase_ascii name in
    let rec loop = function
      | [] -> None
      | (key, value) :: rest ->
          if String.lowercase_ascii key = lname then
            (try Some (int_of_string (String.trim value)) with _ -> None)
          else
            loop rest
    in
    loop headers

  let json_string_or_int = function
    | `String s when String.trim s <> "" -> Some (String.trim s)
    | `Int i -> Some (string_of_int i)
    | _ -> None

  let parse_message_id body =
    let assoc_member key = function
      | `Assoc fields -> List.assoc_opt key fields
      | _ -> None
    in
    let list_first = function
      | `List (value :: _) -> Some value
      | _ -> None
    in
    let pick_first values =
      List.find_map (fun value -> Option.bind value json_string_or_int) values
    in
    try
      let json = Yojson.Basic.from_string body in
      let candidates =
        [ assoc_member "message_id" json
        ; assoc_member "id" json
        ; assoc_member "timestamp" json
        ; Option.bind (assoc_member "result" json) (assoc_member "message_id")
        ; Option.bind (assoc_member "result" json) (assoc_member "id")
        ; Option.bind (assoc_member "result" json) (assoc_member "timestamp")
        ; Option.bind (assoc_member "data" json) (assoc_member "id")
        ; Option.bind (assoc_member "data" json) (assoc_member "timestamp")
        ; Option.bind (Option.bind (assoc_member "messages" json) list_first) (assoc_member "id")
        ; Option.bind (Option.bind (assoc_member "messages" json) list_first) (assoc_member "timestamp")
        ; Option.bind (list_first json) (assoc_member "id")
        ; Option.bind (list_first json) (assoc_member "timestamp")
        ]
      in
      pick_first candidates
    with _ ->
      None

  let parse_error_message body =
    let open Yojson.Basic.Util in
    try
      let json = Yojson.Basic.from_string body in
      let candidates =
        [ json |> member "message"
        ; json |> member "error"
        ; json |> member "detail"
        ; json |> member "description"
        ]
      in
      match List.find_map json_string_or_int candidates with
      | Some message -> message
      | None ->
          let trimmed = String.trim body in
          if trimmed = "" then "Signal bridge API error" else trimmed
    with _ ->
      let trimmed = String.trim body in
      if trimmed = "" then "Signal bridge API error" else trimmed

  let classify_http_error (response : Http_client.response) =
    let message = parse_error_message response.Http_client.body in
    match response.status with
    | 401 -> Error_types.Auth_error Invalid_token
    | 403 -> Error_types.Auth_error (Unauthorized message)
    | 429 ->
        let retry_after_seconds =
          parse_int_header response.headers "retry-after"
        in
        Error_types.Rate_limited
          { retry_after_seconds; limit = None; remaining = None }
    | status ->
        Error_types.Api_error
          { code = status
          ; message
          ; retriable = status >= 500
          }

  let is_success_status status = status >= 200 && status < 300

  let send_message ~account_id message on_result =
    match Connector_intf.validate_outbound_message message with
    | Error errors -> on_result (Error (Error_types.Validation_error errors))
    | Ok () when message.Platform_types.media_urls <> [] ->
        on_result
          (Error
             (validation_error "media_urls"
                "media sends are not supported in signal-bridge-v1 MVP"))
    | Ok () ->
        with_endpoint ~account_id
          (fun endpoint ->
             with_token ~account_id
               (fun token ->
                  let payload =
                    `Assoc
                      [ ("number", `String account_id)
                      ; ("recipients", `List [ `String (recipient_string message.recipient) ])
                      ; ("message", `String message.text)
                      ]
                  in
                  Config.Http.post
                    ~headers:
                      [ ("Authorization", "Bearer " ^ token)
                      ; ("Content-Type", "application/json")
                      ]
                    ~body:(Yojson.Basic.to_string payload)
                    (endpoint_url ~base:endpoint send_path)
                    (fun response ->
                       if is_success_status response.status then
                         (match parse_message_id response.body with
                          | Some message_id -> on_result (Ok message_id)
                          | None ->
                              on_result
                                (Error
                                   Error_types.
                                     (Internal_error
                                        "signal bridge send response missing message identifier")))
                       else
                         on_result (Error (classify_http_error response)))
                    (fun message ->
                       on_result
                         (Error
                            Error_types.
                              (Network_error (Connection_failed message)))))
               (fun err -> on_result (Error err)))
          (fun err -> on_result (Error err))

  let send_thread ~account_id thread on_result =
    let total_requested = List.length thread.Platform_types.posts in
    let rec loop index posted_ids = function
      | [] ->
          on_result
            (Ok
               { Platform_types.posted_ids = List.rev posted_ids
               ; failed_at_index = None
               ; total_requested
               })
      | post :: remaining ->
          send_message ~account_id post (function
            | Ok message_id -> loop (index + 1) (message_id :: posted_ids) remaining
            | Error _ ->
                on_result
                  (Ok
                     { Platform_types.posted_ids = List.rev posted_ids
                     ; failed_at_index = Some index
                     ; total_requested
                     }))
    in
    loop 0 [] thread.Platform_types.posts

  let validate_access ~account_id on_result =
    with_endpoint ~account_id
      (fun endpoint ->
         with_token ~account_id
           (fun token ->
              Config.Http.get
                ~headers:[ ("Authorization", "Bearer " ^ token) ]
                (endpoint_url ~base:endpoint health_path)
                (fun response ->
                   if is_success_status response.status then
                     on_result (Ok ())
                   else
                     on_result (Error (classify_http_error response)))
                (fun message ->
                   on_result
                     (Error
                        Error_types.
                          (Network_error (Connection_failed message)))))
           (fun err -> on_result (Error err)))
      (fun err -> on_result (Error err))
end
