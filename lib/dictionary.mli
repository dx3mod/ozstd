(** Zstandard compression and decompression dictionary.

    The compression ratio achievable on small data can be significantly improved
    using a dictionary. Dictionaries can be either plain or trained:

    - Plain dictionaries consist of unstructured datasets.
    - Trained (or prepared) dictionaries incorporate a structured dataset
      optimized for Zstandard. *)

type t = private Bstr.t
(** The type for dictionaries, represented as a private bigstring to prevent
    type confusion with regular data bigstrings. *)

val of_bigstring : Bstr.t -> t
(** [of_bigstring bigstring] validates and wraps the given bigstring into a
    dictionary.

    @raise Invalid_argument if the dictionary content is invalid.

    @return A validated dictionary value of type [t]. *)

val of_string : string -> Bstr.t
(** [of_string s] is like {!of_bigstring} but uses [string] values. *)
