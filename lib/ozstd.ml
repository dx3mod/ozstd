(** Zstandard (zstd) compression library.

    Zstandard is a fast, lossless compression algorithm. This library covers the
    reference C bindings with a small, idiomatic OCaml API.

    The library is split into two halves: {!Compressor} for compression and
    {!Decompressor} for decompression, each exposing

    - one-shot functions for data that fits in memory;
    - streaming modules ([Stream] and [State]) for incremental processing. *)

(** {2 Compression and decompression} *)

module Compressor = Compressor
module Decompressor = Decompressor

(** {2 Dictionaries} *)

module Dictionary = Dictionary

(** {2 Version} *)

(** [version ()] is the version of the linked zstd C library as a triple
    [(major, minor, patch)], e.g. [(1, 5, 6)]. *)
let version () =
  let v = Bindings.version () in
  (v / 10_000, v / 100 mod 100, v mod 100)

(** {2 Internals} *)

module Bindings_intf = Bindings
