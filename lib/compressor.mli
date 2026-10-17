(** The Zstandard compression module.

    This module provides functions for both bulk and streaming compression. *)

type t
(** The compressor type allows compressing multiple chunks of data
    independently. It can be reused across multiple compression operations to
    avoid re-initialization overhead. *)

and compressor = t
(** Alias for {!t}. *)

val create : ?dictionary:Dictionary.t -> ?compression_level:int -> unit -> t
(** [create ?dictionary ?compression_level ()] creates a new compressor value.

    @param dictionary
      An optional dictionary to load. Using a dictionary can significantly
      improve the compression ratio on small data.

    @param compression_level
      The zstd quality setting, from [1] (fastest) to [22] (best ratio). Levels
      greater than or equal to [20] are considered "ultra" and should be used
      with caution, as they require more memory. *)

val set_compression_level : t -> int -> unit
(** [set_compression_level compressor compression_level] sets the compression
    level of an existing [compressor].

    @param compression_level
      The new level, from [1] (fastest) to [22] (best ratio). *)

val set_dictionary : t -> Dictionary.t -> unit
(** [set_dictionary compressor dictionary] sets the compression dictionary of an
    existing [compressor] *)

(** {2 Bulk compression} *)

(** {3 Compression into buffer} *)

val compress_bigstring_into :
  in_slice:Slice_bstr.t -> out_slice:Slice_bstr.t -> t -> int
(** [compress_bigstring_into ~in_slice ~out_slice compressor] compresses the
    data in [in_slice] into the pre-allocated buffer [out_slice].

    This is a low-level function that writes directly into a caller-provided
    buffer, avoiding intermediate allocations.

    @param in_slice The input data to compress.
    @param out_slice The output buffer where compressed data is written.
    @param compressor The compressor to use.

    @return The number of bytes written to [out_slice]. *)

val compress_string_into :
  in_slice:Slice_bytes.t -> out_slice:Slice_bytes.t -> t -> int
(** [compress_string_into ~in_slice ~out_slice compressor] compresses the data
    in [in_slice] into [out_slice].

    This is the [bytes]-based counterpart of {!compress_bigstring_into}.

    @return The number of bytes written to [out_slice]. *)

(** {3 Single compression} *)

val compress_bigstring : t -> Bstr.t -> Bstr.t
(** [compress_bigstring compressor input] compresses [input] in a single step
    and returns the compressed data as a fresh [Bstr.t].

    @param compressor The compressor to use.
    @param input The data to compress.

    @return The compressed data. *)

val compress_string : t -> string -> string
(** [compress_string compressor input] compresses [input] and returns the result
    as a new [string].

    This function allocates a new string for the output.

    @param compressor The compressor to use.
    @param input The data to compress.

    @return The compressed data. *)

val compress_channel : t -> in_channel -> out_channel -> unit
(** [compress_channel compressor ic oc] reads all data from [ic] until EOF,
    compresses it with [compressor], and writes the result to [oc] as a single
    zstd frame.

    Internally uses the streaming API with buffers of size {!Stream.in_size} /
    {!Stream.out_size}, so memory usage is bounded regardless of the channel
    size. [oc] is flushed before returning. *)

(** {2 Streaming compression}

    The streaming API is suitable for unbounded or large data streams where the
    entire input cannot be held in memory at once. *)

module Stream : sig
  type t
  (** The type of a streaming compression context.

      A stream context maintains the internal state needed to compress data
      incrementally. *)

  val make : compressor -> t
  (** [make compressor] creates a new stream context based on the given
      [compressor].

      @param compressor
        The compressor that provides the configuration and dictionary for this
        stream. *)

  val in_size : unit -> int
  (** [in_size ()] returns the recommended input buffer size for compression.

      Using buffers of this size can help achieve optimal performance. *)

  val out_size : unit -> int
  (** [out_size ()] returns the recommended output buffer size for compression.
  *)

  exception Already_closed
  (** Raised when attempting to use a stream context that has already been
      closed with {!close}, or after a [compress_bigstring]/[compress_string]
      call that was issued with the [`End] directive. *)

  val compress_bigstring :
    in_slice:Slice_bstr.t ->
    out_slice:Slice_bstr.t ->
    t ->
    [< `Continue | `End | `Flush ] ->
    (remaining:int * consumed:int * compressed:int)
  (** [compress_bigstring ~in_slice ~out_slice stream directive] feeds the data
      in [in_slice] to the compression [stream] and writes any available
      compressed output to [out_slice].

      The [directive] parameter controls how the stream behaves:

      - [`Continue]: process input normally without forcing a flush.
      - [`End]: signal that this is the last chunk; the stream will finalize the
        compressed frame.
      - [`Flush]: force the stream to flush all buffered output to [out_slice].

      @return
        A triple [(remaining, consumed, compressed)] where:
        - [remaining] is the number of input bytes that were not consumed,
        - [consumed] is the number of input bytes that were actually consumed,
        - [compressed] is the number of bytes written to [out_slice].

      @raise Already_closed if the stream has been closed. *)

  val compress_string :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    [< `Continue | `End | `Flush ] ->
    (remaining:int * consumed:int * compressed:int)
  (** [compress_string] is the [bytes]-based counterpart of
      {!compress_bigstring}. *)

  val close : t -> unit
  (** [close stream] closes the [stream].

      After calling [close], the stream must not be used again. Attempting to do
      so will raise {!Already_closed}. *)
end

(** {3 Incremental compression, automated} *)

(** A stateful wrapper around {!Stream} that manages the output buffer and the
    compression loop for you. *)
module State : sig
  type t = { stream : Stream.t; out_buf : Bstr.t }
  (** A higher-level stateful wrapper around a {!Stream.t}.

      This type bundles a stream context with a reusable output buffer, making
      it easier to perform repeated compression steps without manually managing
      buffer allocations.

      Use {!make} to construct a value; the record fields are exposed mainly for
      introspection and should not be mutated directly. *)

  val make : ?out_buf:Bstr.t -> Stream.t -> t
  (** [make ?out_buf stream] creates a new {!t} from an existing [stream].

      @param out_buf
        An optional pre-allocated output buffer. If omitted, a buffer of the
        recommended size ({!Stream.out_size}) is allocated.

      @param stream The underlying stream context. *)

  val feed : t -> Slice_bstr.t -> [< `Continue | `End | `Flush ] -> Slice_bstr.t
  (** [feed state in_slice directive] compresses [in_slice] and returns a slice
      of the internal output buffer containing the newly produced compressed
      data.

      The returned slice is valid only until the next call to [feed] or
      {!finish}.

      @param state The stateful compression context.
      @param in_slice The input data for this step.
      @param directive
        The same flushing semantics as in {!Stream.compress_bigstring}.

      @return
        A slice pointing to the compressed output within the internal buffer. *)

  val finish : t -> Slice_bstr.t
  (** [finish state] signals the end of the input stream, finalizes compression,
      and returns any remaining compressed output as a slice.

      After calling [finish], the state should no longer be used for further
      compression.

      @return A slice containing the final compressed bytes. *)
end
