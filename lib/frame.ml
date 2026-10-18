let get_content_size_bigstring frame =
  Bindings.get_frame_content_size_bigstring frame

let get_content_size_bigstring_opt frame =
  try Some (get_content_size_bigstring frame) with Not_found -> None

let get_content_size_string frame = Bindings.get_frame_content_size_string frame

let get_content_size_string_opt frame =
  try Some (get_content_size_string frame) with Not_found -> None
