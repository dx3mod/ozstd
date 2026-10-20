<p>
  <img src="https://imagepaste.org/i/fwfn4kpr.png" width="250">
</p>

Thin, idiomatic OCaml bindings to Facebook's [Zstandard] compression library.

While it does not cover every feature, it provides robust support for common use cases,
including one-shot and streaming compression and decompression of strings and bigstrings.

## Quick start

You can install `ozstd` using the [OPAM] package manager. It requires OCaml 5.5.0 or later.

```sh
$ opam install ozstd
```

If you are using [Dune], add `ozstd` to your project's dependencies.

### In use

To begin using `ozstd`, you don't need to know all the details of Zstandard, but three basic concepts are key: first, a frame is the compressed data containing both metadata and payload; second, parameters include compression levels (ranging from 1 for speed to 22 for maximum ratio) and dictionaries for better small-data compression; and third, contexts manage the resources used during processing.

Below is an overview of the available library functionality.

#### One-shot compression and decompression 

The most common and simple use case is one-shot data compression or decompression into newly allocated values.

```ocaml
let source = "Contrary to popular belief, Lorem Ipsum is not simply random text."

let compressed_frame =
  (* Create a compression context with a compression level of 3 *)
  let compressor = Ozstd.Compressor.create ~compression_level:3 () in
  (* and compress the source string into a new allocated string. *)
  Ozstd.Compressor.compress_string compressor source

let source' =
  (* Similar to compress, but decompress the compressed string value. *)
  let decompressor = Ozstd.Decompressor.create () in
  Ozstd.Decompressor.decompress_string decompressor compressed_frame

(* Checks that (decompressed source) equals the source. *)
assert (source = source')
```

`compression_level` is a Zstandard quality setting from `1` (fastest) to `22`
(best ratio); `3` is a good default. It can also be changed on an existing
compressor with `Ozstd.Compressor.set_compression_level`.

Also the library provides variants for both `string`
and `bigstring` types (indicated by `_string` and `_bigstring` function suffixes).
For example, `compress_string` and `compress_bigstring` functions.

> [!IMPORTANT]
> Please note that operations on string values currently block the OCaml runtime domain,
> whereas operations on bigstring values release the runtime lock
> (allowing execution without blocking the GC/other threads).

##### Reuse compressor and decompressor contexts for best performance and happy memory management

Compressors and decompressors hold Zstandard's internal state, are mutex-guarded
(so a single value can be shared across threads), and can carry a dictionary:

```ocaml
let compress_all inputs =
  let compressor = Ozstd.Compressor.create ~dictionary ~compression_level:17 () in
  List.map (Ozstd.Compressor.compress_bigstring compressor) inputs
```

#### Streaming compression and decompression

When working with network streams or large datasets, streaming support becomes essential. In these scenarios, you often cannot wait for all the data to arrive or more importantly, you cannot fit the entire compressed or uncompressed payload into memory at once. Instead, data must be compressed or decompressed chunk by chunk as it flows through your application.

To support these use cases, Zstandard and the `ozstd` bindings provide both manual buffering and an automated slice-based API.

Automated slice-based API provides `compress_bigstring_stream` and `decompress_bigstring_stream` functions, driven by a pull and push mechanism, and `State` modules.

```ocaml
let pull () = read_slice source 
and push slice = write_slice destination in 

Ozstd.Compressor.compress_bigstring_stream ~pull ~push compressor
```

However, for manual and automated streaming compression and decompression, you can use the `Stream` and `State` modules.

For more details, see the [API reference](https://ocaml.org/p/ozstd/latest/doc/index.html) and the [`examples/`](./examples/) directory.

<!-- ## Limitations -->

## References

- Early [OCaml bindings](https://github.com/ygrek/ocaml-zstd).
- [Rust binding](https://docs.rs/zstd/latest/zstd/index.html) to the zstd library.

## License

Licensed under [MIT](./LICENSE). Pull requests are welcome.

[Zstandard]: https://github.com/facebook/zstd
[OPAM]: https://opam.ocaml.org/
[Dune]: https://dune.build
