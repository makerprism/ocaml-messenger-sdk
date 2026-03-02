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
  metadata : (string * string) list;
}

type message_id = string
