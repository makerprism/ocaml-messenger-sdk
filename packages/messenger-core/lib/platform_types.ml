type platform =
  | Telegram_bot
  | Whatsapp_cloud
  | Signal_bridge
  | Custom of string

type recipient =
  | User_id of string
  | Phone_number of string
  | Channel_id of string

type outbound_message = {
  recipient : recipient;
  text : string;
  media_urls : string list;
  metadata : (string * string) list;
}

type message_id = string

type thread_request = {
  posts : outbound_message list;
}

type thread_result = {
  posted_ids : message_id list;
  failed_at_index : int option;
  total_requested : int;
}
