#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/custom.h>
#include <caml/bigarray.h>
#include <caml/threads.h>

#include <string.h>
#include <zstd.h>
#include <zstd_errors.h>

/*
 * Some error codes were added after zstd v1.3.1, so they are not available
 * on all versions of the library. Guard each of them with the first zstd
 * release that introduced it:
 *
 *   dstBuffer_wrong              >= v1.4.5
 *   srcBuffer_wrong              >= v1.4.7
 *   literals_headerWrong         >= v1.5.4
 *   parameter_combination...     >= v1.5.4
 *   stabilityCondition...        >= v1.5.4
 *   noForwardProgress_*          >= v1.5.4
 *   sequenceProducer_failed      >= v1.5.4
 *   externalSequences_invalid    >= v1.5.4
 *   cannotProduce_uncompressedBlock >= v1.5.7
 */
#define OZSTD_ZSTD_VERSION_AT_LEAST(M, m, p)                  \
  (ZSTD_VERSION_MAJOR > (M) ||                                \
   (ZSTD_VERSION_MAJOR == (M) && (ZSTD_VERSION_MINOR > (m) || \
                                  (ZSTD_VERSION_MINOR == (m) && ZSTD_VERSION_RELEASE >= (p)))))

////////////////////////////////////////////////////////////////////////
//  ERRORS
////////////////////////////////////////////////////////////////////////

enum
{
  OCAML_ZSTD_NO_ERROR = 0,
  OCAML_ZSTD_GENERIC = 1,
  OCAML_ZSTD_PREFIX_UNKNOWN = 2,
  OCAML_ZSTD_VERSION_UNSUPPORTED = 3,
  OCAML_ZSTD_FRAME_PARAMETER_UNSUPPORTED = 4,
  OCAML_ZSTD_FRAME_PARAMETER_WINDOW_TOO_LARGE = 5,
  OCAML_ZSTD_CORRUPTION_DETECTED = 6,
  OCAML_ZSTD_CHECKSUM_WRONG = 7,
  OCAML_ZSTD_LITERALS_HEADER_WRONG = 8,
  OCAML_ZSTD_DICTIONARY_CORRUPTED = 9,
  OCAML_ZSTD_DICTIONARY_WRONG = 10,
  OCAML_ZSTD_DICTIONARY_CREATION_FAILED = 11,
  OCAML_ZSTD_PARAMETER_UNSUPPORTED = 12,
  OCAML_ZSTD_PARAMETER_COMBINATION_UNSUPPORTED = 13,
  OCAML_ZSTD_PARAMETER_OUT_OF_BOUND = 14,
  OCAML_ZSTD_TABLE_LOG_TOO_LARGE = 15,
  OCAML_ZSTD_MAX_SYMBOL_VALUE_TOO_LARGE = 16,
  OCAML_ZSTD_MAX_SYMBOL_VALUE_TOO_SMALL = 17,
  OCAML_ZSTD_CANNOT_PRODUCE_UNCOMPRESSED_BLOCK = 18,
  OCAML_ZSTD_STABILITY_CONDITION_NOT_RESPECTED = 19,
  OCAML_ZSTD_STAGE_WRONG = 20,
  OCAML_ZSTD_INIT_MISSING = 21,
  OCAML_ZSTD_MEMORY_ALLOCATION = 22,
  OCAML_ZSTD_WORK_SPACE_TOO_SMALL = 23,
  OCAML_ZSTD_DST_SIZE_TOO_SMALL = 24,
  OCAML_ZSTD_SRC_SIZE_WRONG = 25,
  OCAML_ZSTD_DST_BUFFER_NULL = 26,
  OCAML_ZSTD_NO_FORWARD_PROGRESS_DEST_FULL = 27,
  OCAML_ZSTD_NO_FORWARD_PROGRESS_INPUT_EMPTY = 28,
  OCAML_ZSTD_FRAME_INDEX_TOO_LARGE = 29,
  OCAML_ZSTD_SEEKABLE_IO = 30,
  OCAML_ZSTD_DST_BUFFER_WRONG = 31,
  OCAML_ZSTD_SRC_BUFFER_WRONG = 32,
  OCAML_ZSTD_SEQUENCE_PRODUCER_FAILED = 33,
  OCAML_ZSTD_EXTERNAL_SEQUENCES_INVALID = 34,
  OCAML_ZSTD_MAX_CODE = 35
};

static value zstd_error_code_to_ocaml(int code)
{
  int tag;

  switch (code)
  {
  case ZSTD_error_no_error:
    tag = OCAML_ZSTD_NO_ERROR;
    break;
  case ZSTD_error_GENERIC:
    tag = OCAML_ZSTD_GENERIC;
    break;
  case ZSTD_error_prefix_unknown:
    tag = OCAML_ZSTD_PREFIX_UNKNOWN;
    break;
  case ZSTD_error_version_unsupported:
    tag = OCAML_ZSTD_VERSION_UNSUPPORTED;
    break;
  case ZSTD_error_frameParameter_unsupported:
    tag = OCAML_ZSTD_FRAME_PARAMETER_UNSUPPORTED;
    break;
  case ZSTD_error_frameParameter_windowTooLarge:
    tag = OCAML_ZSTD_FRAME_PARAMETER_WINDOW_TOO_LARGE;
    break;
  case ZSTD_error_corruption_detected:
    tag = OCAML_ZSTD_CORRUPTION_DETECTED;
    break;
  case ZSTD_error_checksum_wrong:
    tag = OCAML_ZSTD_CHECKSUM_WRONG;
    break;
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 5, 4)
  case ZSTD_error_literals_headerWrong:
    tag = OCAML_ZSTD_LITERALS_HEADER_WRONG;
    break;
#endif
  case ZSTD_error_dictionary_corrupted:
    tag = OCAML_ZSTD_DICTIONARY_CORRUPTED;
    break;
  case ZSTD_error_dictionary_wrong:
    tag = OCAML_ZSTD_DICTIONARY_WRONG;
    break;
  case ZSTD_error_dictionaryCreation_failed:
    tag = OCAML_ZSTD_DICTIONARY_CREATION_FAILED;
    break;
  case ZSTD_error_parameter_unsupported:
    tag = OCAML_ZSTD_PARAMETER_UNSUPPORTED;
    break;
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 5, 4)
  case ZSTD_error_parameter_combination_unsupported:
    tag = OCAML_ZSTD_PARAMETER_COMBINATION_UNSUPPORTED;
    break;
#endif
  case ZSTD_error_parameter_outOfBound:
    tag = OCAML_ZSTD_PARAMETER_OUT_OF_BOUND;
    break;
  case ZSTD_error_tableLog_tooLarge:
    tag = OCAML_ZSTD_TABLE_LOG_TOO_LARGE;
    break;
  case ZSTD_error_maxSymbolValue_tooLarge:
    tag = OCAML_ZSTD_MAX_SYMBOL_VALUE_TOO_LARGE;
    break;
  case ZSTD_error_maxSymbolValue_tooSmall:
    tag = OCAML_ZSTD_MAX_SYMBOL_VALUE_TOO_SMALL;
    break;
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 5, 7)
  case ZSTD_error_cannotProduce_uncompressedBlock:
    tag = OCAML_ZSTD_CANNOT_PRODUCE_UNCOMPRESSED_BLOCK;
    break;
#endif
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 5, 4)
  case ZSTD_error_stabilityCondition_notRespected:
    tag = OCAML_ZSTD_STABILITY_CONDITION_NOT_RESPECTED;
    break;
#endif
  case ZSTD_error_stage_wrong:
    tag = OCAML_ZSTD_STAGE_WRONG;
    break;
  case ZSTD_error_init_missing:
    tag = OCAML_ZSTD_INIT_MISSING;
    break;
  case ZSTD_error_memory_allocation:
    tag = OCAML_ZSTD_MEMORY_ALLOCATION;
    break;
  case ZSTD_error_workSpace_tooSmall:
    tag = OCAML_ZSTD_WORK_SPACE_TOO_SMALL;
    break;
  case ZSTD_error_dstSize_tooSmall:
    tag = OCAML_ZSTD_DST_SIZE_TOO_SMALL;
    break;
  case ZSTD_error_srcSize_wrong:
    tag = OCAML_ZSTD_SRC_SIZE_WRONG;
    break;
  case ZSTD_error_dstBuffer_null:
    tag = OCAML_ZSTD_DST_BUFFER_NULL;
    break;
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 5, 4)
  case ZSTD_error_noForwardProgress_destFull:
    tag = OCAML_ZSTD_NO_FORWARD_PROGRESS_DEST_FULL;
    break;
  case ZSTD_error_noForwardProgress_inputEmpty:
    tag = OCAML_ZSTD_NO_FORWARD_PROGRESS_INPUT_EMPTY;
    break;
#endif
  case ZSTD_error_frameIndex_tooLarge:
    tag = OCAML_ZSTD_FRAME_INDEX_TOO_LARGE;
    break;
  case ZSTD_error_seekableIO:
    tag = OCAML_ZSTD_SEEKABLE_IO;
    break;
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 4, 5)
  case ZSTD_error_dstBuffer_wrong:
    tag = OCAML_ZSTD_DST_BUFFER_WRONG;
    break;
#endif
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 4, 7)
  case ZSTD_error_srcBuffer_wrong:
    tag = OCAML_ZSTD_SRC_BUFFER_WRONG;
    break;
#endif
#if OZSTD_ZSTD_VERSION_AT_LEAST(1, 5, 4)
  case ZSTD_error_sequenceProducer_failed:
    tag = OCAML_ZSTD_SEQUENCE_PRODUCER_FAILED;
    break;
  case ZSTD_error_externalSequences_invalid:
    tag = OCAML_ZSTD_EXTERNAL_SEQUENCES_INVALID;
    break;
#endif
  case ZSTD_error_maxCode:
    tag = OCAML_ZSTD_MAX_CODE;
    break;
  default:
    /* Unknown error code – map to Generic as a safe fallback. */
    tag = OCAML_ZSTD_GENERIC;
    break;
  }

  return Val_int(tag);
}

CAMLnoret static void raise_zstd_error(const int error_code, const char *fn_name, const char *message)
{
  CAMLparam0();
  CAMLlocalN(args, 3);

  const value *exn = caml_named_value("ozstd_zstd_error");

  if (exn == NULL)
    caml_failwith(message);

  args[0] = zstd_error_code_to_ocaml(error_code);
  args[1] = caml_copy_string(fn_name);
  args[2] = caml_copy_string(message);

  caml_raise_with_args(*exn, 3, args);

  CAMLnoreturn;
}

static void check_on_zstd_error(size_t result, const char *fn_name, const char *msg)
{
  if (ZSTD_isError(result))
    raise_zstd_error(
        ZSTD_getErrorCode(result),
        fn_name,
        msg == NULL ? ZSTD_getErrorName(result) : msg);
}

////////////////////////////////////////////////////////////////////////
//  CONTEXTS
////////////////////////////////////////////////////////////////////////

void custom_finalize_zstd_cctx_ops(value);

static struct custom_operations zstd_cctx_ops = {
    "zstd.CCtx_s",
    custom_finalize_zstd_cctx_ops,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default};

#define Zstd_cctx_val(v) (*((ZSTD_CCtx **)Data_custom_val(v)))

void custom_finalize_zstd_cctx_ops(value cctx)
{
  ZSTD_freeCCtx(Zstd_cctx_val(cctx));
}

CAMLprim value caml_create_zstd_cctx_s(value unit)
{
  CAMLparam1(unit);
  CAMLlocal1(cctx_val);

  cctx_val = caml_alloc_custom(&zstd_cctx_ops, sizeof(ZSTD_CCtx *), 0, 1);
  Zstd_cctx_val(cctx_val) = NULL;

  ZSTD_CCtx *cctx = ZSTD_createCCtx();

  if (cctx == NULL)
    raise_zstd_error(-1, "ZSTD_createCCtx", "NULL");

  Zstd_cctx_val(cctx_val) = cctx;

  CAMLreturn(cctx_val);
}

CAMLprim value caml_create_zstd_set_cctx_param(value context, value param_kind, value param_value)
{
  CAMLparam3(context, param_kind, param_value);
  ZSTD_CCtx_setParameter(Zstd_cctx_val(context), Int_val(param_kind), Long_val(param_value));
  CAMLreturn(Val_unit);
}

void custom_finalize_zstd_dctx_ops(value);

static struct custom_operations zstd_dctx_ops = {
    "zstd.DCtx_s",
    custom_finalize_zstd_dctx_ops,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default};

#define Zstd_dctx_val(v) (*((ZSTD_DCtx **)Data_custom_val(v)))

void custom_finalize_zstd_dctx_ops(value dctx)
{
  ZSTD_freeDCtx(Zstd_dctx_val(dctx));
}

CAMLprim value caml_create_zstd_dctx_s(value unit)
{
  CAMLparam1(unit);
  CAMLlocal1(dctx_val);

  dctx_val = caml_alloc_custom(&zstd_dctx_ops, sizeof(ZSTD_DCtx *), 0, 1);
  Zstd_dctx_val(dctx_val) = NULL;

  ZSTD_DCtx *dctx = ZSTD_createDCtx();

  if (dctx == NULL)
    raise_zstd_error(-1, "ZSTD_createDCtx", "NULL");

  Zstd_dctx_val(dctx_val) = dctx;

  CAMLreturn(dctx_val);
}

CAMLprim value caml_create_zstd_set_dctx_param(value context, value param_kind, value param_value)
{
  CAMLparam3(context, param_kind, param_value);
  ZSTD_DCtx_setParameter(Zstd_dctx_val(context), Int_val(param_kind), Long_val(param_value));
  CAMLreturn(Val_unit);
}

////////////////////////////////////////////////////////////////////////
//  DICTIONARIES
////////////////////////////////////////////////////////////////////////

CAMLprim value caml_create_zstd_load_cdict(value context, value dictionary)
{
  CAMLparam2(context, dictionary);

  const size_t result = ZSTD_CCtx_loadDictionary(Zstd_cctx_val(context),
                                                 Caml_ba_data_val(dictionary),
                                                 Caml_ba_array_val(dictionary)->dim[0]);

  check_on_zstd_error(result, "ZSTD_CCtx_loadDictionary", NULL);

  CAMLreturn(Val_unit);
}

CAMLprim value caml_create_zstd_load_ddict(value context, value dictionary)
{
  CAMLparam2(context, dictionary);

  const size_t result = ZSTD_DCtx_loadDictionary(Zstd_dctx_val(context),
                                                 Caml_ba_data_val(dictionary),
                                                 Caml_ba_array_val(dictionary)->dim[0]);

  check_on_zstd_error(result, "ZSTD_DCtx_loadDictionary", NULL);

  CAMLreturn(Val_unit);
}

////////////////////////////////////////////////////////////////////////
//  MISC
////////////////////////////////////////////////////////////////////////

CAMLprim value caml_zstd_version(value unit)
{
  return Val_int(ZSTD_VERSION_NUMBER);
}

CAMLprim value caml_zstd_compress_bound(value src_size)
{
  CAMLparam1(src_size);
  CAMLreturn(Val_long(ZSTD_COMPRESSBOUND(Long_val(src_size))));
}

CAMLprim value caml_get_frame_content_size(value compressed)
{
  CAMLparam1(compressed);

  char const *data;
  size_t data_size;

  if (Tag_val(compressed) == String_tag)
  {
    data = String_val(compressed);
    data_size = caml_string_length(compressed);
  }
  else if (Tag_val(compressed) == Custom_tag)
  {
    data = Caml_ba_data_val(compressed);
    data_size = Caml_ba_array_val(compressed)->dim[0];
  }
  else
    caml_failwith("impossible state");

  const size_t result = ZSTD_getFrameContentSize(data, data_size);

  if (result == ZSTD_CONTENTSIZE_ERROR)
    raise_zstd_error(-1, "ZSTD_getFrameContentSize", "corrupt frame");

  if (result == ZSTD_CONTENTSIZE_UNKNOWN)
    raise_zstd_error(-1, "ZSTD_getFrameContentSize", "frame does not carry its content size");

  CAMLreturn(Val_long(result));
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// STREAM COMPRESS
/////////////////////////////////////////////////////////////////////////////////////////////////////////

#define Slice_data_val(V) Caml_ba_data_val(Field(V, 0))
#define Slice_bytes_val(V) Bytes_val(Field(V, 0))

#define Slice_offset_val(V) Long_val(Field(V, 1))
#define Slice_length_val(V) Long_val(Field(V, 2))

#define Slice_size_val(V) (Slice_offset_val(V) + Slice_length_val(V))

static void initialize_compression_result_tuple(value tup, size_t remaining, size_t input_position, size_t output_position)
{
  Store_field(tup, 0, Val_long(remaining));
  Store_field(tup, 1, Val_long(input_position));
  Store_field(tup, 2, Val_long(output_position));
}

CAMLprim value caml_zstd_compress_stream2(value context, value in_slice, value out_slice, value directive)
{
  CAMLparam4(context, in_slice, out_slice, directive);
  CAMLlocal1(tup);

  ZSTD_inBuffer input = {
      .src = Slice_data_val(in_slice),
      .size = Slice_size_val(in_slice),
      .pos = Slice_offset_val(in_slice)};

  ZSTD_outBuffer output = {
      .dst = Slice_data_val(out_slice),
      .size = Slice_size_val(out_slice),
      .pos = Slice_offset_val(out_slice)};

  ZSTD_CCtx *const cctx = Zstd_cctx_val(context);
  const int dir = Int_val(directive);

  caml_enter_blocking_section();
  const size_t remaining = ZSTD_compressStream2(cctx, &output, &input, dir);
  caml_leave_blocking_section();

  check_on_zstd_error(remaining, "ZSTD_compressStream2", NULL);

  tup = caml_alloc_tuple(3);
  initialize_compression_result_tuple(tup, remaining, input.pos, output.pos);

  CAMLreturn(tup);
}

CAMLprim value caml_zstd_compress_stream2_bytes(value context, value in_slice, value out_slice, value directive)
{
  CAMLparam4(context, in_slice, out_slice, directive);
  CAMLlocal1(tup);

  ZSTD_inBuffer input = {
      .src = Slice_bytes_val(in_slice),
      .size = Slice_size_val(in_slice),
      .pos = Slice_offset_val(in_slice)};

  ZSTD_outBuffer output = {
      .dst = Slice_bytes_val(out_slice),
      .size = Slice_size_val(out_slice),
      .pos = Slice_offset_val(out_slice)};

  const size_t remaining = ZSTD_compressStream2(Zstd_cctx_val(context), &output, &input, Int_val(directive));

  check_on_zstd_error(remaining, "ZSTD_compressStream2", NULL);

  tup = caml_alloc_tuple(3);
  initialize_compression_result_tuple(tup, remaining, input.pos, output.pos);

  CAMLreturn(tup);
}

CAMLprim value caml_zstd_compression_stream_in_size(value unit)
{
  return Val_long(ZSTD_CStreamInSize());
}

CAMLprim value caml_zstd_compression_stream_out_size(value unit)
{
  return Val_long(ZSTD_CStreamOutSize());
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// STREAM DECOMPRESS
/////////////////////////////////////////////////////////////////////////////////////////////////////////

/*
 * The value passed to the decompression-stream stubs is created with
 * [zstd_dctx_ops] (see [Decompressor.unsafe_stream_of_decompressor]); since
 * [ZSTD_DStream] is a typedef of [ZSTD_DCtx] and the custom block layout is
 * the same, reading it as [ZSTD_DStream *] is safe.
 */
#define Zstd_dstream_val(v) (*((ZSTD_DStream **)Data_custom_val(v)))

CAMLprim value caml_zstd_decompress_stream(value dstream, value in_slice, value out_slice)
{
  CAMLparam3(dstream, in_slice, out_slice);
  CAMLlocal1(tup);

  ZSTD_inBuffer input = {
      .src = Slice_data_val(in_slice),
      .size = Slice_size_val(in_slice),
      .pos = Slice_offset_val(in_slice)};

  ZSTD_outBuffer output = {
      .dst = Slice_data_val(out_slice),
      .size = Slice_size_val(out_slice),
      .pos = Slice_offset_val(out_slice)};

  ZSTD_DStream *const stream = Zstd_dstream_val(dstream);

  caml_enter_blocking_section();
  const size_t remaining = ZSTD_decompressStream(stream, &output, &input);
  caml_leave_blocking_section();

  check_on_zstd_error(remaining, "ZSTD_decompressStream", NULL);

  tup = caml_alloc_tuple(3);
  initialize_compression_result_tuple(tup, remaining, input.pos, output.pos);

  CAMLreturn(tup);
}

CAMLprim value caml_zstd_decompress_stream_bytes(value dstream, value in_slice, value out_slice)
{
  CAMLparam3(dstream, in_slice, out_slice);
  CAMLlocal1(tup);

  ZSTD_inBuffer input = {
      .src = Slice_bytes_val(in_slice),
      .size = Slice_size_val(in_slice),
      .pos = Slice_offset_val(in_slice)};

  ZSTD_outBuffer output = {
      .dst = Slice_bytes_val(out_slice),
      .size = Slice_size_val(out_slice),
      .pos = Slice_offset_val(out_slice)};

  const size_t remaining = ZSTD_decompressStream(Zstd_dstream_val(dstream), &output, &input);

  check_on_zstd_error(remaining, "ZSTD_decompressStream", NULL);

  tup = caml_alloc_tuple(3);
  initialize_compression_result_tuple(tup, remaining, input.pos, output.pos);

  CAMLreturn(tup);
}

CAMLprim value caml_zstd_decompression_stream_in_size(value unit)
{
  return Val_long(ZSTD_DStreamInSize());
}

CAMLprim value caml_zstd_decompression_stream_out_size(value unit)
{
  return Val_long(ZSTD_DStreamOutSize());
}