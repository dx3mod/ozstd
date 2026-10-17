let compressed_buffer =
  let compressor = Ozstd.Compressor.create () in
  Ozstd.Compressor.compress_bigstring compressor
  @@ Bstr.of_string "hello world peace"

let stream = Ozstd.Decompressor.create () |> Ozstd.Decompressor.Stream.make

let in_slice = Slice_bstr.make compressed_buffer
and out_slice = Slice_bstr.create @@ Ozstd.Decompressor.Stream.out_size ()

let _step =
  Ozstd.Decompressor.Stream.decompress_bigstring ~in_slice ~out_slice stream
