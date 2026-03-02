module type S = sig
  val platform : Platform_types.platform

  val send_message :
    Platform_types.outbound_message ->
    (Platform_types.message_id, Error_types.t) result
end

let validate_outbound_message (msg : Platform_types.outbound_message) =
  let errors =
    if String.length msg.text = 0 then
      [ { Error_types.field = "text"; message = "must not be empty" } ]
    else
      []
  in
  if errors = [] then Ok () else Error errors
