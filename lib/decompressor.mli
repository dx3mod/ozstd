(** The Zstandard decompression module.

    This module provides functions for both bulk and streaming decompression. *)

type t
(** The decompressor holds an internal state that can be reused across multiple
    calls to eliminate re-initialization overhead. *)

and decompressor = t
(** Alias for {!t}. *)

val create : ?size_limit:int -> ?dictionary:Dictionary.t -> unit -> t
(** [create ?size_limit ?dictionary ()]

    Creates a new decompressor.

    @param size_limit
      An optional cap on the sliding window size. See also {!set_size_limit}.

    @param dictionary
      An optional dictionary to load into the decompressor context. *)

val set_size_limit : t -> int -> unit
(** [set_size_limit decompressor size]

    Limits the maximum size of the sliding window accepted by the decompressor
    to [size] bytes, protecting against decompression bombs.

    @param size The maximum allowed window size in bytes. *)

val set_dictionary : t -> Dictionary.t -> unit
(** [set_dictionary compressor dictionary]

    Loads the dictionary into the decompressor context. *)

(** {2 Bulk decompression} *)

(** {3 Decompression into buffer}

    Perform explicit decompression with full control over input and output
    buffers. *)

val decompress_bigstring_into :
  in_slice:Slice_bstr.t -> out_slice:Slice_bstr.t -> t -> int
(** [decompress_bigstring_into ~in_slice ~out_slice decompressor]

    Decompresses [in_slice] directly into the pre-allocated [out_slice] buffer.

    Requires manual buffer control, making the user responsible for sizing the
    buffers correctly.

    @param in_slice The compressed input data.
    @param out_slice
      The destination output buffer; it must be large enough to hold the full
      decompressed data.

    @return The number of bytes written to [out_slice]. *)

val decompress_string_into :
  in_slice:Slice_bytes.t -> out_slice:Slice_bytes.t -> t -> int
(** [decompress_string_into ~in_slice ~out_slice decompressor]

    Similar to {!decompress_bigstring_into}, but for [string] type values. *)

(** {3 Single decompression} *)

val decompress_bigstring : t -> Bstr.t -> Bstr.t
(** [decompress_bigstring decompressor bigstring]

    Decompresses the compressed bigstring frame into a newly allocated
    uncompressed bigstring. *)

val decompress_string : t -> string -> string
(** [decompress_string decompressor string]

    Similiar to {!decompress_bigstring}, but for [string] type values. *)

val decompress_channel : decompressor -> in_channel -> out_channel -> unit
(** [decompress_channel decompressor ic oc]

    Decompresses data from an input channel into an output channel.

    @param ic The input channel holding compressed data.
    @param oc The output channel for decompressed data. *)

(** {2 Streaming decompression}

    The streaming API is suitable for unbounded or large data streams where the
    entire input cannot be held in memory at once, or for frames that do not
    store their content size. *)

module Stream : sig
  type t
  (** A streaming decompressor wrapper for incremental data decompression. *)

  val make : decompressor -> t
  (** [make decompressor]

      Creates a new stream context based on the given [decompressor].

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
  (** [decompress_bigstring ~in_slice ~out_slice stream]

      Incrementally decompresses [in_slice] data into the [out_slice] buffer.

      @param in_slice The input compressed buffer.
      @param out_slice The output buffer to write decompressed bytes into.

      @return
        A triple [(~remaining, ~consumed, ~decompressed)] where:
        - [remaining] is the number of bytes of [in_slice] not yet processed,
        - [consumed] is the number of bytes of [in_slice] actually consumed,
        - [decompressed] is the number of bytes written to [out_slice].

      @raise Already_closed if [stream] was closed. *)

  val decompress_string :
    in_slice:Slice_bytes.t ->
    out_slice:Slice_bytes.t ->
    t ->
    (remaining:int * consumed:int * decompressed:int)
  (** [decompress_string ~in_slice ~out_slice stream]

      Similiar to {!decompress_bigstring}, but for [string] type values. *)

  val close : t -> unit
  (** [close stream] closes the [stream].

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
  (** [feed state slice]

      Incrementally decompresses [slice] and returns a slice of the internal
      output buffer containing the decompressed bytes produced during this call.

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
