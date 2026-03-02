type method_ =
  | GET
  | POST
  | PUT
  | DELETE
  | PATCH

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

type multipart_part = {
  name : string;
  body : string;
  filename : string option;
  content_type : string option;
}

module type HTTP_CLIENT = sig
  val request :
    meth:method_ ->
    ?headers:(string * string) list ->
    ?body:string ->
    string ->
    (response -> unit) ->
    (string -> unit) ->
    unit

  val get :
    ?headers:(string * string) list ->
    string ->
    (response -> unit) ->
    (string -> unit) ->
    unit

  val post :
    ?headers:(string * string) list ->
    ?body:string ->
    string ->
    (response -> unit) ->
    (string -> unit) ->
    unit

  val post_multipart :
    ?headers:(string * string) list ->
    parts:multipart_part list ->
    string ->
    (response -> unit) ->
    (string -> unit) ->
    unit

  val put :
    ?headers:(string * string) list ->
    ?body:string ->
    string ->
    (response -> unit) ->
    (string -> unit) ->
    unit

  val delete :
    ?headers:(string * string) list ->
    string ->
    (response -> unit) ->
    (string -> unit) ->
    unit
end
