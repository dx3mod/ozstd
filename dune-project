(lang dune 3.6)

(name ozstd)

(version 0.3)

(implicit_transitive_deps false)

(generate_opam_files true)

(source
 (github dx3mod/ozstd))

(authors "Mikhail Lopatin <dx3mod@bk.ru>")

(maintainers "Mikhail Lopatin <dx3mod@bk.ru>")

(license MIT)

(package
 (name ozstd)
 (synopsis "A thin, modern OCaml binding to Zstandard")
 (description
  "A small, modern OCaml binding to Zstandard. It wraps the common one-shot and streaming C APIs in a simple, idiomatic interface")
 (depends
  (ocaml
   (>= 5.5.0))
  dune-configurator
  bstr
  slice
  conf-zstd
  (alcotest :with-test))
 (tags (clib:zstd)))
