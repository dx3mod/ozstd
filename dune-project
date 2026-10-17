(lang dune 3.6)

(name ozstd)

(version 0.4)

(implicit_transitive_deps false)

(generate_opam_files true)

(source
 (github dx3mod/ozstd))

(authors "Mikhail Lopatin <dx3mod@bk.ru>")

(maintainers "Mikhail Lopatin <dx3mod@bk.ru>")

(license MIT)

(package
 (name ozstd)
 (synopsis "A small OCaml binding to Zstandard")
 (description
  "A small OCaml bindings to [Zstandard], wrapping the reference C API in an idiomatic interface")
 (depends
  (ocaml
   (>= 5.5.0))
  dune-configurator
  bstr
  slice
  conf-zstd
  (alcotest :with-test))
 (tags (clib:zstd)))
