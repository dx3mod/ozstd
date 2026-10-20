(lang dune 3.6)

(name ozstd)

(implicit_transitive_deps false)

(generate_opam_files true)

(source
 (github dx3mod/ozstd))

(authors "Mikhail Lopatin <dx3mod@bk.ru>")

(maintainers "Mikhail Lopatin <dx3mod@bk.ru>")

(license MIT)

(package
 (name ozstd)
 (synopsis
  "Thin, idiomatic OCaml bindings to Facebook's Zstandard compression library")
 (depends
  (ocaml
   (>= 5.5.0))
  dune-configurator
  bstr
  (slice
   (>= 0.1.0))
  conf-zstd
  (alcotest :with-test))
 (tags (clib:zstd)))
