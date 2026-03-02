let () =
  let open Messenger_core in
  let message : Platform_types.outbound_message =
    {
      recipient = Platform_types.User_id "user-1";
      text = "hello";
      metadata = [];
    }
  in
  match Connector_intf.validate_outbound_message message with
  | Ok () -> ()
  | Error _ -> failwith "expected valid message"
