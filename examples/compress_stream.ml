let uncompressed_buffer = Bstr.of_string "hello world peace"
let stream = Ozstd.Compressor.create () |> Ozstd.Compressor.Stream.make

let in_slice = Slice_bstr.make uncompressed_buffer
and out_slice = Slice_bstr.create @@ Ozstd.Decompressor.Stream.out_size ()

let _step =
  Ozstd.Compressor.Stream.compress_bigstring ~in_slice ~out_slice stream `Flush
