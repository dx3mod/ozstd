<p>
  <img src="https://imagepaste.org/i/fwfn4kpr.png" width="250">
</p>

A small OCaml bindings to [Zstandard], wrapping the reference C API in an idiomatic interface.

**Features**

- One-shot and streaming compression/decompression for strings and bigstrings.
- Reusable, mutex-guarded compressor and decompressor values.
- Low-level `Stream` API for manual buffers, and high-level `State` API for slice
  handling.

## Quick start

Install `ozstd` with [OPAM] or another method. If you use [Dune], add `ozstd` to
your dependencies.

### In use

#### One-shot compression and decompression

```ocaml
let source = "Contrary to popular belief, Lorem Ipsum is not simply random text."

let compressor = Ozstd.Compressor.create ~compression_level:3 ()
let compressed = Ozstd.Compressor.compress_bytes compressor source

let decompressor = Ozstd.Decompressor.create ()
let decompressed = Ozstd.Decompressor.decompress_bytes decompressor compressed
```

`compression_level` is a Zstandard quality setting from `1` (fastest) to `22`
(best ratio); `3` is a good default. It can also be changed on an existing
compressor with `Ozstd.Compressor.set_compression_level`.

Bigstring versions use the same names: `compress_bigstring` and
`decompress_bigstring`. The `*_into` variants (`compress_bigstring_into`,
`compress_bytes_into`, `decompress_bigstring_into`, `decompress_bytes_into`)
write into a preallocated destination buffer and return the number of bytes
written. They are low-level: you are responsible for sizing the buffer
correctly.

Note: streaming compression does not embed the frame content size, so
`decompress_bigstring` / `decompress_bytes`, which read the size from the frame
header, will not work on it. Use the `*_into` variants with a destination large
enough for the decompressed data instead.

#### Reusing a compressor or decompressor

Compressors and decompressors hold Zstandard's internal state, are mutex-guarded
(so a single value can be shared across threads), and can carry a dictionary:

```ocaml
let compress_all dictionary inputs =
  let compressor =
    Ozstd.Compressor.create ~compression_level:3 ~dictionary ()
  in
  List.map (Ozstd.Compressor.compress_bigstring compressor) inputs
```

The same value can be used with the streaming API below.

#### Streaming the `State` API

For data that does not fit in memory or arrives in pieces. Feed it input slices
and emit output slices:

```ocaml
let compress_sequence_into_channel compressor seq oc =
  let stream = Ozstd.Compressor.Stream.make compressor in
  let state = Ozstd.Compressor.State.make stream in

  let rec output Slice.{ buf; off; len } =
    Out_channel.output_bigarray oc buf off len
  and aux slice =
    Ozstd.Compressor.State.feed state slice `Continue |> output
  in

  Seq.iter aux seq;
  Ozstd.Compressor.State.finish state |> output
```

The directive (`` `Continue ``, `` `Flush ``, `` `End ``) controls how much the
stream flushes. `State.finish` emits the last part of the frame.

Decompression uses the same pattern, but `State.feed` takes no directive and
there is no `finish`:

```ocaml
let decompress_sequence_into_channel decompressor seq oc =
  let stream = Ozstd.Decompressor.Stream.make decompressor in
  let state = Ozstd.Decompressor.State.make stream in

  let rec output Slice.{ buf; off; len } =
    Out_channel.output_bigarray oc buf off len
  and aux slice =
    Ozstd.Decompressor.State.feed state slice |> output
  in

  Seq.iter aux seq
```

#### Streaming the `Stream` API

You supply the buffers yourself, and it reports how much work it did:

```ocaml
(* assume [compressed_buffer : Bstr.t] holds a complete zstd frame *)

let decompressor = Ozstd.Decompressor.create ()
let stream = Ozstd.Decompressor.Stream.make decompressor

let in_slice = Slice_bstr.make compressed_buffer
and out_slice = Slice_bstr.create (Ozstd.Decompressor.Stream.out_size ())

let (~remaining, ~consumed, ~decompressed) =
  Ozstd.Decompressor.Stream.decompress_bigstring ~in_slice ~out_slice stream
```

The triple reports bytes remaining in the input, bytes read, and bytes written
to the output. Keep calling it, refilling the input buffer and draining the
output buffer, until all data is processed.
`Ozstd.Compressor.Stream.compress_bigstring` works the same way but takes an
additional directive (`` `Continue ``, `` `Flush ``, `` `End ``) and reports
`~compressed` instead of `~decompressed`.

`Slice_bstr` slices are bigstring-based. If you prefer plain `bytes`, the same
API is available as `Stream.compress_bytes` and `Stream.decompress_bytes`,
which take `Slice_bytes.t` slices with an identical interface.

Note: bigstrings do not block the OCaml runtime while the C binding runs, but
`bytes` and `string` buffers do. Prefer the bigstring (`Slice_bstr`) variants in
multithreaded programs that mix OCaml work with compression.

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