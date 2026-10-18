(** Zstandard compression and decompression errors. *)

(** The type for Zstandard error codes. *)
type error_code =
  | Generic (* *)
  | Prefix_unknown
  | Version_unsupported
  | Frame_parameter_unsupported
  | Frame_parameter_window_too_large
  | Corruption_detected
  | Checksum_wrong
  | Literals_header_wrong
  | Dictionary_corrupted
  | Dictionary_wrong
  | Dictionary_creation_failed
  | Parameter_unsupported
  | Parameter_combination_unsupported
  | Parameter_out_of_bound
  | Table_log_too_large
  | Max_symbol_value_too_large
  | Max_symbol_value_too_small
  | Cannot_produce_uncompressed_block
  | Stability_condition_not_respected
  | Stage_wrong
  | Init_missing
  | Memory_allocation
  | Work_space_too_small
  | Destination_size_too_small
  | Src_size_wrong
  | Destination_buffer_null
  | No_forward_progress_dest_full
  | No_forward_progress_input_empty
  | Frame_index_too_large
  | Seekable_io
  | Destination_buffer_wrong
  | Src_buffer_wrong
  | Sequence_producer_failed
  | External_sequences_invalid
  | Max_code
  | Corrupt_frame

exception Zstd_error of error_code * string * string
(** Raised when a Zstandard operation fails. The payload contains the error
    code, the name of the C function that reported the error, and a descriptive
    error message. *)
