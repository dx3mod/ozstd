(** The Zstandard decompression module.

    The module covers the decompression features of the Zstandard (zstd) C
    library. *)

(** {2 Reusable contexts} *)

(** A decompression context holding Zstandard internal state.

    Contexts are mutex-guarded and may be shared across threads. *)
module Context : sig
  type t

  val create : unit -> t
  (** [create ()] returns a fresh, unconfigured decompression context. *)

  val set_size_limit : t -> int -> unit
  (** [set_size_limit context size] caps the size of the internal decompression
      buffer of [context] at [size] bytes, protecting against decompression
      bombs. *)

  val load_dictionary : t -> Dictionary.t -> unit
  (** [load_dictionary context dict] loads [dict] into [context]. Every
      decompression call using [context] subsequently applies [dict]. *)
end

(** {2 One-shot decompression} *)

val decompress_bigstring :
  ?context:Context.t -> ?dictionary:Dictionary.t -> Bstr.t -> Bstr.t
(** [decompress_bigstring ?context ?dictionary bigstring] decompresses the
    compressed [bigstring] and returns the original data in a fresh bigstring.

    @param context reuse a context instead of creating a fresh one.
    @param dictionary an optional dictionary that was used for compression.

    @raise Ozstd.Zstd_error
      if the frame does not store its content size, as produced by streaming
      compression. See {!decompress_string_into_bytes}. *)

val decompress_string :
  ?context:Context.t -> ?dictionary:Bstr.t -> string -> string
(** [decompress_string ?context ?dictionary string] decompresses the compressed
    [string] and returns the original data as a new string.

    @param context reuse a context instead of creating a fresh one.
    @param dictionary an optional dictionary that was used for compression.

    @raise Ozstd.Zstd_error
      if the frame does not store its content size, as produced by streaming
      compression. See {!decompress_string_into_bytes}. *)

val decompress_channel :
  ?dictionary:Dictionary.t ->
  ?size_limit:int ->
  in_channel ->
  out_channel ->
  unit
(** [decompress_channel ?dictionary ?size_limit ic oc] streams data from [ic] to
    [oc], decompressing it on the fly. *)

(** {3 Into} *)

val decompress_bigstring_into :
  ?context:Context.t -> ?dictionary:Dictionary.t -> Bstr.t -> Bstr.t -> int
(** [decompress_bigstring_into ?context ?dictionary src dst] decompresses [src]
    into the destination bigstring [dst].

    @param dst
      the destination buffer, large enough for the original data. Its size can
      be read from the frame header with
      {!Ozstd.Compressor.Frame.uncompressed_size}.
    @return the number of bytes written to [dst]. *)

val decompress_string_into_bytes :
  ?context:Context.t -> ?dictionary:Dictionary.t -> string -> bytes -> int
(** [decompress_string_into_bytes ?context ?dictionary src dst] decompresses
    [src] into the destination [bytes] [dst]. Use this for frames without a
    stored content size (produced by streaming compression), providing a [dst]
    large enough for the original data.

    @param dst the destination buffer, large enough for the original data.
    @return the number of bytes written to [dst]. *)

(** {2 Incremental decompression} *)

(** The decompression stream module. This is the manual, buffer-level API: you
    are in charge of the buffers and of tracking progress yourself. *)
module Stream : sig
  type t

  exception Already_closed
  (** Raised when using a stream that has been closed. *)

  val create : ?dictionary:Dictionary.t -> ?size_limit:int -> unit -> t
  (** [create ?dictionary ?size_limit ()] returns a fresh decompression stream.

      @param dictionary an optional dictionary used for compression.
      @param size_limit an optional cap on the decompressed size. *)

  val close : t -> unit
  (** [close stream] explicitly closes [stream].

      @raise Already_closed if [stream] is already closed. *)

  val decompress :
    in_slice:Slice_bstr.t ->
    out_slice:Slice_bstr.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress ~in_slice ~out_slice stream] decompresses the bytes of
      [in_slice] into [out_slice], feeding [stream].

      @param in_slice the input buffer holding compressed data.
      @param out_slice the output buffer to write decompressed bytes into.
      @return
        A triple where [remaining] is the number of bytes of [in_slice] not yet
        processed, [consumed] the number consumed, and [decompressed] the number
        of bytes written to [out_slice]. Call it repeatedly, refilling
        [in_slice] and emptying [out_slice], until all data is processed.

      @raise Already_closed if [stream] was closed. *)

  val decompress_bytes :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress_bytes ~in_slice ~out_slice stream] is {!decompress} with
      [bytes]-based slices. Useful if you prefer mutable [bytes] to bigstrings;
      the interface and semantics are identical.

      {b Runtime note.} Unlike bigstrings, [bytes] block the OCaml runtime while
      the C code runs. *)

  val in_size : unit -> int
  (** [in_size ()] is the recommended input buffer size for {!decompress}. *)

  val out_size : unit -> int
  (** [out_size ()] is the recommended output buffer size for {!decompress}. *)
end

(** {2 Incremental decompression, automated} *)

(** The decompression stream state module: wraps a {!Stream} so that buffers and
    progress are managed for you. *)
module State : sig
  type t

  val make : ?out_buf:Bstr.t -> ?stream:Stream.t -> unit -> t
  (** [make ?out_buf ?stream ()] returns the state built on the existing
      [stream].

      @param out_buf
        the output buffer to use; allocated automatically if omitted.
      @param stream the stream to use; a fresh one is created if omitted. *)

  val create : ?dictionary:Dictionary.t -> ?size_limit:int -> unit -> t
  (** [create ?dictionary ?size_limit ()] returns a fresh state with its own
      stream and output buffer.

      @param dictionary an optional dictionary used for compression.
      @param size_limit an optional cap on the decompressed size. *)

  val feed : t -> Slice_bstr.t -> Slice_bstr.t
  (** [feed state slice] decompresses [slice] and returns the decompressed
      output as a slice.

      @raise Stream.Already_closed if the underlying stream was closed. *)
end
