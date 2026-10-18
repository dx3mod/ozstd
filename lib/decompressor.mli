(** Zstandard decompression module. *)

type t
(** The type for an explicit decompression context that must be allocated once
    and reused across successive decompression operations, improving memory
    efficiency.

    {b Note:}
    - Reusing a context is a performance and resource optimization and does not
      affect the decompression output.
    - In multi-threaded environments, use a separate context per thread for
      parallel execution. *)

and decompressor = t

val create : ?size_limit:int -> ?dictionary:Dictionary.t -> unit -> t
(** [create ?size_limit ?dictionary ()] creates a new decompressor with
    parameters.

    The [size_limit] sets a maximum size limit (in bytes) beyond which the
    streaming API refuses to allocate a memory buffer, protecting the host from
    unreasonable memory requirements. This parameter is relevant only in
    streaming mode, as no internal buffers are allocated in single-frame mode.
*)

val set_size_limit : t -> int -> unit
(** [set_size_limit decompressor limit] sets a maximum size limit (in bytes) for
    the decompressor. *)

val set_dictionary : t -> Dictionary.t -> unit
(** [set_dictionary decompressor dictionary] loads a new dictionary for the
    decompressor. *)

(** {2 One-shot decompression}

    This section describes functions for one-shot decompression of Zstandard
    frames. *)

(** {3 Into already allocated buffers} *)

val decompress_bigstring_into :
  in_slice:Slice_bstr.t -> out_slice:Slice_bstr.t -> t -> int
(** [decompress_bigstring_into ~in_slice ~out_slice decompressor] decompresses
    the compressed Zstandard [in_slice] content frame into the already allocated
    [out_slice].

    @raise Zstd_error
      If the [out_slice] is too small, if memory allocation fails, or if invalid
      parameters are provided.

    @return Decompressed size written into the [out_slice]. *)

val decompress_string_into :
  in_slice:Slice_bytes.t -> out_slice:Slice_bytes.t -> t -> int
(** [decompress_string_into ~in_slice ~out_slice decompressor] is like
    {!decompress_bigstring_into} but uses [string] values. *)

(** {3 Into fresh buffers} *)

val decompress_bigstring : t -> Bstr.t -> Bstr.t
(** [decompress_bigstring decompressor frame] decompresses the compressed
    Zstandard content frame into a newly allocated bigstring.

    @raise Zstd_error if decompression fails.

    @return A newly allocated bigstring containing the decompressed frame. *)

val decompress_string : t -> string -> string
(** [decompress_string decompressor contents] is like {!decompress_bigstring}
    but uses [string] values. *)

(** {2 Streaming decompression}

    This section describes abstractions for streaming decompression. *)

val decompress_bigstring_stream :
  pull:(unit -> Slice_bstr.t option) -> push:(Slice_bstr.t -> unit) -> t -> unit
(** [decompress_bigstring_stream ~pull ~push compressor] decompresses a data
    stream by repeatedly pulling input slices from [pull] until [None] is
    returned, and pushing the resulting uncompressed chunks to [push].

    {b Example}.

    {[
    let pull () = read_slice source and push slice = write_slice destination in

    Ozstd.Decompressor.decompress_bigstring_stream ~pull ~push decompressor
    ]}

    @raise Zstd_error if compression fails. *)

val decompress_channel : decompressor -> in_channel -> out_channel -> unit
(** [decompress_channel decompressor ic oc] decompresses data from the input
    channel [ic] into the output channel [oc] using streaming decompression.

    @raise Zstd_error if decompression fails. *)

(** {3 Manual streaming decompression} *)

module Stream : sig
  (** Manual streaming decompression.

      {b Example}.

      {[
      let stream =
        let decompressor = Ozstd.Decompressor.create () in
        Ozstd.Decompressor.Stream.make decompressor

      let in_slice =
        Slice_bstr.make compressed_data (* holds a complete Zstandard frame *)

      and out_slice = Slice_bstr.create @@ Ozstd.Decompressor.Stream.out_size ()

      let ~remaining, ~consumed, ~decompressed =
        Ozstd.Decompressor.Stream.decompress_bigstring ~in_slice ~out_slice
          stream
      ]} *)

  type t
  (** The type for streaming decompression contexts, wrapping a decompressor
      context. *)

  val make : decompressor -> t
  (** [make decompressor] creates a streaming decompression context from the
      decompressor context. *)

  val in_size : unit -> int
  (** [in_size ()] returns the recommended input buffer size for streaming
      decompression functions. *)

  val out_size : unit -> int
  (** [out_size ()] returns the recommended output buffer size for streaming
      decompression functions. *)

  exception Already_closed
  (** Raised when attempting to close an already closed stream context. *)

  val decompress_bigstring :
    in_slice:Slice_bstr.t ->
    out_slice:Slice_bstr.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress_bigstring ~in_slice ~out_slice stream] decompresses the
      [in_slice] content into the [out_slice].

      @raise Zstd_error if decompression fails.

      @return
        - [remaining]: the number of bytes remaining in the [in_slice],
        - [consumed]: the number of bytes consumed from the [in_slice],
        - [decompressed]: the number of bytes written to the [out_slice]. *)

  val decompress_string :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress_string ~in_slice ~out_slice stream] is like
      {!decompress_bigstring} but uses [string] values. *)

  val close : t -> unit
  (** [close stream] closes the streaming decompression context.

      @raise Already_closed if the stream is already closed. *)
end

(** {3 Automated streaming decompression loop} *)

module State : sig
  (** Automated streaming decompression loop.

      {b Example}.

      {[
      let decompress_sequence_into_channel decompressor seq oc =
        let state =
          (* Make a stream abstraction from an existing decompressor *)
          Ozstd.Decompressor.Stream.make decompressor
          (* and wraps this stream into a state abstraction. *)
          |> Ozstd.Decompressor.State.make stream
        in

        Seq.iter
          (fun slice ->
            let Slice.{ buf; off; len } =
              Ozstd.Decompressor.State.feed state slice
            in

            Out_channel.output_bigarray oc buf off len)
          seq
      ]} *)

  type t
  (** The type for stateful streaming decompression contexts, wrapping a stream
      context. *)

  val make : ?out_buf:Bstr.t -> Stream.t -> t
  (** [make ?out_buf stream] creates a stateful stream decompression context.

      @param out_buf
        Internal decompression buffer. If omitted, a buffer of size [out_size]
        is allocated automatically. *)

  val feed : t -> Slice_bstr.t -> Slice_bstr.t
  (** [feed state slice] feeds the [slice] content and decompresses it into the
      internal decompression buffer.

      @raise Zstd_error if decompression fails.

      @return
        A slice pointing to the decompressed data within the internal buffer.
        {b Note:} The returned slice is valid only until the next call to
        [feed]. *)
end
