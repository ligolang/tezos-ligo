(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

open Alpha_context

module Cost_of : sig
  val manager_operation : Gas.cost

  val baker_operation : Gas.cost

  module Legacy : sig
    val z_to_int64 : Gas.cost

    val hash : bytes -> int -> Gas.cost

    val set_update : 'a -> bool -> 'a Script_typed_ir.set -> Gas.cost
  end

  module Interpreter : sig
    val cycle : Gas.cost

    val loop_cycle : Gas.cost

    val list_map : 'a Script_typed_ir.boxed_list -> Gas.cost

    val list_iter : 'a Script_typed_ir.boxed_list -> Gas.cost

    val set_iter : 'a Script_typed_ir.set -> Gas.cost

    val stack_op : Gas.cost

    val stack_n_op : int -> Gas.cost

    val bool_binop : 'a -> 'b -> Gas.cost

    val bool_unop : 'a -> Gas.cost

    val pair : Gas.cost

    val pair_access : Gas.cost

    val unpair : Gas.cost

    val cons : Gas.cost

    val variant_no_data : Gas.cost

    val branch : Gas.cost

    val concat_string : length:int -> Gas.cost

    val concat_bytes : length:int -> Gas.cost

    val slice_string : int -> Gas.cost

    val map_map : ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_iter : ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_mem : 'a -> ('a, 'b) Script_typed_ir.map -> Gas.cost

    val map_get : 'a -> ('a, 'b) Script_typed_ir.map -> Gas.cost

    val map_update :
      'a -> 'b option -> ('a, 'b) Script_typed_ir.map -> Gas.cost

    val map_size : Gas.cost

    val set_update : 'a -> bool -> 'a Script_typed_ir.set -> Gas.cost

    val set_mem : 'a -> 'a Script_typed_ir.set -> Gas.cost

    val mul : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val div : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val add : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val sub : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val abs : 'a Script_int.num -> Gas.cost

    val neg : 'a Script_int.num -> Gas.cost

    val int : 'a -> Gas.cost

    val add_timestamp : Script_timestamp.t -> 'a Script_int.num -> Gas.cost

    val sub_timestamp : Script_timestamp.t -> 'a Script_int.num -> Gas.cost

    val diff_timestamps : Script_timestamp.t -> Script_timestamp.t -> Gas.cost

    val empty_set : Gas.cost

    val set_size : Gas.cost

    val empty_map : Gas.cost

    val int64_op : Gas.cost

    val z_to_int64 : Gas.cost

    val int64_to_z : Gas.cost

    val logor : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val logand : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val logxor : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val lognot : 'a Script_int.num -> Gas.cost

    val shift_left : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val shift_right : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val exec : Gas.cost

    val push : Gas.cost

    val compare_res : Gas.cost

    val unpack_failed : bytes -> Gas.cost

    val address : Gas.cost

    val contract : Gas.cost

    val transfer : Gas.cost

    val create_account : Gas.cost

    val create_contract : Gas.cost

    val implicit_account : Gas.cost

    val set_delegate : Gas.cost

    val balance : Gas.cost

    val level : Gas.cost

    val now : Gas.cost

    val check_signature : public_key -> bytes -> Gas.cost

    val hash_key : Gas.cost

    val key : Gas.cost

    val hash_blake2b : bytes -> Gas.cost

    val hash_sha256 : bytes -> Gas.cost

    val hash_sha512 : bytes -> Gas.cost

    val steps_to_quota : Gas.cost

    val source : Gas.cost

    val self : Gas.cost

    val amount : Gas.cost

    val chain_id : Gas.cost

    val get_voting_power : Gas.cost

    val get_total_voting_power : Gas.cost

    val hash_keccak : bytes -> Gas.cost

    val hash_sha3 : bytes -> Gas.cost

    val add_bls12_381_g1 : Gas.cost

    val add_bls12_381_g2 : Gas.cost

    val add_bls12_381_fr : Gas.cost

    val mul_bls12_381_g1 : Gas.cost

    val mul_bls12_381_g2 : Gas.cost

    val mul_bls12_381_fr : Gas.cost

    val neg_bls12_381_g1 : Gas.cost

    val neg_bls12_381_g2 : Gas.cost

    val neg_bls12_381_fr : Gas.cost

    val pairing_bls12_381 : Gas.cost

    val mul_bls12_381_fq12 : Gas.cost

    val check_one_bls12_381_fq12 : Gas.cost

    val pairing_check_bls12_381 : int -> Gas.cost

    val wrap : Gas.cost

    val compare : 'a Script_typed_ir.comparable_ty -> 'a -> 'a -> Gas.cost

    val apply : Gas.cost

    val baker_operation : Gas.cost

    val sapling_empty_state : Gas.cost

    val sapling_verify_update : Gas.cost
  end

  module Typechecking : sig
    val cycle : Gas.cost

    val unit : Gas.cost

    val bool : Gas.cost

    val tez : Gas.cost

    val z : Z.t -> Gas.cost

    val string : int -> Gas.cost

    val bytes : int -> Gas.cost

    val int_of_string : string -> Gas.cost

    val string_timestamp : Gas.cost

    val key : Gas.cost

    val key_hash : Gas.cost

    val baker_hash : Gas.cost

    val pvss_key : Gas.cost

    val signature : Gas.cost

    val bls12_381_g1 : Gas.cost

    val bls12_381_g2 : Gas.cost

    val bls12_381_fr : Gas.cost

    val chain_id : Gas.cost

    val contract : Gas.cost

    (** Gas.Cost of getting the code for a contract *)
    val get_script : Gas.cost

    val contract_exists : Gas.cost

    (** Additional Gas.cost of parsing a pair over the Gas.cost of parsing each type  *)
    val pair : Gas.cost

    val union : Gas.cost

    val lambda : Gas.cost

    val some : Gas.cost

    val none : Gas.cost

    val list_element : Gas.cost

    val set_element : int -> Gas.cost

    val map_element : int -> Gas.cost

    val primitive_type : Gas.cost

    val one_arg_type : Gas.cost

    val two_arg_type : Gas.cost

    val operation : int -> Gas.cost

    (** Cost of parsing a type *)
    val type_ : int -> Gas.cost

    (** Cost of parsing an instruction *)
    val instr : ('a, 'b) Script_typed_ir.instr -> Gas.cost
  end

  module Unparse : sig
    val prim_cost : int -> Script.annot -> Gas.cost

    val seq_cost : int -> Gas.cost

    val cycle : Gas.cost

    val unit : Gas.cost

    val bool : Gas.cost

    val z : Z.t -> Gas.cost

    val int : 'a Script_int.num -> Gas.cost

    val tez : Gas.cost

    val string : string -> Gas.cost

    val bytes : bytes -> Gas.cost

    val timestamp : Script_timestamp.t -> Gas.cost

    val key : Gas.cost

    val key_hash : Gas.cost

    val baker_hash : Gas.cost

    val pvss_key : Gas.cost

    val signature : Gas.cost

    val operation : bytes -> Gas.cost

    val chain_id : Gas.cost

    val bls12_381_g1 : Gas.cost

    val bls12_381_g2 : Gas.cost

    val bls12_381_fr : Gas.cost

    val contract : Gas.cost

    (** Additional Gas.cost of parsing a pair over the Gas.cost of parsing each type  *)
    val pair : Gas.cost

    val union : Gas.cost

    val some : Gas.cost

    val none : Gas.cost

    val list_element : Gas.cost

    val set_element : Gas.cost

    val map_element : Gas.cost

    val one_arg_type : Script.annot -> Gas.cost

    val two_arg_type : Script.annot -> Gas.cost

    val sapling_transaction : Sapling.transaction -> Gas.cost

    val sapling_diff : Sapling.diff -> Gas.cost
  end
end
