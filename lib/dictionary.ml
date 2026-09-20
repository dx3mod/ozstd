type t = Bstr.t

let of_bigstring bs =
  match Bstr.get_int32_le bs 0 with
  | 0xEC30A437l -> bs
  | _ when Bstr.length bs >= 8 -> bs
  | _ | (exception Invalid_argument _) -> invalid_arg "illegal zstd dictionary"

let of_string s = Bstr.of_string s |> of_bigstring
