type t = [ `String of string | `Bigstring of Bstr.t ]

let uncompressed_size = function
  | `String string -> Bindings.get_decompression_size_of_string string
  | `Bigstring bigstring ->
      Bindings.get_decompression_size_of_bigstring bigstring

let of_string s =
  match String.get_int32_le s 0 with
  | 0xFD2FB528l -> `String s
  | _ -> invalid_arg "not a zstd frame"

let of_bigstring bs =
  match Bstr.get_int32_le bs 0 with
  | 0xFD2FB528l -> `Bigstring bs
  | _ -> invalid_arg "not a zstd frame"
