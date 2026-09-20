(** The Zstandard dictionaries module.

    Dictionaries are pre-trained samples that make compression of small, similar
    messages much more effective.

    A dictionary is an opaque value as far as this library is concerned: any
    byte sequence produced by zstd's [ZDICT_trainFromBuffer] (or another zstd
    tool) is a valid {!t}.

    Load one onto a {!Ozstd.Compressor.Context} or {!Ozstd.Decompressor.Context}
    to apply it to every call using that context, or pass it directly to the
    one-shot and streaming functions that accept it *)

type t = private Bstr.t
(** A bigstring dictionary. *)

val of_bigstring : Bstr.t -> t
(** [of_bigstring dict] *)

val of_string : string -> t
(** [of_string dict] *)
