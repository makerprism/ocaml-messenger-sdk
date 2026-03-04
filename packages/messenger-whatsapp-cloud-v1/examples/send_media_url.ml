(* send_media_url.ml — Send media URLs via mock WhatsApp Cloud API.

   Demonstrates supported media types (extension-based inference):
   - Image: .jpg, .jpeg, .png, .webp, .gif
   - Video: .mp4, .3gp, .mov
   - Document: .pdf, .doc, .docx, .ppt, .pptx, .xls, .xlsx, .txt, .csv, .rtf

   Also demonstrates:
   - Caption handling (text as caption when media is present)
   - Unsupported extension validation error
   - Multi-media URL validation error (only one URL supported in MVP)

   Expected output:
     --- Image with caption ---
     POST https://graph.facebook.com/v19.0/1234567890/messages
     Body: {"messaging_product":"whatsapp","to":"15551234567","type":"image","image":{"link":"https://example.com/photo.jpg","caption":"A photo"}}
     OK: message_id = wamid.test123

     --- Video without caption ---
     POST https://graph.facebook.com/v19.0/1234567890/messages
     Body: {"messaging_product":"whatsapp","to":"15551234567","type":"video","video":{"link":"https://example.com/clip.mp4"}}
     OK: message_id = wamid.test123

     --- Document (PDF) with caption ---
     POST https://graph.facebook.com/v19.0/1234567890/messages
     Body: {"messaging_product":"whatsapp","to":"15551234567","type":"document","document":{"link":"https://example.com/report.pdf","caption":"Monthly report"}}
     OK: message_id = wamid.test123

     --- Unsupported extension (.bin) ---
     Error: validation error: media_urls: unable to infer media type from URL extension (supported: image, video, document)

     --- Multiple media URLs (unsupported in MVP) ---
     Error: validation error: media_urls: only one media URL is supported in MVP
*)

open Messenger_core

module Mock_http : Http_client.HTTP_CLIENT = struct
  let post ?headers:_ ?body url on_success _on_error =
    Printf.printf "POST %s\n" url;
    (match body with Some b -> Printf.printf "Body: %s\n" b | None -> ());
    on_success
      { Http_client.status = 200
      ; headers = []
      ; body = {|{"messages":[{"id":"wamid.test123"}]}|}
      }

  let request ~meth:_ ?headers ?body url on_success on_error =
    post ?headers ?body url on_success on_error

  let get ?headers:_ _url on_success _on_error =
    on_success { Http_client.status = 200; headers = []; body = {|{"id":"1234567890"}|} }

  let post_multipart ?headers:_ ~parts:_ _url _on_success on_error =
    on_error "not implemented"

  let put ?headers:_ ?body:_ _url _on_success on_error =
    on_error "not implemented"

  let delete ?headers:_ _url _on_success on_error =
    on_error "not implemented"
end

module Connector = Messenger_whatsapp_cloud_v1.Make (struct
  module Http = Mock_http

  let get_access_token ~account_id:_ = Ok (Some "test-access-token")
end)

let send_and_print message =
  Connector.send_message ~account_id:"1234567890" message (function
    | Ok msg_id -> Printf.printf "OK: message_id = %s\n" msg_id
    | Error err -> Printf.printf "Error: %s\n" (Error_types.to_string err))

let () =
  Printf.printf "--- Image with caption ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "A photo"
    ; media_urls = [ "https://example.com/photo.jpg" ]
    ; metadata = []
    };
  print_newline ();

  Printf.printf "--- Video without caption ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = ""
    ; media_urls = [ "https://example.com/clip.mp4" ]
    ; metadata = []
    };
  print_newline ();

  Printf.printf "--- Document (PDF) with caption ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "Monthly report"
    ; media_urls = [ "https://example.com/report.pdf" ]
    ; metadata = []
    };
  print_newline ();

  Printf.printf "--- Unsupported extension (.bin) ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "hello"
    ; media_urls = [ "https://example.com/data.bin" ]
    ; metadata = []
    };
  print_newline ();

  Printf.printf "--- Multiple media URLs (unsupported in MVP) ---\n";
  send_and_print
    { Platform_types.recipient = Phone_number "15551234567"
    ; text = "hello"
    ; media_urls = [ "https://example.com/a.jpg"; "https://example.com/b.jpg" ]
    ; metadata = []
    }
