open Alcotest

let compress_and_decompress_string source =
  let compressor = Ozstd.Compressor.create () in
  let decompressor = Ozstd.Decompressor.create () in

  Ozstd.Compressor.compress_string compressor source
  |> Ozstd.Decompressor.decompress_string decompressor

module Test_compression = struct
  let test_compress_empty () =
    let source = "" in
    check string "empty string" source (compress_and_decompress_string source)

  let test_compress_small_string () =
    let source = "hello world is very small string for this test" in
    check string "empty string" source (compress_and_decompress_string source)
end

let () =
  run "ozstd"
    [
      ( "compression",
        [
          test_case "compress empty string" `Quick
            Test_compression.test_compress_empty;
          test_case "compress small string" `Quick
            Test_compression.test_compress_small_string;
        ] );
    ]
