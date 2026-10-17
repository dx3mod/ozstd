type t = { context : Bindings.compression_context; mutex : Mutex.t }
and compressor = t

let set_compression_level compressor compression_level =
  Mutex.protect compressor.mutex @@ fun () ->
  let open Bindings in
  set_compression_context_parameter compressor.context
    Compression_context_parameters.compression_level compression_level

let set_dictionary compressor dictionary =
  Mutex.protect compressor.mutex @@ fun () ->
  Bindings.load_compression_dictionary compressor.context dictionary

let create ?dictionary ?compression_level () =
  let compressor =
    {
      context = Bindings.create_compression_context ();
      mutex = Mutex.create ();
    }
  in

  Option.iter (set_compression_level compressor) compression_level;
  Option.iter (set_dictionary compressor) dictionary;

  compressor

let compress_bigstring_into ~in_slice ~out_slice compressor =
  let _, _, len =
    Mutex.protect compressor.mutex @@ fun () ->
    Bindings.compress_stream2 compressor.context in_slice out_slice
      Bindings.Directive.eend
  in

  len

let compress_string_into ~in_slice ~out_slice compressor =
  let _, _, len =
    Mutex.protect compressor.mutex @@ fun () ->
    Bindings.compress_stream2_bytes compressor.context in_slice out_slice
      Bindings.Directive.eend
  in

  len

let compress_bigstring compressor uncompressed =
  let in_slice = Slice_bstr.make uncompressed
  and out_slice =
    Bstr.length uncompressed |> Bindings.compress_bound |> Slice_bstr.create
  in

  let len = compress_bigstring_into ~in_slice ~out_slice compressor in
  Bstr.sub ~off:0 ~len out_slice.buf

let compress_string compressor uncompressed =
  let in_slice = Slice_bytes.make (Bytes.unsafe_of_string uncompressed)
  and out_slice =
    String.length uncompressed |> Bindings.compress_bound |> Slice_bytes.create
  in

  let len = compress_string_into ~in_slice ~out_slice compressor in
  Slice_bytes.sub_string ~off:0 ~len out_slice

module Stream = struct
  type nonrec t = { compressor : t; mutable closed : bool }

  let make compressor = { compressor; closed = false }

  let in_size () = Bindings.get_compression_stream_in_size ()
  and out_size () = Bindings.get_compression_stream_out_size ()

  exception Already_closed

  let[@inline] compress_intf ~in_slice ~out_slice
      ({ compressor; closed } as stream) directive f =
    if closed then raise Already_closed;

    let raw_directive =
      match directive with
      | `Continue -> Bindings.Directive.continue
      | `Flush -> Bindings.Directive.flush
      | `End -> Bindings.Directive.eend
    in

    let remaining, consumed, compressed =
      Mutex.protect compressor.mutex @@ fun () ->
      f compressor.context in_slice out_slice raw_directive
    in

    begin match directive with
    | `End when remaining = 0 -> stream.closed <- true
    | `End | `Continue | `Flush -> ()
    end;

    (~remaining, ~consumed, ~compressed)

  let compress_bigstring ~in_slice ~out_slice stream directive =
    compress_intf ~in_slice ~out_slice stream directive
      Bindings.compress_stream2

  let compress_string ~in_slice ~out_slice stream directive =
    compress_intf ~in_slice ~out_slice stream directive
      Bindings.compress_stream2_bytes

  let close stream =
    if stream.closed then raise Already_closed else stream.closed <- true
end

module State = struct
  type t = { stream : Stream.t; out_buf : Bstr.t }

  let make ?out_buf stream =
    {
      stream;
      out_buf =
        (match out_buf with
        | None -> Bstr.create @@ Stream.out_size ()
        | Some out_buf -> out_buf);
    }

  let feed state slice directive =
    let rec aux in_slice =
      let out_slice = Slice_bstr.make state.out_buf in

      let ~remaining, ~consumed, ~compressed =
        Stream.compress_bigstring ~in_slice ~out_slice state.stream directive
      in

      let in_slice_len = Slice_bstr.length in_slice in

      if remaining <> 0 || (consumed > 0 && consumed < in_slice_len) then
        aux
        @@ Slice_bstr.sub ~off:consumed ~len:(in_slice_len - consumed) in_slice
      else Slice_bstr.sub ~off:0 ~len:compressed out_slice
    in

    aux slice

  let finish state = feed state Slice_bstr.empty `End
end

let compress_channel compressor ic oc =
  let state = Stream.make compressor |> State.make in
  let in_buf = Bstr.create @@ Stream.in_size () in

  let output Slice.{ buf; off; len } =
    Out_channel.output_bigarray oc buf off len
  in

  let rec loop () =
    match In_channel.input_bigarray ic in_buf 0 (Bstr.length in_buf) with
    | 0 -> State.finish state |> output
    | len ->
        State.feed state Slice_bstr.(make ~len in_buf) `Continue |> output;
        loop ()
  in

  loop ();
  Out_channel.flush oc
