module Make : Messenger_core.Http_client.HTTP_CLIENT = struct
  let unsupported on_error =
    on_error
      "cohttp client wiring is not enabled in this scaffold build; provide a runtime HTTP implementation"

  let request ~meth:_ ?headers:_ ?body:_ _url _on_success on_error =
    unsupported on_error

  let get ?headers:_ _url _on_success on_error = unsupported on_error

  let post ?headers:_ ?body:_ _url _on_success on_error = unsupported on_error

  let post_multipart ?headers:_ ~parts:_ _url _on_success on_error = unsupported on_error

  let put ?headers:_ ?body:_ _url _on_success on_error = unsupported on_error

  let delete ?headers:_ _url _on_success on_error = unsupported on_error
end
