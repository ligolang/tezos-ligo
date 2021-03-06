(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2019-2020 Nomadic Labs <contact@nomadic-labs.com>           *)
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
open Gas

module Cost_of = struct
  let log2 =
    let rec help acc = function 0 -> acc | n -> help (acc + 1) (n / 2) in
    help 1

  let z_bytes (z : Z.t) =
    let bits = Z.numbits z in
    (7 + bits) / 8

  let int_bytes (z : 'a Script_int.num) = z_bytes (Script_int.to_zint z)

  let timestamp_bytes (t : Script_timestamp.t) =
    let z = Script_timestamp.to_zint t in
    z_bytes z

  (* Upper-bound on the time to compare the given value.
     For now, returns size in bytes, but this could get more complicated... *)
  let rec size_of_comparable :
      type a. a Script_typed_ir.comparable_ty -> a -> int =
   fun wit v ->
    match (wit, v) with
    | (Unit_key _, _) ->
        1
    | (Never_key _, _) ->
        .
    | (Int_key _, _) ->
        int_bytes v
    | (Nat_key _, _) ->
        int_bytes v
    | (Signature_key _, _) ->
        Signature.size
    | (String_key _, _) ->
        String.length v
    | (Bytes_key _, _) ->
        Bytes.length v
    | (Bool_key _, _) ->
        1
    | (Key_hash_key _, _) ->
        Signature.Public_key_hash.size
    | (Key_key _, k) ->
        Signature.Public_key.size k
    | (Timestamp_key _, _) ->
        timestamp_bytes v
    | (Baker_hash_key _, _) ->
        Baker_hash.size
    | (Pvss_key _, _) ->
        Pvss_secp256k1.Public_key.size
    | (Address_key _, _) ->
        Signature.Public_key_hash.size
    | (Mutez_key _, _) ->
        8
    | (Chain_id_key _, _) ->
        Chain_id.size
    | (Pair_key ((l, _), (r, _), _), (lval, rval)) ->
        size_of_comparable l lval + size_of_comparable r rval
    | (Union_key ((t, _), _, _), L x) ->
        1 + size_of_comparable t x
    | (Union_key (_, (t, _), _), R x) ->
        1 + size_of_comparable t x
    | (Option_key _, None) ->
        1
    | (Option_key (t, _), Some x) ->
        1 + size_of_comparable t x

  let string length = alloc_bytes_cost length

  let bytes length = alloc_mbytes_cost length

  let manager_operation = step_cost 10_000

  let baker_operation = manager_operation

  module Legacy = struct
    let zint z = alloc_bits_cost (Z.numbits z)

    let z_to_int64 = step_cost 2 +@ alloc_cost 1

    let hash data len = (10 *@ step_cost (Bytes.length data)) +@ bytes len

    let set_access : type elt. elt -> elt Script_typed_ir.set -> int =
     fun _key (module Box) -> log2 @@ Box.size

    let set_update key _presence set = set_access key set *@ alloc_cost 3
  end

  module Interpreter = struct
    let cycle = atomic_step_cost 10

    let stack_op = atomic_step_cost 10

    let push = atomic_step_cost 10

    let wrap = atomic_step_cost 10

    let variant_no_data = atomic_step_cost 10

    let branch = atomic_step_cost 10

    let pair = atomic_step_cost 10

    let pair_access = atomic_step_cost 10

    let unpair = atomic_step_cost 20

    let cons = atomic_step_cost 10

    let loop_cycle = atomic_step_cost 10

    let list_map (l : 'a Script_typed_ir.boxed_list) =
      atomic_step_cost (30 + (l.length * 30))

    let list_iter (l : 'a Script_typed_ir.boxed_list) =
      atomic_step_cost (20 + (l.length * 20))

    let empty_set = atomic_step_cost 10

    let set_iter : type elt. elt Script_typed_ir.set -> cost =
     fun (module Box) -> atomic_step_cost (20 + (Box.size * 20))

    let set_mem : type elt. elt -> elt Script_typed_ir.set -> cost =
     fun elt (module Box) ->
      let elt_bytes = size_of_comparable Box.elt_ty elt in
      atomic_step_cost ((1 + (elt_bytes / 82)) * log2 Box.size)

    let set_update : type elt. elt -> bool -> elt Script_typed_ir.set -> cost =
     fun elt _ (module Box) ->
      let elt_bytes = size_of_comparable Box.elt_ty elt in
      atomic_step_cost ((1 + (elt_bytes / 82)) * log2 Box.size)

    let set_size = atomic_step_cost 10

    let empty_map = atomic_step_cost 10

    let map_map : type key value. (key, value) Script_typed_ir.map -> cost =
     fun (module Box) ->
      let size = snd Box.boxed in
      atomic_step_cost (30 + (size * 30))

    let map_iter : type key value. (key, value) Script_typed_ir.map -> cost =
     fun (module Box) ->
      let size = snd Box.boxed in
      atomic_step_cost (20 + (size * 20))

    let map_access :
        type key value. key -> (key, value) Script_typed_ir.map -> cost =
     fun key (module Box) ->
      let map_card = snd Box.boxed in
      let key_bytes = size_of_comparable Box.key_ty key in
      atomic_step_cost ((1 + (key_bytes / 70)) * log2 map_card)

    let map_mem = map_access

    let map_get = map_access

    let map_update :
        type key value.
        key -> value option -> (key, value) Script_typed_ir.map -> cost =
     fun key _value (module Box) ->
      let map_card = snd Box.boxed in
      let key_bytes = size_of_comparable Box.key_ty key in
      atomic_step_cost ((1 + (key_bytes / 38)) * log2 map_card)

    let map_size = atomic_step_cost 10

    let add_timestamp (t1 : Script_timestamp.t) (t2 : 'a Script_int.num) =
      let bytes1 = timestamp_bytes t1 in
      let bytes2 = int_bytes t2 in
      atomic_step_cost (51 + (Compare.Int.max bytes1 bytes2 / 62))

    let sub_timestamp = add_timestamp

    let diff_timestamps (t1 : Script_timestamp.t) (t2 : Script_timestamp.t) =
      let bytes1 = timestamp_bytes t1 in
      let bytes2 = timestamp_bytes t2 in
      atomic_step_cost (51 + (Compare.Int.max bytes1 bytes2 / 62))

    let concat_string ~length:string_list_length =
      atomic_step_cost (30 + (string_list_length * 30))

    let slice_string string_length =
      atomic_step_cost (40 + (string_length / 70))

    let concat_bytes ~length:bytes_list_length =
      atomic_step_cost (30 + (bytes_list_length * 30))

    let int64_op = atomic_step_cost 61

    let z_to_int64 = atomic_step_cost 20

    let int64_to_z = atomic_step_cost 20

    let bool_binop _ _ = atomic_step_cost 10

    let bool_unop _ = atomic_step_cost 10

    let abs int = atomic_step_cost (61 + (int_bytes int / 70))

    let int _int = free

    let neg = abs

    let add i1 i2 =
      atomic_step_cost
        (51 + (Compare.Int.max (int_bytes i1) (int_bytes i2) / 62))

    let sub = add

    let mul i1 i2 =
      let bytes = Compare.Int.max (int_bytes i1) (int_bytes i2) in
      atomic_step_cost (51 + (bytes / 6 * log2 bytes))

    let indic_lt x y = if Compare.Int.(x < y) then 1 else 0

    let div i1 i2 =
      let bytes1 = int_bytes i1 in
      let bytes2 = int_bytes i2 in
      let cost = indic_lt bytes2 bytes1 * (bytes1 - bytes2) * bytes2 in
      atomic_step_cost (51 + (cost / 3151))

    let compare_unit = atomic_step_cost 10

    let shift_left _i _shift_bits = atomic_step_cost 30

    let shift_right _i _shift_bits = atomic_step_cost 30

    let logor i1 i2 =
      let bytes1 = int_bytes i1 in
      let bytes2 = int_bytes i2 in
      atomic_step_cost (51 + (Compare.Int.max bytes1 bytes2 / 70))

    let logand i1 i2 =
      let bytes1 = int_bytes i1 in
      let bytes2 = int_bytes i2 in
      atomic_step_cost (51 + (Compare.Int.min bytes1 bytes2 / 70))

    let logxor = logor

    let lognot i = atomic_step_cost (51 + (int_bytes i / 20))

    let exec = atomic_step_cost 10

    let compare_bool = atomic_step_cost 30

    let compare_option_tag = atomic_step_cost 35

    let compare_union_tag = atomic_step_cost 40

    let compare_signature _ _ = atomic_step_cost 92

    let compare_string s1 s2 =
      let bytes1 = String.length s1 in
      let bytes2 = String.length s2 in
      atomic_step_cost (30 + (Compare.Int.min bytes1 bytes2 / 123))

    let compare_bytes b1 b2 =
      let bytes1 = Bytes.length b1 in
      let bytes2 = Bytes.length b2 in
      atomic_step_cost (30 + (Compare.Int.min bytes1 bytes2 / 123))

    let compare_tez _ _ = atomic_step_cost 30

    let compare_zint i1 i2 =
      atomic_step_cost
        (51 + (Compare.Int.min (int_bytes i1) (int_bytes i2) / 82))

    let compare_key_hash _ _ = atomic_step_cost 92

    let compare_key _ _ = atomic_step_cost 92

    let compare_baker_hash _ _ = atomic_step_cost 92

    let compare_pvss_key _ _ = atomic_step_cost 92

    let compare_timestamp t1 t2 =
      let bytes1 = timestamp_bytes t1 in
      let bytes2 = timestamp_bytes t2 in
      atomic_step_cost (51 + (Compare.Int.min bytes1 bytes2 / 82))

    let compare_address _ _ = atomic_step_cost 92

    let compare_chain_id _ _ = atomic_step_cost 30

    let compare_res = atomic_step_cost 30

    let unpack_failed bytes =
      (* We cannot instrument failed deserialization,
         so we take worst case fees: a set of size 1 bytes values. *)
      let len = Bytes.length bytes in
      (len *@ alloc_mbytes_cost 1)
      +@ (len *@ (log2 len *@ (alloc_cost 3 +@ step_cost 1)))

    let address = atomic_step_cost 10

    let contract = step_cost 10000

    let transfer = step_cost 10

    let create_account = step_cost 10

    let create_contract = step_cost 10

    let implicit_account = step_cost 10

    let set_delegate = step_cost 10

    let balance = atomic_step_cost 10

    let now = atomic_step_cost 10

    let check_signature_secp256k1 bytes = atomic_step_cost (10342 + (bytes / 5))

    let check_signature_ed25519 bytes = atomic_step_cost (36864 + (bytes / 5))

    let check_signature_p256 bytes = atomic_step_cost (36864 + (bytes / 5))

    let check_signature (pkey : Signature.public_key) bytes =
      match pkey with
      | Ed25519 _ ->
          check_signature_ed25519 (Bytes.length bytes)
      | Secp256k1 _ ->
          check_signature_secp256k1 (Bytes.length bytes)
      | P256 _ ->
          check_signature_p256 (Bytes.length bytes)

    let hash_key = atomic_step_cost 30

    let key = atomic_step_cost 30

    let hash_blake2b b = atomic_step_cost (102 + (Bytes.length b / 5))

    let hash_sha256 b = atomic_step_cost (409 + Bytes.length b)

    let hash_sha512 b =
      let bytes = Bytes.length b in
      atomic_step_cost (409 + ((bytes lsr 1) + (bytes lsr 4)))

    let hash_keccak b =
      (* TODO: assign gas price *)
      atomic_step_cost (10 + Bytes.length b)

    let hash_sha3 b =
      (* TODO: assign gas price *)
      atomic_step_cost (10 + Bytes.length b)

    let steps_to_quota = atomic_step_cost 10

    let source = atomic_step_cost 10

    let self = atomic_step_cost 10

    let amount = atomic_step_cost 10

    let level = step_cost 2

    let chain_id = step_cost 1

    let get_voting_power = step_cost 1

    let get_total_voting_power = step_cost 1

    let add_bls12_381_g1 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let add_bls12_381_g2 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let add_bls12_381_fr =
      (* TODO: Review this *)
      atomic_step_cost 10

    let mul_bls12_381_g1 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let mul_bls12_381_g2 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let mul_bls12_381_fr =
      (* TODO: Review this *)
      atomic_step_cost 10

    let neg_bls12_381_g1 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let neg_bls12_381_g2 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let neg_bls12_381_fr =
      (* TODO: Review this *)
      atomic_step_cost 10

    let pairing_bls12_381 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let mul_bls12_381_fq12 =
      (* TODO: Review this *)
      atomic_step_cost 10

    let check_one_bls12_381_fq12 =
      (* TODO: Review this *)
      atomic_step_cost 10

    (* Pairing check on a list of `n` pairs *)
    let pairing_check_bls12_381 n =
      (n *@ (pairing_bls12_381 +@ mul_bls12_381_fq12))
      +@ check_one_bls12_381_fq12

    let stack_n_op n =
      atomic_step_cost (20 + ((n lsr 1) + (n lsr 2) + (n lsr 4)))

    let apply = alloc_cost 8 +@ step_cost 1

    let baker_operation = step_cost 10

    let sapling_empty_state = step_cost 1

    let sapling_verify_update = step_cost 1

    let rec compare : type a. a Script_typed_ir.comparable_ty -> a -> a -> cost
        =
     fun ty x y ->
      match ty with
      | Unit_key _ ->
          compare_unit
      | Never_key _ -> (
        match x with _ -> . )
      | Bool_key _ ->
          compare_bool
      | String_key _ ->
          compare_string x y
      | Signature_key _ ->
          compare_signature x y
      | Bytes_key _ ->
          compare_bytes x y
      | Mutez_key _ ->
          compare_tez x y
      | Int_key _ ->
          compare_zint x y
      | Nat_key _ ->
          compare_zint x y
      | Key_hash_key _ ->
          compare_key_hash x y
      | Key_key _ ->
          compare_key x y
      | Baker_hash_key _ ->
          compare_baker_hash x y
      | Pvss_key _ ->
          compare_pvss_key x y
      | Timestamp_key _ ->
          compare_timestamp x y
      | Address_key _ ->
          compare_address x y
      | Chain_id_key _ ->
          compare_chain_id x y
      | Pair_key ((tl, _), (tr, _), _) ->
          (* Reasonable over-approximation of the cost of lexicographic comparison. *)
          let (xl, xr) = x in
          let (yl, yr) = y in
          compare tl xl yl +@ compare tr xr yr
      | Union_key ((tl, _), (tr, _), _) -> (
          compare_union_tag
          +@
          match (x, y) with
          | (L x, L y) ->
              compare tl x y
          | (L _, R _) ->
              free
          | (R _, L _) ->
              free
          | (R x, R y) ->
              compare tr x y )
      | Option_key (t, _) -> (
          compare_option_tag
          +@
          match (x, y) with
          | (None, None) ->
              free
          | (None, Some _) ->
              free
          | (Some _, None) ->
              free
          | (Some x, Some y) ->
              compare t x y )
  end

  module Typechecking = struct
    let cycle = step_cost 1

    let bool = free

    let unit = free

    let string = string

    let bytes = bytes

    let z = Legacy.zint

    let int_of_string str =
      alloc_cost @@ Pervasives.( / ) (String.length str) 5

    let tez = step_cost 1 +@ alloc_cost 1

    let string_timestamp = step_cost 3 +@ alloc_cost 3

    let key = step_cost 3 +@ alloc_cost 3

    let key_hash = step_cost 1 +@ alloc_cost 1

    let signature = step_cost 1 +@ alloc_cost 1

    let bls12_381_g1 = step_cost 1 +@ alloc_cost 1

    let bls12_381_g2 = step_cost 1 +@ alloc_cost 1

    let bls12_381_fr = step_cost 1 +@ alloc_cost 1

    let baker_hash = step_cost 1 +@ alloc_cost 1

    let pvss_key = step_cost 3 +@ alloc_cost 3

    let chain_id = step_cost 1 +@ alloc_cost 1

    let contract = step_cost 5

    let get_script = step_cost 20 +@ alloc_cost 5

    let contract_exists = step_cost 15 +@ alloc_cost 5

    let pair = alloc_cost 2

    let union = alloc_cost 1

    let lambda = alloc_cost 5 +@ step_cost 3

    let some = alloc_cost 1

    let none = alloc_cost 0

    let list_element = alloc_cost 2 +@ step_cost 1

    let set_element size = log2 size *@ (alloc_cost 3 +@ step_cost 2)

    let map_element size = log2 size *@ (alloc_cost 4 +@ step_cost 2)

    let primitive_type = alloc_cost 1

    let one_arg_type = alloc_cost 2

    let two_arg_type = alloc_cost 3

    let operation b = bytes b

    let type_ nb_args = alloc_cost (nb_args + 1)

    (* Cost of parsing instruction, is cost of allocation of
       constructor + cost of constructor parameters + cost of
       allocation on the stack type *)
    let instr : type b a. (b, a) Script_typed_ir.instr -> cost =
     fun i ->
      let open Script_typed_ir in
      alloc_cost 1
      +@
      (* cost of allocation of constructor *)
      match i with
      | Drop ->
          alloc_cost 0
      | Dup ->
          alloc_cost 1
      | Swap ->
          alloc_cost 0
      | Const _ ->
          alloc_cost 1
      | Cons_pair ->
          alloc_cost 2
      | Car ->
          alloc_cost 1
      | Cdr ->
          alloc_cost 1
      | Unpair ->
          alloc_cost 2
      | Cons_some ->
          alloc_cost 2
      | Cons_none _ ->
          alloc_cost 3
      | If_none _ ->
          alloc_cost 2
      | Cons_left ->
          alloc_cost 3
      | Cons_right ->
          alloc_cost 3
      | If_left _ ->
          alloc_cost 2
      | Cons_list ->
          alloc_cost 1
      | Nil ->
          alloc_cost 1
      | If_cons _ ->
          alloc_cost 2
      | List_map _ ->
          alloc_cost 5
      | List_iter _ ->
          alloc_cost 4
      | List_size ->
          alloc_cost 1
      | Empty_set _ ->
          alloc_cost 1
      | Set_iter _ ->
          alloc_cost 4
      | Set_mem ->
          alloc_cost 1
      | Set_update ->
          alloc_cost 1
      | Set_size ->
          alloc_cost 1
      | Empty_map _ ->
          alloc_cost 2
      | Map_map _ ->
          alloc_cost 5
      | Map_iter _ ->
          alloc_cost 4
      | Map_mem ->
          alloc_cost 1
      | Map_get ->
          alloc_cost 1
      | Map_update ->
          alloc_cost 1
      | Map_size ->
          alloc_cost 1
      | Empty_big_map _ ->
          alloc_cost 2
      | Big_map_mem ->
          alloc_cost 1
      | Big_map_get ->
          alloc_cost 1
      | Big_map_update ->
          alloc_cost 1
      | Concat_string ->
          alloc_cost 1
      | Concat_string_pair ->
          alloc_cost 1
      | Concat_bytes ->
          alloc_cost 1
      | Concat_bytes_pair ->
          alloc_cost 1
      | Slice_string ->
          alloc_cost 1
      | Slice_bytes ->
          alloc_cost 1
      | String_size ->
          alloc_cost 1
      | Bytes_size ->
          alloc_cost 1
      | Add_seconds_to_timestamp ->
          alloc_cost 1
      | Add_timestamp_to_seconds ->
          alloc_cost 1
      | Sub_timestamp_seconds ->
          alloc_cost 1
      | Diff_timestamps ->
          alloc_cost 1
      | Add_tez ->
          alloc_cost 1
      | Sub_tez ->
          alloc_cost 1
      | Mul_teznat ->
          alloc_cost 1
      | Mul_nattez ->
          alloc_cost 1
      | Ediv_teznat ->
          alloc_cost 1
      | Ediv_tez ->
          alloc_cost 1
      | Or ->
          alloc_cost 1
      | And ->
          alloc_cost 1
      | Xor ->
          alloc_cost 1
      | Not ->
          alloc_cost 1
      | Is_nat ->
          alloc_cost 1
      | Neg_nat ->
          alloc_cost 1
      | Neg_int ->
          alloc_cost 1
      | Abs_int ->
          alloc_cost 1
      | Int_nat ->
          alloc_cost 1
      | Add_intint ->
          alloc_cost 1
      | Add_intnat ->
          alloc_cost 1
      | Add_natint ->
          alloc_cost 1
      | Add_natnat ->
          alloc_cost 1
      | Sub_int ->
          alloc_cost 1
      | Mul_intint ->
          alloc_cost 1
      | Mul_intnat ->
          alloc_cost 1
      | Mul_natint ->
          alloc_cost 1
      | Mul_natnat ->
          alloc_cost 1
      | Ediv_intint ->
          alloc_cost 1
      | Ediv_intnat ->
          alloc_cost 1
      | Ediv_natint ->
          alloc_cost 1
      | Ediv_natnat ->
          alloc_cost 1
      | Lsl_nat ->
          alloc_cost 1
      | Lsr_nat ->
          alloc_cost 1
      | Or_nat ->
          alloc_cost 1
      | And_nat ->
          alloc_cost 1
      | And_int_nat ->
          alloc_cost 1
      | Xor_nat ->
          alloc_cost 1
      | Not_nat ->
          alloc_cost 1
      | Not_int ->
          alloc_cost 1
      | Seq _ ->
          alloc_cost 8
      | If _ ->
          alloc_cost 8
      | Loop _ ->
          alloc_cost 4
      | Loop_left _ ->
          alloc_cost 5
      | Dip _ ->
          alloc_cost 4
      | Exec ->
          alloc_cost 1
      | Apply _ ->
          alloc_cost 1
      | Lambda _ ->
          alloc_cost 2
      | Failwith _ ->
          alloc_cost 1
      | Nop ->
          alloc_cost 0
      | Compare _ ->
          alloc_cost 1
      | Eq ->
          alloc_cost 1
      | Neq ->
          alloc_cost 1
      | Lt ->
          alloc_cost 1
      | Gt ->
          alloc_cost 1
      | Le ->
          alloc_cost 1
      | Ge ->
          alloc_cost 1
      | Address ->
          alloc_cost 1
      | Contract _ ->
          alloc_cost 2
      | Transfer_tokens ->
          alloc_cost 1
      | Implicit_account ->
          alloc_cost 1
      | Create_contract_legacy _ ->
          alloc_cost 7
      | Create_contract _ ->
          alloc_cost 7
      | Set_delegate_legacy ->
          alloc_cost 1
      | Set_delegate ->
          alloc_cost 1
      | Now ->
          alloc_cost 1
      | Balance ->
          alloc_cost 1
      | Level ->
          alloc_cost 1
      | Check_signature ->
          alloc_cost 1
      | Hash_key ->
          alloc_cost 1
      | Pack _ ->
          alloc_cost 2
      | Unpack _ ->
          alloc_cost 2
      | Blake2b ->
          alloc_cost 1
      | Sha256 ->
          alloc_cost 1
      | Sha512 ->
          alloc_cost 1
      | Source ->
          alloc_cost 1
      | Sender ->
          alloc_cost 1
      | Self _ ->
          alloc_cost 2
      | Self_address ->
          alloc_cost 1
      | Amount ->
          alloc_cost 1
      | Sapling_empty_state ->
          alloc_cost 1
      | Sapling_verify_update ->
          alloc_cost 1
      | Dig (n, _) ->
          n *@ alloc_cost 1 (* _ is a unary development of n *)
      | Dug (n, _) ->
          n *@ alloc_cost 1
      | Dipn (n, _, _) ->
          n *@ alloc_cost 1
      | Dropn (n, _) ->
          n *@ alloc_cost 1
      | ChainId ->
          alloc_cost 1
      | Never ->
          alloc_cost 0
      | Voting_power ->
          alloc_cost 1
      | Total_voting_power ->
          alloc_cost 1
      | Keccak ->
          alloc_cost 1
      | Sha3 ->
          alloc_cost 1
      | Add_bls12_381_g1 ->
          alloc_cost 1
      | Add_bls12_381_g2 ->
          alloc_cost 1
      | Add_bls12_381_fr ->
          alloc_cost 1
      | Mul_bls12_381_g1 ->
          alloc_cost 1
      | Mul_bls12_381_g2 ->
          alloc_cost 1
      | Mul_bls12_381_fr ->
          alloc_cost 1
      | Neg_bls12_381_g1 ->
          alloc_cost 1
      | Neg_bls12_381_g2 ->
          alloc_cost 1
      | Neg_bls12_381_fr ->
          alloc_cost 1
      | Pairing_check_bls12_381 ->
          alloc_cost 1
      | Submit_proposals ->
          alloc_cost 1
      | Submit_ballot ->
          alloc_cost 1
      | Set_baker_active ->
          alloc_cost 1
      | Set_baker_consensus_key ->
          alloc_cost 1
      | Set_baker_pvss_key ->
          alloc_cost 1
      | Toggle_baker_delegations ->
          alloc_cost 1
  end

  module Unparse = struct
    let prim_cost l annot = Script.prim_node_cost_nonrec_of_length l annot

    let seq_cost = Script.seq_node_cost_nonrec_of_length

    let string_cost length = Script.string_node_cost_of_length length

    let cycle = step_cost 1

    let bool = prim_cost 0 []

    let unit = prim_cost 0 []

    (* We count the length of strings and bytes to prevent hidden
       miscalculations due to non detectable expansion of sharing. *)
    let string s = Script.string_node_cost s

    let bytes s = Script.bytes_node_cost s

    let z i = Script.int_node_cost i

    let int i = Script.int_node_cost (Script_int.to_zint i)

    let tez = Script.int_node_cost_of_numbits 60 (* int64 bound *)

    let timestamp x = Script_timestamp.to_zint x |> Script_int.of_zint |> int

    let operation bytes = Script.bytes_node_cost bytes

    let chain_id = string_cost 15

    let bls12_381_g1 = string_cost Bls12_381.G1.size

    let bls12_381_g2 = string_cost Bls12_381.G2.size

    let bls12_381_fr = string_cost Bls12_381.Fr.size

    let key = string_cost 54

    let key_hash = string_cost 36

    let baker_hash = string_cost 36

    let pvss_key = string_cost 54

    let signature = string_cost 128

    let contract = string_cost 36

    let pair = prim_cost 2 []

    let union = prim_cost 1 []

    let some = prim_cost 1 []

    let none = prim_cost 0 []

    let list_element = alloc_cost 2

    let set_element = alloc_cost 2

    let map_element = alloc_cost 2

    let one_arg_type = prim_cost 1

    let two_arg_type = prim_cost 2

    let sapling_transaction t =
      (* TODO should it be scaled? *)
      let size = Data_encoding.Binary.length Sapling.transaction_encoding t in
      string_cost size

    let sapling_diff d =
      (* TODO should it be scaled? *)
      let size = Data_encoding.Binary.length Sapling.diff_encoding d in
      string_cost size
  end
end
