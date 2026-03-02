type response = Messenger_core.Http_client.response
type multipart_part = Messenger_core.Http_client.multipart_part
type method_ = Messenger_core.Http_client.method_
type error = string

let cps_to_lwt register =
  let promise, wakener = Lwt.wait () in
  let settled = ref false in
  let resolve value =
    if not !settled then (
      settled := true;
      Lwt.wakeup_later wakener value)
  in
  (try
     register
       ~on_success:(fun value -> resolve (Ok value))
       ~on_error:(fun err -> resolve (Error err))
   with exn ->
    if not !settled then (
      settled := true;
      Lwt.wakeup_later_exn wakener exn));
  promise

module type HTTP_CLIENT = Messenger_core.Http_client.HTTP_CLIENT

module type HTTP_CLIENT_LWT = sig
  val request :
    meth:method_ ->
    ?headers:(string * string) list ->
    ?body:string ->
    string ->
    unit ->
    (response, error) result Lwt.t

  val get :
    ?headers:(string * string) list ->
    string ->
    unit ->
    (response, error) result Lwt.t

  val post :
    ?headers:(string * string) list ->
    ?body:string ->
    string ->
    unit ->
    (response, error) result Lwt.t

  val post_multipart :
    ?headers:(string * string) list ->
    parts:multipart_part list ->
    string ->
    unit ->
    (response, error) result Lwt.t

  val put :
    ?headers:(string * string) list ->
    ?body:string ->
    string ->
    unit ->
    (response, error) result Lwt.t

  val delete :
    ?headers:(string * string) list ->
    string ->
    unit ->
    (response, error) result Lwt.t
end

module Adapt_http_client (Client : HTTP_CLIENT) : HTTP_CLIENT_LWT = struct
  let request ~meth ?headers ?body url () =
    cps_to_lwt (fun ~on_success ~on_error ->
        Client.request ~meth ?headers ?body url on_success on_error)

  let get ?headers url () =
    cps_to_lwt (fun ~on_success ~on_error ->
        Client.get ?headers url on_success on_error)

  let post ?headers ?body url () =
    cps_to_lwt (fun ~on_success ~on_error ->
        Client.post ?headers ?body url on_success on_error)

  let post_multipart ?headers ~parts url () =
    cps_to_lwt (fun ~on_success ~on_error ->
        Client.post_multipart ?headers ~parts url on_success on_error)

  let put ?headers ?body url () =
    cps_to_lwt (fun ~on_success ~on_error ->
        Client.put ?headers ?body url on_success on_error)

  let delete ?headers url () =
    cps_to_lwt (fun ~on_success ~on_error ->
        Client.delete ?headers url on_success on_error)
end
