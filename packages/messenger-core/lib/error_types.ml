type validation_error = {
  field : string;
  message : string;
}

type rate_limit_info = {
  retry_after_seconds : int option;
  limit : int option;
  remaining : int option;
}

type auth_error =
  | Missing_token
  | Invalid_token
  | Unauthorized of string

type network_error =
  | Timeout
  | Connection_failed of string

type api_error = {
  code : int;
  message : string;
  retriable : bool;
}

type error =
  | Validation_error of validation_error list
  | Auth_error of auth_error
  | Rate_limited of rate_limit_info
  | Network_error of network_error
  | Api_error of api_error
  | Internal_error of string

type t = error

let to_string = function
  | Validation_error errs ->
      let details =
        List.map (fun e -> e.field ^ ": " ^ e.message) errs |> String.concat "; "
      in
      "validation error: " ^ details
  | Auth_error Missing_token -> "auth error: missing token"
  | Auth_error Invalid_token -> "auth error: invalid token"
  | Auth_error (Unauthorized reason) -> "auth error: unauthorized (" ^ reason ^ ")"
  | Rate_limited { retry_after_seconds; _ } ->
      (match retry_after_seconds with
       | Some sec -> "rate limited: retry after " ^ string_of_int sec ^ "s"
       | None -> "rate limited")
  | Network_error Timeout -> "network error: timeout"
  | Network_error (Connection_failed msg) -> "network error: connection failed (" ^ msg ^ ")"
  | Api_error { code; message; retriable } ->
      let retry = if retriable then "retriable" else "non-retriable" in
      "api error " ^ string_of_int code ^ " (" ^ retry ^ "): " ^ message
  | Internal_error msg -> "internal error: " ^ msg

let is_retryable = function
  | Rate_limited _ -> true
  | Network_error Timeout -> true
  | Network_error (Connection_failed _) -> true
  | Api_error { retriable; _ } -> retriable
  | _ -> false
