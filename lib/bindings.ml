(** Low-level bindings to the Zstandard C library. *)

type compression_context = external "ZSTD_CCtx"

and decompression_context = external "ZSTD_DCtx"
(** The low-level Zstandard compression and decompression contexts. *)

external create_compression_context : unit -> compression_context
  = "caml_create_zstd_cctx_s"
(** [create_compression_context ()] creates a new low-level compression context.

    @raise Zstd_error if context creation fails. *)

(** Low-level compression context parameter identifiers. *)
module Compression_context_parameters = struct
  let compression_level = 100
end

external set_compression_context_parameter :
  compression_context -> int -> int -> unit = "caml_create_zstd_set_cctx_param"
(** [set_compression_context_parameter context param value] sets the given
    [param] to [value] on the compression [context].

    @raise Zstd_error if the parameter or value is invalid. *)

external load_compression_dictionary :
  compression_context -> Dictionary.t -> unit = "caml_create_zstd_load_cdict"
(** [load_compression_dictionary context dictionary] loads the [dictionary] into
    the compression [context].

    @raise Zstd_error if dictionary loading fails. *)

external create_decompression_context : unit -> decompression_context
  = "caml_create_zstd_dctx_s"
(** [create_decompression_context ()] creates a new low-level decompression
    context.

    @raise Zstd_error if context creation fails. *)

external set_decompression_context_parameter :
  decompression_context -> int -> int -> unit
  = "caml_create_zstd_set_dctx_param"
(** [set_decompression_context_parameter context param value] sets the given
    [param] to [value] on the decompression [context].

    @raise Zstd_error if the parameter or value is invalid. *)

external load_decompression_dictionary :
  decompression_context -> Dictionary.t -> unit = "caml_create_zstd_load_ddict"
(** [load_decompression_dictionary context dictionary] loads the [dictionary]
    into the decompression [context].

    @raise Zstd_error if dictionary loading fails. *)

type decompression_stream = external "ZSTD_DCtx"
(** A zstd decompression stream.

    In the reference C API, [ZSTD_DStream] is a [typedef] of [ZSTD_DCtx]; this
    binding reflects that by reusing the same phantom type constructor. Values
    of this type are produced by {!Decompressor.unsafe_stream_of_decompressor},
    which reinterprets a {!decompression_context} — the two are structurally
    identical. *)

type dictionary = Dictionary.t
(** A dictionary, as a bigstring. *)

external version : unit -> int = "caml_zstd_version"
(** [version ()] is the numeric version of the linked zstd C library, encoded as
    [major * 10000 + minor * 100 + patch]. *)

external compress_bound : int -> int = "caml_zstd_compress_bound"
(** [compress_bound src_size] is the upper bound on the size of the compressed
    output for a source of [src_size] bytes. *)

external get_frame_content_size_string : string -> int
  = "caml_get_frame_content_size"
(** [get_frame_content_size_string compressed] reads the uncompressed content
    size from the frame header of [compressed].

    @raise Zstd_error
      if [compressed] is not a valid zstd frame, or if the frame does not store
      its content size (as produced by the streaming API). *)

external get_frame_content_size_bigstring : Bstr.t -> int
  = "caml_get_frame_content_size"
(** [get_frame_content_size_bigstring compressed] is the bigstring counterpart
    of {!get_frame_content_size_string}.

    @raise Zstd_error under the same conditions. *)

external get_decompression_stream_out_size : unit -> int
  = "caml_zstd_decompression_stream_out_size"
(** [get_decompression_stream_out_size ()] is [ZSTD_DStreamOutSize]. *)

external get_decompression_stream_in_size : unit -> int
  = "caml_zstd_decompression_stream_in_size"
(** [get_decompression_stream_in_size ()] is [ZSTD_DStreamInSize]. *)

external get_compression_stream_out_size : unit -> int
  = "caml_zstd_compression_stream_out_size"
(** [get_compression_stream_out_size ()] is [ZSTD_CStreamOutSize]. *)

external get_compression_stream_in_size : unit -> int
  = "caml_zstd_compression_stream_in_size"
(** [get_compression_stream_in_size ()] is [ZSTD_CStreamInSize]. *)

external compress2_bigstring :
  compression_context -> Slice_bstr.t -> Slice_bstr.t -> int
  = "caml_zstd_compress2_bigstring"
(** [compress2_bigstring context in_slice out_slice] compresses the Zstandard
    content frame from [in_slice] into the already allocated [out_slice].

    @return The number of compressed bytes written into [out_slice].
    @raise Zstd_error if compression fails or buffer parameters are invalid. *)

external compress2_string :
  compression_context -> Slice_bytes.t -> Slice_bytes.t -> int
  = "caml_zstd_compress2_string"
(** [compress2_string context in_slice out_slice] is the [bytes]-based
    counterpart of {!compress2_bigstring}.

    {b Runtime note.} Unlike the bigstring variant, this call is not wrapped in
    [caml_enter_blocking_section]: [bytes] buffers block the OCaml runtime while
    the C code runs. *)

external decompress_bigstring :
  decompression_context -> Slice_bstr.t -> Slice_bstr.t -> int
  = "caml_zstd_decompress_bigstring"
(** [decompress_bigstring context in_slice out_slice] decompresses the Zstandard
    content frame from [in_slice] into the already allocated [out_slice].

    @return The number of decompressed bytes written into [out_slice].
    @raise Zstd_error if decompression fails or buffer parameters are invalid.
*)

external decompress_string :
  decompression_context -> Slice_bytes.t -> Slice_bytes.t -> int
  = "caml_zstd_decompress_string"
(** [decompress_string context in_slice out_slice] is the [bytes]-based
    counterpart of {!decompress_bigstring}.

    {b Runtime note.} Unlike the bigstring variant, this call is not wrapped in
    [caml_enter_blocking_section]: [bytes] buffers block the OCaml runtime while
    the C code runs. *)

(** [Directive.continue], [Directive.flush] and [Directive.eend] are the flush
    directives for the streaming compressor. *)
module Directive = struct
  let continue = 0
  and flush = 1
  and eend = 2
end

external compress_stream2 :
  compression_context -> Slice_bstr.t -> Slice_bstr.t -> int -> int * int * int
  = "caml_zstd_compress_stream2"
(** [compress_stream2 context in_slice out_slice directive] is
    [ZSTD_compressStream2].

    @return [(remaining, consumed, compressed)].
    @raise Zstd_error if the underlying call reports an error. *)

external compress_stream2_bytes :
  compression_context ->
  Slice_bytes.t ->
  Slice_bytes.t ->
  int ->
  int * int * int = "caml_zstd_compress_stream2_bytes"
(** [compress_stream2_bytes context in_slice out_slice directive] is the
    [bytes]-based counterpart of {!compress_stream2}.

    {b Runtime note.} Unlike the bigstring variant, this call is not wrapped in
    [caml_enter_blocking_section]: [bytes] buffers block the OCaml runtime while
    the C code runs. *)

external decompress_stream :
  decompression_stream -> Slice_bstr.t -> Slice_bstr.t -> int * int * int
  = "caml_zstd_decompress_stream"
(** [decompress_stream stream in_slice out_slice] is [ZSTD_decompressStream].

    @return [(remaining, consumed, decompressed)].
    @raise Zstd_error if the underlying call reports an error. *)

external decompress_stream_bytes :
  decompression_stream -> Slice_bytes.t -> Slice_bytes.t -> int * int * int
  = "caml_zstd_decompress_stream_bytes"
(** [decompress_stream_bytes stream in_slice out_slice] is the [bytes]-based
    counterpart of {!decompress_stream}.

    {b Runtime note.} Unlike the bigstring variant, this call is not wrapped in
    [caml_enter_blocking_section]: [bytes] buffers block the OCaml runtime while
    the C code runs. *)
