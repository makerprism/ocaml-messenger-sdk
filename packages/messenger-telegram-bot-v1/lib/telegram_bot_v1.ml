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
    if status = 429 then
      Error_types.Rate_limited
        { retry_after_seconds; limit = None; remaining = Some 0 }
    else if status = 401 || error_code_opt = Some 401 then
      Error_types.Auth_error Error_types.Invalid_token
    else if status = 403 || error_code_opt = Some 403 then
      Error_types.Auth_error (Error_types.Unauthorized message)
    else
      let retriable = status >= 500 in
      Error_types.Api_error { code = status; message; retriable }

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

  let send_message ~account_id message on_result =
    match Connector_intf.validate_outbound_message message with
    | Error errors -> on_result (Error (Error_types.Validation_error errors))
    | Ok () ->
        with_token ~account_id
          (fun token ->
            let chat_id = recipient_to_chat_id message.Platform_types.recipient in
            let payload =
              `Assoc
                [ ("chat_id", `String chat_id)
                ; ("text", `String message.text)
                ]
            in
            Config.Http.post
              ~headers:[ ("Content-Type", "application/json") ]
              ~body:(Yojson.Basic.to_string payload)
              (telegram_url ~token "sendMessage")
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
                                    "Telegram sendMessage response missing result.message_id")))
                     else
                       on_result
                         (Error (parse_api_error resp.status resp.body))
                   with _ ->
                     on_result
                       (Error
                          (Error_types.Internal_error
                             "Failed to parse Telegram sendMessage response")))
                else
                  on_result (Error (parse_api_error resp.status resp.body)))
              (fun err_msg ->
                on_result
                  (Error Error_types.(Network_error (Connection_failed err_msg)))))
          (fun err -> on_result (Error err))

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
