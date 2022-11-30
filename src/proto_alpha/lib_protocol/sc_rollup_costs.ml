(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Trili Tech, <contact@trili.tech>                       *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

module S = Saturation_repr

module Constants = struct
  (* TODO: https://gitlab.com/tezos/tezos/-/issues/2648
     Fill in real benchmarked values.
     Need to create benchmark and fill in values.
  *)
  let cost_add_message_base = S.safe_int 430

  let cost_add_message_per_byte = S.safe_int 15

  let cost_add_inbox_per_level = S.safe_int 15

  let cost_update_num_and_size_of_messages = S.safe_int 15

  (* equal to Michelson_v1_gas.Cost_of.Unparsing.contract_optimized *)
  let cost_decoding_contract_optimized = S.safe_int 70

  (* equal to Michelson_v1_gas.Cost_of.Unparsing.key_hash_optimized *)
  let cost_decoding_key_hash_optimized = S.safe_int 50

  (* Set to the cost of encoding a pkh defined in {!Michelson_v1_gas} divided
     by the number of characters of a pkh, i.e. 70/35. To be updated when
     benchmarking is completed. *)
  let cost_encode_string_per_byte = S.safe_int 2

  (* Cost of serializing a state hash. *)
  let cost_serialize_state_hash =
    let len = S.safe_int State_hash.size in
    S.Syntax.(cost_encode_string_per_byte * len)

  (* Cost of serializing a commitment hash. *)
  let cost_serialize_commitment_hash =
    let len = S.safe_int Sc_rollup_commitment_repr.Hash.size in
    S.Syntax.(cost_encode_string_per_byte * len)

  (* Cost of serializing a commitment. The cost of serializing the level and
     number of ticks (both int32) is negligible. *)
  let cost_serialize_commitment =
    S.Syntax.(cost_serialize_state_hash + cost_serialize_commitment_hash)

  (* Cost of serializing an operation hash. *)
  let cost_serialize_operation_hash =
    let len = S.safe_int Operation_hash.size in
    S.Syntax.(cost_encode_string_per_byte * len)

  (* Cost of serializing a nonce. The cost of serializing the index (an int32)
     is negligible. *)
  let cost_serialize_nonce = cost_serialize_operation_hash

  (* Set to [proof_size_coeff] in {!Tx_rollup_l2_verifier.verify_proof_model}.
     This is an estimate to be updated when benchmarking is completed. *)
  let cost_verify_output_proof_per_byte = S.safe_int 152
end

(* Reusing model from {!Ticket_costs.has_tickets_of_ty_cost}. *)
let is_valid_parameters_ty_cost ~ty_size =
  let fixed_cost = S.safe_int 10 in
  let coeff = S.safe_int 6 in
  S.add fixed_cost (S.mul coeff ty_size)

let cost_serialize_internal_inbox_message
    (internal_inbox_message :
      Sc_rollup_inbox_message_repr.internal_inbox_message) =
  match internal_inbox_message with
  | Transfer {payload; sender = _; source = _; destination = _} ->
      let lexpr = Script_repr.lazy_expr payload in
      let expr_cost = Script_repr.force_bytes_cost lexpr in
      S.Syntax.(
        expr_cost + Constants.cost_decoding_contract_optimized
        + Constants.cost_decoding_key_hash_optimized)
  | Start_of_level -> Saturation_repr.zero
  | End_of_level -> Saturation_repr.zero
  | Info_per_level _ -> Saturation_repr.zero

(** TODO: #3212
    Confirm gas cost model.
    We here assume that the cost of deserializing an expression of [bytes_len]
    is proportional to deserializing a script expression of size [bytes_len].
    This may not be the case and in particular, the cost depends on the specific
    structure used for the PVM. We may thus need to split the cost function.
  *)
let cost_deserialize_output_proof ~bytes_len =
  Script_repr.deserialization_cost_estimated_from_bytes bytes_len

let cost_serialize_external_inbox_message ~bytes_len =
  let len = S.safe_int bytes_len in
  S.Syntax.(Constants.cost_encode_string_per_byte * len)

(* Equal to Michelson_v1_gas.Cost_of.Interpreter.blake2b. *)
let cost_hash_bytes ~bytes_len =
  let open S.Syntax in
  let v0 = S.safe_int bytes_len in
  S.safe_int 430 + v0 + (v0 lsr 3)

let cost_compare a_size_in_bytes b_size_in_bytes =
  let open S.Syntax in
  let size_in_bytes = Compare.Int.min a_size_in_bytes b_size_in_bytes in
  let v0 = S.safe_int size_in_bytes in
  S.safe_int 35 + ((v0 lsr 6) + (v0 lsr 7))

let cost_search_in_tick_list len tick_size =
  let open S.Syntax in
  S.safe_int len * cost_compare tick_size tick_size

let cost_check_dissection ~number_of_states ~tick_size ~hash_size =
  let open S.Syntax in
  cost_search_in_tick_list number_of_states tick_size
  + (S.safe_int 2 * cost_compare hash_size hash_size)

let cost_verify_output_proof ~bytes_len =
  let open S.Syntax in
  Constants.cost_verify_output_proof_per_byte * S.safe_int bytes_len
