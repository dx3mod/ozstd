(** The Zstandard decompression module.

    This module provides functions for both bulk and streaming decompression. *)

type t
(** The decompressor type holds Zstandard internal state and a mutex.

    A decompressor can be reused across many decompression calls to avoid
    re-initialization overhead. *)

and decompressor = t
(** Alias for {!t}. *)

val create : ?size_limit:int -> ?dictionary:Dictionary.t -> unit -> t
(** [create ?size_limit ?dictionary ()] creates a new decompressor value.

    @param size_limit
      An optional cap on the sliding window size. See {!set_size_limit}.

    @param dictionary An optional dictionary to load. *)

val set_size_limit : t -> int -> unit
(** [set_size_limit decompressor size] caps the size of the sliding window the
    decompressor will accept at [size] bytes, protecting against decompression
    bombs.

    @param decompressor The decompressor to configure.
    @param size The new upper bound on the window size, in bytes. *)

(** {2 Bulk decompression} *)

(** {3 Decompression into buffer} *)

val decompress_bigstring_into :
  in_slice:Slice_bstr.t -> out_slice:Slice_bstr.t -> t -> int
(** [decompress_bigstring_into ~in_slice ~out_slice decompressor] decompresses
    the data in [in_slice] into the pre-allocated buffer [out_slice].

    This is a low-level function: the caller is responsible for sizing
    [out_slice] correctly. For frames produced by
    {!Zstandard.Compressor.compress_bigstring} the required size can be read
    from the frame header with [Frame.uncompressed_size]; for frames produced by
    the streaming API the size may not be stored at all, in which case the
    caller must know it out of band.

    @param in_slice The compressed input data.
    @param out_slice
      The destination buffer; it must be large enough to hold the full
      decompressed payload.
    @param decompressor The decompressor to use.

    @return The number of bytes written to [out_slice]. *)

val decompress_bytes_into :
  in_slice:Slice_bytes.t -> out_slice:Slice_bytes.t -> t -> int
(** [decompress_bytes_into ~in_slice ~out_slice decompressor] decompresses the
    data in [in_slice] into [out_slice].

    This is the [bytes]-based counterpart of {!decompress_bigstring_into}; the
    same sizing caveat applies.

    @return The number of bytes written to [out_slice]. *)

(** {3 Single decompression} *)

val decompress_bigstring : t -> Bstr.t -> Bstr.t
(** [decompress_bigstring decompressor compressed] decompresses [compressed] and
    returns the original data in a fresh bigstring.

    The destination size is read from the frame header using
    [Frame.uncompressed_size], so [compressed] must be a frame that stores its
    content size. Frames produced by {!Zstandard.Compressor.compress_bigstring}
    and {!Zstandard.Compressor.compress_bytes} satisfy this condition; frames
    produced by the streaming API may not — use {!decompress_bigstring_into} for
    those.

    @param decompressor The decompressor to use.
    @param compressed The compressed input frame.

    @return A fresh bigstring holding the decompressed data. *)

val decompress_bytes : t -> string -> string
(** [decompress_bytes decompressor compressed] decompresses the compressed
    string [compressed] and returns the original data as a new [bytes].

    The destination size is read from the frame header, so [compressed] must be
    a frame that stores its content size (same constraint as
    {!decompress_bigstring}).

    @param decompressor The decompressor to use.
    @param compressed The compressed input frame.

    @return A fresh [string] buffer holding the decompressed data. *)

val decompress_channel : decompressor -> in_channel -> out_channel -> unit
(** [decompress_channel decompressor ic oc] streams data from [ic] to [oc],
    decompressing it on the fly.

    @param decompressor The decompressor to use.
    @param ic The input channel holding compressed data.
    @param oc The output channel for decompressed data. *)

(** {2 Streaming decompression}

    The streaming API is suitable for unbounded or large data streams where the
    entire input cannot be held in memory at once, or for frames that do not
    store their content size. *)

module Stream : sig
  type t
  (** The type of a streaming decompression context.

      A stream context wraps a {!decompressor} and tracks whether it has been
      closed. *)

  val make : decompressor -> t
  (** [make decompressor] creates a new stream context based on the given
      [decompressor].

      @param decompressor
        The decompressor that provides the configuration and dictionary for this
        stream. *)

  val in_size : unit -> int
  (** [in_size ()] returns the recommended input buffer size for decompression.
  *)

  val out_size : unit -> int
  (** [out_size ()] returns the recommended output buffer size for
      decompression. *)

  exception Already_closed
  (** Raised when attempting to use a stream context that has already been
      closed with {!close}. *)

  val decompress_bigstring :
    in_slice:Slice_bstr.t ->
    out_slice:Slice_bstr.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress_bigstring ~in_slice ~out_slice stream] decompresses the bytes
      of [in_slice] into [out_slice], feeding [stream].

      Call this function in a loop, refilling [in_slice] and draining
      [out_slice] until the whole frame has been decoded. The stream does not
      signal end-of-frame by itself; the caller detects completion either from
      the known expected output size or by observing that the input has been
      fully consumed and the trailing frame bytes have been processed.

      @param in_slice The input buffer holding compressed data.
      @param out_slice The output buffer to write decompressed bytes into.
      @param stream The stream to feed.

      @return
        A triple [(remaining, consumed, decompressed)] where:
        - [remaining] is the number of bytes of [in_slice] not yet processed,
        - [consumed] is the number of bytes of [in_slice] actually processed,
        - [decompressed] is the number of bytes written to [out_slice].

      @raise Already_closed if [stream] was closed. *)

  val decompress_bytes :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress_bytes] is the [bytes]-based counterpart of
      {!decompress_bigstring}.

      {b Runtime note.} Unlike bigstrings, [bytes] block the OCaml runtime while
      the C code runs. *)

  val close : t -> unit
  (** [close stream] closes the [stream].

      After calling [close], the stream must not be used again. Attempting to do
      so will raise {!Already_closed}.

      @raise Already_closed if [stream] is already closed. *)
end

(** {3 Incremental decompression, automated} *)

(** A stateful wrapper around {!Stream} that manages the output buffer and the
    decompression loop for you. *)
module State : sig
  type t
  (** An automated decompression state.

      Bundles a {!Stream.t} with a reusable output buffer. *)

  val make : ?out_buf:Bstr.t -> Stream.t -> t
  (** [make ?out_buf stream] creates a new {!t} from an existing [stream].

      @param out_buf
        The output buffer to use. If omitted, a buffer of size
        {!Stream.out_size} is allocated.

      @param stream The underlying stream context. *)

  val feed : t -> Slice_bstr.t -> Slice_bstr.t
  (** [feed state slice] decompresses [slice] and returns a slice of the
      internal output buffer containing the decompressed bytes produced during
      this call.

      The function loops internally until either all of [slice] has been
      consumed or no further progress can be made. Because the internal output
      buffer is reused across iterations, the returned slice reflects only the
      output of the last iteration; callers that need every byte should provide
      a sufficiently large [out_buf], or drive {!Stream} directly.

      The returned slice is valid only until the next call to [feed].

      @param state The stateful decompression context.
      @param slice The compressed input for this step.

      @return
        A slice pointing to the decompressed output within the internal buffer.

      @raise Stream.Already_closed if the underlying stream was closed. *)
end
