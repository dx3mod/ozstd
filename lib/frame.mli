(** Zstandard compressed frame utilities. *)

val get_content_size_bigstring : Bstr.t -> int
(** [get_content_size_bigstring frame] returns the original uncompressed content
    size (in bytes) of the compressed [frame].

    @raise Zstd_error If the frame is invalid.
    @raise Not_found If the frame lacks a content size field in its header. *)

val get_content_size_bigstring_opt : Bstr.t -> int option
(** [get_content_size_bigstring_opt frame] is like {!get_content_size_bigstring}
    but returns [None] instead of raising an exception if the frame's content
    size is unknown.

    @raise Zstd_error If the frame is invalid. *)

val get_content_size_string : string -> int
(** [get_content_size_string frame] is like {!get_content_size_bigstring} but
    uses [string] values. *)

val get_content_size_string_opt : string -> int option
(** [get_content_size_string_opt frame] is like
    {!get_content_size_bigstring_opt} but uses [string] values. *)
