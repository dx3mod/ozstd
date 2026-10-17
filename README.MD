<p>
  <img src="https://imagepaste.org/i/fwfn4kpr.png" width="250">
</p>

A thin, idiomatic OCaml bindings to the Facebook's [Zstandard] compression library.

This library does not include all features, but it provides enough for common scenarios,
including one-shot and streaming compression and decompression of strings and bigstring values.

## Getting Started

### Installation

You can install `ozstd` using the [OPAM] package manager or any other preferred method.

```sh
$ opam install ozstd
```

If you are using [Dune], please add `ozstd` to your list of dependencies.

### Usage

To begin using `ozstd`, you don't need to know all the details of Zstandard,
but here are some basic concepts:

- Zstandard has its own compressed data format named a **frame**. A frame is the fundamental, self-contained unit of data produced by Zstandard compression.
- To improve compression quality, you can use dictionaries. Dictionaries can be prepared or unprepared: a prepared (or compiled) dictionary is designed for massive Zstandard data and is used to achieve a smaller size for compression; an unprepared dictionary is a data that does not have a structure but can be used by Zstandard to make some improvements.
- Of course, the compression level is the most important factor for users. The compression level can be set from 1 (the fastest) to 22 (the best ratio). Levels greater than or equal to 20 are considered "ultra" and should be used with caution, as they require more memory.
- And containers that store these settings and memory used during compression/decompression work in specific **contexts**. Context is an extensive object, so you should appreciate it.

Okay, now let's see how it works with some simple examples.

#### One-shot compression and decompression

The most common and simple use case is one-shot data compression or decompression into newly allocated values.

```ocaml
let source = "Contrary to popular belief, Lorem Ipsum is not simply random text."

let compressed =
  (* Create a compression context with a compression level of 3 *)
  let compressor = Ozstd.Compressor.create ~compression_level:3 () in
  (* And compress the source string into a new allocated string. *)
  Ozstd.Compressor.compress_string compressor source

let source' =
  (* Similar to compress, but decompress the compressed string value. *)
  let decompressor = Ozstd.Decompressor.create () in
  Ozstd.Decompressor.decompress_string decompressor compressed

(* Checks that (decompressed source) equals the source. *)
assert (source = source')
```

`compression_level` is a Zstandard quality setting from `1` (fastest) to `22`
(best ratio); `3` is a good default. It can also be changed on an existing
compressor with `Ozstd.Compressor.set_compression_level`.

The library API provides variants for both `string`
and `bigstring` types (indicated by `_string` and `_bigstring` function suffixes).
For example, `compress_string` and `compress_bigstring` functions.

> [!IMPORTANT]
> Please note that operations on string values currently block the OCaml runtime domain,
> whereas operations on bigstring values release the runtime lock
> (allowing execution without blocking the GC/other threads).

#### Reuse compressor and decompressor contexts

for best performance and happy memory management.

Compressors and decompressors hold Zstandard's internal state, are mutex-guarded
(so a single value can be shared across threads), and can carry a dictionary:

```ocaml
let compress_all inputs =
  let compressor = Ozstd.Compressor.create ~dictionary ~compression_level:17 () in
  List.map (Ozstd.Compressor.compress_bigstring compressor) inputs
```

#### Streaming compression and decompression

When working with network streams or large datasets, streaming support becomes essential. In these scenarios, you often cannot wait for all the data to arrive—or more importantly, you cannot fit the entire compressed or uncompressed payload into memory at once. Instead, data must be compressed or decompressed chunk by chunk as it flows through your application.

To support these use cases, Zstandard and the `ozstd` bindings provide both manual buffering and an automated slice-based API.

```ocaml
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
    (fun slice -> Ozstd.Compressor.State.feed state slice `Continue |> output)
    seq;

  Ozstd.Compressor.State.finish state |> output
```

Also, you can provide the buffers yourself and it will report how much work it has done.

```ocaml
let stream =
  let decompressor = Ozstd.Decompressor.create () in
  Ozstd.Decompressor.Stream.make decompressor

let in_slice = Slice_bstr.make compressed_data (* holds a complete Zstandard frame *)
and out_slice = Slice_bstr.create @@ Ozstd.Decompressor.Stream.out_size ()

let (~remaining, ~consumed, ~decompressed) =
  Ozstd.Decompressor.Stream.decompress_bigstring ~in_slice ~out_slice stream
```

The returned tuple reports how many bytes remain in the input, how many bytes were read, and how many bytes were written to the output.

Streaming compression works the same way, but takes an additional `directive` parameter. This parameter controls the stream's flushing behavior.

## Limitations

These bindings cover a large part of the [Zstandard] C API, but not all of it.

**Not covered**

- **Advanced parameters** — only compression `compression_level` and
  decompression `size_limit` are exposed. Tuning knobs, long-distance matching,
  checksums, and content-size flags are not available.
- **Dictionary training** — dictionaries can be used but not created. There is
  no `ZDICT_*` binding.
- **Compiled dictionaries and pledged sizes** — `ZSTD_CDict`, `ZSTD_DDict`,
  `ZSTD_CCtx_setPledgedSrcSize`, and `ZSTD_compress2` are not wrapped. Raw and
  experimental APIs are also missing.
- **Multithreading** — the `ZSTDMT_*` parallel compression API is not bound;
  everything runs single-threaded.

## References

- Early [OCaml bindings](https://github.com/ygrek/ocaml-zstd)
- [Rust binding](https://docs.rs/zstd/latest/zstd/index.html) to the zstd library.

## License

Licensed under [MIT](./LICENSE). Pull requests are welcome.

[Zstandard]: https://github.com/facebook/zstd
[OPAM]: https://opam.ocaml.org/
[Dune]: https://dune.build
