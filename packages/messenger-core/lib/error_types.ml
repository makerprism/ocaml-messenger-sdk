type validation_error = {
  field : string;
  message : string;
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

type t =
  | Validation of validation_error list
  | Auth of auth_error
  | Network of network_error
  | Api of api_error

let to_string = function
  | Validation errs ->
      let details =
        List.map (fun e -> e.field ^ ": " ^ e.message) errs |> String.concat "; "
      in
      "validation error: " ^ details
  | Auth Missing_token -> "auth error: missing token"
  | Auth Invalid_token -> "auth error: invalid token"
  | Auth (Unauthorized reason) -> "auth error: unauthorized (" ^ reason ^ ")"
  | Network Timeout -> "network error: timeout"
  | Network (Connection_failed msg) -> "network error: connection failed (" ^ msg ^ ")"
  | Api { code; message; retriable } ->
      let retry = if retriable then "retriable" else "non-retriable" in
      "api error " ^ string_of_int code ^ " (" ^ retry ^ "): " ^ message
