(** The Zstandard compression module.

    The module covers the compression features of the Zstandard (zstd) C
    library. *)

(** {2 Reusable contexts} *)

(** A compression context holding Zstandard internal state.

    Creating a context is heavy; create one once and reuse it. Contexts are
    mutex-guarded and may be shared across threads. *)
module Context : sig
  type t

  val create : unit -> t
  (** [create ()] returns a fresh, unconfigured compression context. *)

  val set_compression_level : t -> int -> unit
  (** [set_compression_level context level] sets the compression [level] of
      [context]. *)

  val load_dictionary : t -> Dictionary.t -> unit
  (** [load_dictionary context dict] loads [dict] into [context]. Every
      compression call using [context] subsequently applies [dict]. *)
end

(** {2 Frame metadata} *)

module Frame : sig
  type t = [ `Bigstring of Bstr.t | `String of string ]
  (** A compressed frame, stored either as a bigstring or as a string. *)

  val uncompressed_size : t -> int
  (** [uncompressed_size frame] returns the original size of the data stored in
      [frame], read from the frame header without decompressing. *)
end

(** {2 One-shot compression} *)

val compress_bigstring :
  ?context:Context.t ->
  ?dictionary:Dictionary.t ->
  level:int ->
  Bstr.t ->
  Bstr.t
(** [compress_bigstring ?context ?dictionary ~level bigstring] compresses
    [bigstring] and returns the compressed data in a fresh bigstring trimmed to
    its exact size.

    @param context
      reuse a context to tune the compression parameters (e.g. a loaded
      dictionary) instead of creating a fresh one.
    @param dictionary an optional dictionary to apply.
    @param level
      the zstd quality setting, from [1] (fastest) to [22] (best ratio). [3] is
      a reasonable default. *)

val compress_string :
  ?context:Context.t ->
  ?dictionary:Dictionary.t ->
  level:int ->
  string ->
  string
(** [compress_string ?context ?dictionary ~level string] compresses [string] and
    returns the compressed data as a new string.

    @param context reuse a context instead of creating a fresh one.
    @param dictionary an optional dictionary to apply.
    @param level
      the zstd quality setting, from [1] (fastest) to [22] (best ratio). [3] is
      a reasonable default. *)

val compress_channel :
  ?dictionary:Dictionary.t -> level:int -> in_channel -> out_channel -> unit
(** [compress_channel ?dictionary ~level ic oc] streams data from [ic] to [oc],
    compressing it on the fly. *)

(** {3 Into} *)

val compress_bigstring_into :
  ?context:Context.t ->
  ?dictionary:Dictionary.t ->
  level:int ->
  Bstr.t ->
  Bstr.t ->
  int
(** [compress_bigstring_into ?context ?dictionary ~level src dst] compresses
    [src] into the destination bigstring [dst].

    @param dst
      the destination buffer. Make it at least as large as the compressed data;
      {!compress_bigstring} computes the exact size. When the final size is
      unknown, a buffer of the uncompressed size plus a margin is a safe upper
      bound.

    @raise Failure if [dst] is too small for the compressed data.
    @return the number of bytes written to [dst]. *)

val compress_string_into :
  ?context:Context.t ->
  ?dictionary:Dictionary.t ->
  level:int ->
  string ->
  bytes ->
  int
(** [compress_string_into ?context ?dictionary ~level src dst] compresses [src]
    into the destination [bytes] [dst]. See {!compress_bigstring_into}.

    @param dst the destination buffer.
    @return the number of bytes written to [dst]. *)

(** {2 Incremental compression} *)

(** The compression stream module.

    The module is the manual, buffer-level API: you are in charge of the buffers
    and of tracking progress yourself ({!State} automates this). *)
module Stream : sig
  type t

  (** {2 Construction} *)

  val create : ?dictionary:Dictionary.t -> ?level:int -> unit -> t
  (** [create ?dictionary ?level ()] returns a fresh compression stream.

      @param dictionary an optional dictionary to apply.
      @param level the zstd quality setting; see {!compress_bigstring}. *)

  val of_context : Context.t -> t
  (** [of_context context] returns a compression stream built on the existing
      [context], inheriting its parameters and dictionary. *)

  (** {2 Closeting} *)

  exception Already_closed
  (** Raised when using a stream that has been closed.. *)

  val close : t -> unit
  (** [close stream] explicitly closes [stream].

      @raise Already_closed if [stream] is already closed. *)

  (** {2 Compression} *)

  val compress :
    in_slice:Slice_bstr.t ->
    out_slice:Slice_bstr.t ->
    t ->
    [ `Continue | `End | `Flush ] ->
    (remaining:int * consumed:int * compressed:int)
  (** [compress ~in_slice ~out_slice stream mode] compresses the bytes of
      [in_slice] into [out_slice], feeding [stream].

      @param mode controls flushing:

      - [`Continue] keeps the stream running and does not flush;
      - [`Flush] flushes so compressors see all input so far;
      - [`End] terminates the frame and closes the stream once [in_slice] is
        fully consumed.

      @param in_slice the input buffer to compress.
      @param out_slice the output buffer to write compressed bytes into.
      @return
        A triple where [remaining] is the number of bytes of [in_slice] not yet
        processed, [consumed] the number consumed, and [compressed] the number
        of bytes written to [out_slice]. Call it repeatedly, refilling
        [in_slice] and emptying [out_slice], until all data is processed.

      @raise Already_closed if [stream] was ended with [`End]. *)

  val compress_bytes :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    [ `Continue | `End | `Flush ] ->
    (remaining:int * consumed:int * compressed:int)
  (** [compress_bytes ~in_slice ~out_slice stream mode] is {!compress} with
      [bytes]-based slices. Useful if you prefer mutable [bytes] to bigstrings;
      the interface and semantics are identical.

      {b Runtime note.} Unlike bigstrings, [bytes] block the OCaml runtime while
      the C code runs. *)

  (** {2 Buffer sizes} *)

  val in_size : unit -> int
  (** [in_size ()] is the recommended input buffer size for {!compress}. *)

  val out_size : unit -> int
  (** [out_size ()] is the recommended output buffer size for {!compress}. *)
end

(** {3 Automated} *)

(** A compression state: wraps a {!Stream} so that buffers and progress are
    managed for you. *)
module State : sig
  type t

  val make : ?out_buf:Bstr.t -> Stream.t -> t
  (** [make ?out_buf stream] returns the state built on the existing [stream].

      @param out_buf
        the output buffer to use; allocated automatically if omitted. *)

  val create : ?dictionary:Dictionary.t -> ?level:int -> unit -> t
  (** [create ?dictionary ?level ()] returns a fresh state with its own stream
      and output buffer.

      @param dictionary an optional dictionary to apply.
      @param level the zstd quality setting; see {!compress_bigstring}. *)

  val feed : t -> Slice_bstr.t -> [ `Continue | `Flush | `End ] -> Slice_bstr.t
  (** [feed state slice mode] compresses [slice] and returns the compressed
      output as a slice. [mode] behaves as in {!Stream.compress}. *)

  val finish : t -> Slice_bstr.t
  (** [finish state] emits the last part of the frame and closes the state. *)
end
