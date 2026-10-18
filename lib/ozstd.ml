(** Thin, idiomatic OCaml bindings to Facebook's Zstandard compression library,
    providing thread-safe abstractions for both one-shot and streaming
    compression and decompression. *)

module Compressor = Compressor
module Decompressor = Decompressor
module Dictionary = Dictionary
module Frame = Frame
module Zstd_error = Zstd_error
