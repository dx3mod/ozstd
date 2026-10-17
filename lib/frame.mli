type t = private [ `Bigstring of Bstr.t | `String of string ]

val uncompressed_size : t -> int
val of_string : string -> t
val of_bigstring : Bstr.t -> t
