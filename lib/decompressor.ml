type t = { context : Bindings.decompression_context; mutex : Mutex.t }
and decompressor = t

let set_size_limit decompressor size =
  let log2 x = log x /. log 2.0 |> int_of_float in
  Mutex.protect decompressor.mutex @@ fun () ->
  Bindings.set_decompression_context_parameter decompressor.context 100
  @@ log2 @@ float_of_int size

let set_dictionary decompressor dictionary =
  Mutex.protect decompressor.mutex @@ fun () ->
  Bindings.load_decompression_dictionary decompressor.context dictionary

let create ?size_limit ?dictionary () =
  let decompressor =
    {
      context = Bindings.create_decompression_context ();
      mutex = Mutex.create ();
    }
  in

  Option.iter (set_dictionary decompressor) dictionary;
  Option.iter (set_size_limit decompressor) size_limit;

  decompressor

let unsafe_stream_of_decompressor : t -> Bindings.decompression_stream =
 fun { context; _ } -> Obj.magic context

let decompress_bigstring_into ~in_slice ~out_slice decompressor =
  let _, _, len =
    Mutex.protect decompressor.mutex @@ fun () ->
    Bindings.decompress_stream
      (unsafe_stream_of_decompressor decompressor)
      in_slice out_slice
  in

  len

let decompress_bytes_into ~in_slice ~out_slice decompressor =
  let _, _, len =
    Mutex.protect decompressor.mutex @@ fun () ->
    Bindings.decompress_stream_bytes
      (unsafe_stream_of_decompressor decompressor)
      in_slice out_slice
  in

  len

let decompress_bigstring decompressor compressed =
  let compressed_frame = Frame.of_bigstring compressed in
  let content_size = Frame.uncompressed_size compressed_frame in

  let out_slice = Slice_bstr.create content_size
  and in_slice = Slice_bstr.make compressed in

  let len = decompress_bigstring_into ~in_slice ~out_slice decompressor in
  assert (len = content_size);

  out_slice.buf

let decompress_bytes decompressor compressed =
  let compressed_frame = Frame.of_string compressed in
  let content_size = Frame.uncompressed_size compressed_frame in

  let out_slice = Slice_bytes.create content_size
  and in_slice = Slice_bytes.make (Bytes.unsafe_of_string compressed) in

  let len = decompress_bytes_into ~in_slice ~out_slice decompressor in
  assert (len = content_size);

  Bytes.unsafe_to_string out_slice.buf

module Stream = struct
  type t = { decompressor : decompressor; mutable closed : bool }

  let make decompressor = { decompressor; closed = false }

  let in_size () = Bindings.get_decompression_stream_in_size ()
  and out_size () = Bindings.get_decompression_stream_out_size ()

  exception Already_closed

  let[@inline] decompress_intf ~in_slice ~out_slice stream f =
    if stream.closed then raise Already_closed;

    let remaining, consumed, decompressed =
      Mutex.protect stream.decompressor.mutex @@ fun () ->
      f (unsafe_stream_of_decompressor stream.decompressor) in_slice out_slice
    in

    (~remaining, ~consumed, ~decompressed)

  let decompress_bigstring ~in_slice ~out_slice stream =
    decompress_intf ~in_slice ~out_slice stream Bindings.decompress_stream

  let decompress_bytes ~in_slice ~out_slice stream =
    decompress_intf ~in_slice ~out_slice stream Bindings.decompress_stream_bytes

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

  let feed state slice =
    let rec aux in_slice =
      let out_slice = Slice_bstr.make state.out_buf in

      let ~remaining, ~consumed, ~decompressed =
        Stream.decompress_bigstring ~in_slice ~out_slice state.stream
      in

      let in_slice_len = Slice_bstr.length in_slice in

      if (remaining > 0 || consumed > 0) && consumed < in_slice_len then
        aux
        @@ Slice_bstr.sub ~off:consumed ~len:(in_slice_len - consumed) in_slice
      else Slice_bstr.sub ~off:0 ~len:decompressed out_slice
    in

    aux slice
end

let decompress_channel decompressor ic oc =
  let state = Stream.make decompressor |> State.make in
  let in_buf = Bstr.create @@ Stream.in_size () in

  let rec loop () =
    match In_channel.input_bigarray ic in_buf 0 (Bstr.length in_buf) with
    | 0 -> ()
    | len ->
        let Slice.{ buf; off; len } =
          State.feed state Slice_bstr.(make ~off:0 ~len in_buf)
        in

        Out_channel.output_bigarray oc buf off len;
        loop ()
  in

  loop ();
  Out_channel.flush oc
