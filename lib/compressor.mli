(** Zstandard compression module. *)

type t
(** The type for an explicit compression context that must be allocated once and
    reused across successive compression operations, improving memory
    efficiency.

    {b Note:}
    - Reusing a context is a performance and resource optimization and does not
      affect the compression ratio.
    - In multi-threaded environments, use a separate context per thread for
      parallel execution. *)

and compressor = t

val create : ?dictionary:Dictionary.t -> ?compression_level:int -> unit -> t
(** [create ?dictionary ?compression_level ()] creates a new compressor with
    parameters. *)

val set_compression_level : t -> int -> unit
(** [set_compression_level compressor level] sets a new compression level for
    the compressor. *)

val set_dictionary : t -> Dictionary.t -> unit
(** [set_dictionary compressor dictionary] loads a new dictionary for the
    compressor. *)

(** {2 One-shot compression}

    This section describes functions for one-shot compression of Zstandard
    frames. *)

val compression_upper_bound_for_size : int -> int
(** [compression_upper_bound_for_size size] returns the maximum buffer size
    required to safely store compressed data for an input of [size] bytes. *)

(** {3 Into already allocated buffers} *)

val compress_bigstring_into :
  in_slice:Slice_bstr.t -> out_slice:Slice_bstr.t -> t -> int
(** [compress_bigstring_into ~in_slice ~out_slice compressor] compresses
    [in_slice] content as a single Zstandard compressed frame into already
    allocated [out_slice].

    {b Hint}. The compression runs faster if the size of the [out_slice] is
    greater than or equal to the upper bound on the size of the [in_slice].

    @raise Zstd_error
      If the [out_slice] is too small, if memory allocation fails, or if invalid
      parameters are provided.

    @return Compressed size written into the [out_slice]. *)

val compress_string_into :
  in_slice:Slice_bytes.t -> out_slice:Slice_bytes.t -> t -> int
(** [compress_string_into ~in_slice ~out_slice compressor] is like
    {!compress_bigstring_into} but uses [string] values. *)

(** {3 Into fresh buffers} *)

val compress_bigstring : t -> Bstr.t -> Bstr.t
(** [compress_bigstring compressor contents] compresses the [contents] as a
    single Zstandard compressed frame into a newly allocated bigstring.

    @raise Zstd_error if compression fails.

    @return A newly allocated bigstring containing the compressed frame. *)

val compress_string : t -> string -> string
(** [compress_string compressor contents] is like {!compress_bigstring} but uses
    [string] values. *)

(** {2 Streaming compression}

    This section describes abstractions for streaming compression. *)

val compress_bigstring_stream :
  pull:(unit -> Slice_bstr.t option) -> push:(Slice_bstr.t -> unit) -> t -> unit
(** [compress_bigstring_stream ~pull ~push compressor] compresses a data stream
    by repeatedly pulling input slices from [pull] until [None] is returned, and
    pushing the resulting compressed chunks to [push].

    {b Example}.

    {[
    let pull () = read_slice source and push slice = write_slice destination in

    Ozstd.Compressor.compress_bigstring_stream ~pull ~push compressor
    ]}

    @raise Zstd_error if compression fails. *)

val compress_channel : t -> in_channel -> out_channel -> unit
(** [compress_channel compressor ic oc] compresses data from the input channel
    [ic] into the output channel [oc] using {!compress_bigstring_stream}.

    @raise Zstd_error if compression fails. *)

(** {3 Manual streaming compression} *)

module Stream : sig
  (** Manual streaming compression.

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
  (** The type for streaming compression contexts, wrapping a compressor
      context. *)

  val make : compressor -> t
  (** [make compressor] creates a streaming compression context from the
      compressor context. *)

  val in_size : unit -> int
  (** [in_size ()] returns the recommended input buffer size for streaming
      compression functions. *)

  val out_size : unit -> int
  (** [out_size ()] returns the recommended output buffer size for streaming
      compression functions. *)

  exception Already_closed
  (** Raised when attempting to close an already closed stream context. *)

  val compress_bigstring :
    in_slice:Slice_bstr.t ->
    out_slice:Slice_bstr.t ->
    t ->
    [< `Continue | `End | `Flush ] ->
    (remaining:int * consumed:int * compressed:int)
  (** [compress_bigstring ~in_slice ~out_slice stream directive] compresses the
      [in_slice] content as part of a Zstandard compressed frame into the
      [out_slice] with flushing control via the [directive] parameter.

      The [directive] parameter controls chunk compression:
      - [`Continue] Collects more data; the encoder decides when to output the
        compressed result for an optimal compression ratio.
      - [`Flush] Flushes any data provided so far, creating at least one new
        block that can be decoded immediately upon reception. The frame
        continues: future data can still reference previously compressed data,
        improving compression. {b Note:} Multithreaded compression blocks to
        flush as much output as possible.
      - [`End] Flushes any remaining data and closes the current frame.
        {b Note:} The frame is closed only after the compressed data is fully
        flushed (when remaining bytes equal 0). Afterward, any additional data
        starts a new frame.

      {b Note:} Each frame is independent and does not reference content from
      previous frames.

      @raise Zstd_error if compression fails.
      @raise Already_closed

      @return
        - [remaining]: the number of bytes remaining in the [in_slice],
        - [consumed]: the number of bytes consumed from the [in_slice],
        - [compressed]: the number of bytes written to the [out_slice]. *)

  val compress_string :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    [< `Continue | `End | `Flush ] ->
    (remaining:int * consumed:int * compressed:int)
  (** [compress_string ~in_slice ~out_slice stream] is like
      {!compress_bigstring} but uses [string] values. *)

  val close : t -> unit
  (** [close stream] closes the streaming compression context.

      @raise Already_closed if the stream is already closed. *)
end

(** {3 Automated streaming compression loop} *)

module State : sig
  (** Automated streaming compression loop.

      {b Example}.

      {[
      let compress_sequence_into_channel compressor seq oc =
        let state =
          (* Make a stream abstraction from an existing compressor *)
          Ozstd.Compressor.Stream.make compressor
          (* and wraps this stream into a state abstraction. *)
          |> Ozstd.Compressor.State.make stream
        in

        let output Slice.{ buf; off; len } =
          Out_channel.output_bigarray oc buf off len
        in

        Seq.iter
          (fun slice ->
            Ozstd.Compressor.State.feed state slice `Continue |> output)
          seq;

        Ozstd.Compressor.State.finish state |> output
      ]} *)

  type t
  (** The type for stateful streaming compression contexts, wrapping a stream
      context. *)

  val make : ?out_buf:Bstr.t -> Stream.t -> t
  (** [make ?out_buf stream] creates a stateful stream compression context.

      @param out_buf
        Internal compression buffer. If omitted, a buffer of size [out_size] is
        allocated automatically. *)

  val feed : t -> Slice_bstr.t -> [< `Continue | `End | `Flush ] -> Slice_bstr.t
  (** [feed state slice directive] feeds the [slice] content and compresses it
      into the internal compression buffer using {!Stream.compress_bigstring}.

      @raise Zstd_error if compression fails.

      @return
        A slice pointing to the compressed data within the internal buffer.
        {b Note:} The returned slice is valid only until the next call to
        [feed]. *)

  val finish : t -> Slice_bstr.t
  (** [finish state] flushes any remaining data, finalizes the compression
      stream, and returns the final compressed slice. *)
end
