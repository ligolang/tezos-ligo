(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021-2022 Nomadic Labs <contact@nomadic-labs.com>           *)
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

open Protocol
open Script_typed_ir

type parameters = {
  base_parameters : Michelson_samplers_base.parameters;
  list_size : Base_samplers.range;
  set_size : Base_samplers.range;
  map_size : Base_samplers.range;
}

let parameters_encoding =
  let open Data_encoding in
  let range_encoding = Base_samplers.range_encoding in
  conv
    (fun {base_parameters; list_size; set_size; map_size} ->
      (base_parameters, (list_size, set_size, map_size)))
    (fun (base_parameters, (list_size, set_size, map_size)) ->
      {base_parameters; list_size; set_size; map_size})
    (merge_objs
       Michelson_samplers_base.parameters_encoding
       (obj3
          (req "list_size" range_encoding)
          (req "set_size" range_encoding)
          (req "map_size" range_encoding)))

(* ------------------------------------------------------------------------- *)
(* Helpers. *)

let comparable_downcast = Script_ir_translator.ty_of_comparable_ty

(* ------------------------------------------------------------------------- *)
(* Type names. *)

(* We only want to generated inhabited types, hence Never is not included. *)

type type_name =
  [ `TUnit
  | `TInt
  | `TNat
  | `TSignature
  | `TString
  | `TBytes
  | `TMutez
  | `TKey_hash
  | `TKey
  | `TTimestamp
  | `TAddress
  | `TTx_rollup_l2_address
  | `TBool
  | `TPair
  | `TUnion
  | `TLambda
  | `TOption
  | `TList
  | `TSet
  | `TMap
  | `TBig_map
  | `TContract
  | `TSapling_transaction
  | `TSapling_state
  | `TOperation
  | `TChain_id
  | `TBls12_381_g1
  | `TBls12_381_g2
  | `TBls12_381_fr
  | `TTicket ]

type atomic_type_name =
  [ `TUnit
  | `TInt
  | `TNat
  | `TSignature
  | `TString
  | `TBytes
  | `TMutez
  | `TKey_hash
  | `TKey
  | `TTimestamp
  | `TAddress
  | `TTx_rollup_l2_address
  | `TBool
  | `TSapling_transaction
  | `TSapling_state
  | `TChain_id
  | `TBls12_381_g1
  | `TBls12_381_g2
  | `TBls12_381_fr ]

type non_atomic_type_name =
  [ `TPair
  | `TUnion
  | `TLambda
  | `TOption
  | `TList
  | `TSet
  | `TMap
  | `TBig_map
  | `TContract
  | `TTicket ]

(* Ensure inclusion of atomic_type_name in type_name *)
let (_ : atomic_type_name -> type_name) = fun x -> (x :> type_name)

(* Ensure inclusion of non_atomic_type_name in type_name *)
let (_ : non_atomic_type_name -> type_name) = fun x -> (x :> type_name)

let all_atomic_type_names : atomic_type_name array =
  [|
    `TUnit;
    `TInt;
    `TNat;
    `TSignature;
    `TString;
    `TBytes;
    `TMutez;
    `TKey_hash;
    `TKey;
    `TTimestamp;
    `TAddress;
    `TTx_rollup_l2_address;
    `TBool;
    `TSapling_transaction;
    `TSapling_state;
    `TChain_id;
    `TBls12_381_g1;
    `TBls12_381_g2;
    `TBls12_381_fr;
  |]

let all_non_atomic_type_names : non_atomic_type_name array =
  [|
    `TPair;
    `TUnion;
    `TLambda;
    `TOption;
    `TList;
    `TSet;
    `TMap;
    `TBig_map;
    `TContract;
    `TTicket;
  |]

type comparable_type_name =
  [ `TUnit
  | `TInt
  | `TNat
  | `TSignature
  | `TString
  | `TBytes
  | `TMutez
  | `TBool
  | `TKey_hash
  | `TKey
  | `TTimestamp
  | `TChain_id
  | `TAddress
  | `TTx_rollup_l2_address
  | `TPair
  | `TUnion
  | `TOption ]

(* Ensure inclusion of comparable_type_name in type_name *)
let (_ : comparable_type_name -> type_name) = fun x -> (x :> type_name)

type 'a comparable_and_atomic = 'a
  constraint 'a = [< comparable_type_name] constraint 'a = [< atomic_type_name]

let all_comparable_atomic_type_names : 'a comparable_and_atomic array =
  [|
    `TUnit;
    `TInt;
    `TNat;
    `TSignature;
    `TString;
    `TBytes;
    `TMutez;
    `TBool;
    `TKey_hash;
    `TKey;
    `TTimestamp;
    `TChain_id;
    `TAddress;
    `TTx_rollup_l2_address;
  |]

type 'a comparable_and_non_atomic = 'a
  constraint 'a = [< comparable_type_name]
  constraint 'a = [< non_atomic_type_name]

let all_comparable_non_atomic_type_names : 'a comparable_and_non_atomic array =
  [|`TPair; `TUnion; `TOption|]

(* Ensure inclusion of comparable_and_atomic in type_name *)
let (_ : 'a comparable_and_atomic -> type_name) = fun x -> (x :> type_name)

(* ------------------------------------------------------------------------- *)
(* Uniform type name generators *)

open Sampling_helpers

let uniform : 'a array -> 'a sampler =
 fun arr rng_state ->
  let i = Random.State.int rng_state (Array.length arr) in
  arr.(i)

let uniform_atomic_type_name : atomic_type_name sampler =
  uniform all_atomic_type_names

let uniform_comparable_atomic_type_name : 'a comparable_and_atomic sampler =
  uniform all_comparable_atomic_type_names

let uniform_comparable_non_atomic_type_name :
    'a comparable_and_non_atomic sampler =
  uniform all_comparable_non_atomic_type_names

(* ------------------------------------------------------------------------- *)
(* Random generation functor. *)

module type S = sig
  module Michelson_base : Michelson_samplers_base.S

  module Random_type : sig
    val m_type : size:int -> Script_ir_translator.ex_ty sampler

    val m_comparable_type :
      size:int -> Script_ir_translator.ex_comparable_ty sampler
  end

  module rec Random_value : sig
    val value : 'a Script_typed_ir.ty -> 'a sampler

    val comparable : 'a Script_typed_ir.comparable_ty -> 'a sampler

    val stack : ('a, 'b) Script_typed_ir.stack_ty -> ('a * 'b) sampler
  end
end

exception SamplingError of string

let fail_sampling error = raise (SamplingError error)

module Make (P : sig
  val parameters : parameters
end)
(Crypto_samplers : Crypto_samplers.Finite_key_pool_S) : S = struct
  module Michelson_base = Michelson_samplers_base.Make (struct
    let parameters = P.parameters.base_parameters
  end)

  let memo_size =
    Alpha_context.Sapling.Memo_size.parse_z Z.zero |> Result.get_ok

  (* [pick_split x] randomly splits the integer [x] into two integers [left]
      and [right] such that [1 <= left], [1 <= right], and [left + right = x].
      Expects [x >= 2]. *)
  let pick_split : int -> (int * int) sampler =
   fun x rng_state ->
    if x < 2 then invalid_arg "pick_split"
    else
      (* x >= 2 *)
      let left = 1 + Random.State.int rng_state (x - 1) in
      let right = x - left in
      assert (left + right = x) ;
      (left, right)

  (* Random generation of Michelson types. *)
  module Random_type = struct
    let type_of_atomic_type_name (at_tn : atomic_type_name) :
        Script_ir_translator.ex_ty =
      match at_tn with
      | `TString -> Ex_ty string_t
      | `TNat -> Ex_ty nat_t
      | `TKey -> Ex_ty key_t
      | `TBytes -> Ex_ty bytes_t
      | `TBool -> Ex_ty bool_t
      | `TAddress -> Ex_ty address_t
      | `TTx_rollup_l2_address -> Ex_ty tx_rollup_l2_address_t
      | `TTimestamp -> Ex_ty timestamp_t
      | `TKey_hash -> Ex_ty key_hash_t
      | `TMutez -> Ex_ty mutez_t
      | `TSignature -> Ex_ty signature_t
      | `TUnit -> Ex_ty unit_t
      | `TInt -> Ex_ty int_t
      | `TSapling_state -> Ex_ty (sapling_state_t ~memo_size)
      | `TSapling_transaction -> Ex_ty (sapling_transaction_t ~memo_size)
      | `TChain_id -> Ex_ty chain_id_t
      | `TBls12_381_g1 -> Ex_ty bls12_381_g1_t
      | `TBls12_381_g2 -> Ex_ty bls12_381_g2_t
      | `TBls12_381_fr -> Ex_ty bls12_381_fr_t

    let comparable_type_of_comparable_atomic_type_name
        (cmp_tn : 'a comparable_and_atomic) :
        Script_ir_translator.ex_comparable_ty =
      match cmp_tn with
      | `TString -> Ex_comparable_ty string_key
      | `TNat -> Ex_comparable_ty nat_key
      | `TBytes -> Ex_comparable_ty bytes_key
      | `TBool -> Ex_comparable_ty bool_key
      | `TAddress -> Ex_comparable_ty address_key
      | `TTx_rollup_l2_address -> Ex_comparable_ty tx_rollup_l2_address_key
      | `TTimestamp -> Ex_comparable_ty timestamp_key
      | `TKey_hash -> Ex_comparable_ty key_hash_key
      | `TMutez -> Ex_comparable_ty mutez_key
      | `TInt -> Ex_comparable_ty int_key
      | `TUnit -> Ex_comparable_ty unit_key
      | `TSignature -> Ex_comparable_ty signature_key
      | `TKey -> Ex_comparable_ty key_key
      | `TChain_id -> Ex_comparable_ty chain_id_key

    let rec m_type ~size : Script_ir_translator.ex_ty sampler =
      let open Script_ir_translator in
      let open M in
      if size <= 0 then Stdlib.failwith "m_type: size <= 0"
      else if size = 1 then
        (* only atomic types can have size 1 *)
        let* at_tn = uniform_atomic_type_name in
        return (type_of_atomic_type_name at_tn)
      else if size = 2 then
        bind (uniform [|`TOption; `TList; `TSet; `TTicket; `TContract|])
        @@ function
        | `TOption -> (
            let* (Ex_ty t) = m_type ~size:1 in
            match option_t (-1) t with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TList -> (
            let* (Ex_ty t) = m_type ~size:1 in
            match list_t (-1) t with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TSet -> (
            let* (Ex_comparable_ty t) = m_comparable_type ~size:1 in
            match set_t (-1) t with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TTicket -> (
            let* (Ex_comparable_ty contents) = m_comparable_type ~size:1 in
            match ticket_t (-1) contents with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TContract -> (
            let* (Ex_ty t) = m_type ~size:1 in
            match contract_t (-1) t with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
      else
        bind (uniform all_non_atomic_type_names) @@ function
        | `TPair -> (
            let* (lsize, rsize) = pick_split (size - 1) in
            let* (Ex_ty left) = m_type ~size:lsize in
            let* (Ex_ty right) = m_type ~size:rsize in
            match pair_t (-1) left right with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TLambda -> (
            let* (lsize, rsize) = pick_split (size - 1) in
            let* (Ex_ty domain) = m_type ~size:lsize in
            let* (Ex_ty range) = m_type ~size:rsize in
            match lambda_t (-1) domain range with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TUnion -> (
            let* (lsize, rsize) = pick_split (size - 1) in
            let* (Ex_ty left) = m_type ~size:lsize in
            let* (Ex_ty right) = m_type ~size:rsize in
            match union_t (-1) left right with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TOption -> (
            let* (Ex_ty t) = m_type ~size:(size - 1) in
            match option_t (-1) t with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TMap -> (
            let* (lsize, rsize) = pick_split (size - 1) in
            let* (Ex_comparable_ty key) = m_comparable_type ~size:lsize in
            let* (Ex_ty elt) = m_type ~size:rsize in
            match map_t (-1) key elt with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TSet -> (
            let* (Ex_comparable_ty key_ty) =
              m_comparable_type ~size:(size - 1)
            in
            match set_t (-1) key_ty with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TList -> (
            let* (Ex_ty elt) = m_type ~size:(size - 1) in
            match list_t (-1) elt with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TTicket -> (
            let* (Ex_comparable_ty contents) =
              m_comparable_type ~size:(size - 1)
            in
            match ticket_t (-1) contents with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TContract -> (
            let* (Ex_ty t) = m_type ~size:(size - 1) in
            match contract_t (-1) t with
            | Error _ -> assert false
            | Ok res_ty -> return @@ Ex_ty res_ty)
        | `TBig_map ->
            (* Don't know what to do with theses. Redraw. *)
            m_type ~size

    and m_comparable_type ~size : Script_ir_translator.ex_comparable_ty sampler
        =
      let open M in
      let open Script_ir_translator in
      let atomic_case () =
        let* at_tn = uniform_comparable_atomic_type_name in
        return (comparable_type_of_comparable_atomic_type_name at_tn)
      in
      let option_case size =
        let size = size - 1 in
        let* (Ex_comparable_ty t) = m_comparable_type ~size in
        match option_key (-1) t with
        | Error _ -> (* what should be done here? *) assert false
        | Ok res_ty -> return @@ Ex_comparable_ty res_ty
      in
      let pair_case size =
        let size = size - 1 in
        let* size_left =
          Base_samplers.sample_in_interval ~range:{min = 1; max = size - 1}
        in
        let size_right = size - size_left in
        let* (Ex_comparable_ty l) = m_comparable_type ~size:size_left in
        let* (Ex_comparable_ty r) = m_comparable_type ~size:size_right in
        match pair_key (-1) l r with
        | Error _ -> assert false
        | Ok res_ty -> return @@ Ex_comparable_ty res_ty
      in
      let union_case size =
        let size = size - 1 in
        let* size_left =
          Base_samplers.sample_in_interval ~range:{min = 1; max = size - 1}
        in
        let size_right = size - size_left in
        let* (Ex_comparable_ty l) = m_comparable_type ~size:size_left in
        let* (Ex_comparable_ty r) = m_comparable_type ~size:size_right in
        match union_key (-1) l r with
        | Error _ -> assert false
        | Ok res_ty -> return @@ Ex_comparable_ty res_ty
      in

      if size <= 1 then atomic_case ()
      else if size = 2 then option_case size
      else
        let* cmp_tn = uniform_comparable_non_atomic_type_name in
        match cmp_tn with
        | `TPair -> pair_case size
        | `TUnion -> union_case size
        | `TOption -> option_case size
  end

  (* Type-directed generation of random values. *)
  module rec Random_value : sig
    val value : 'a Script_typed_ir.ty -> 'a sampler

    val comparable : 'a Script_typed_ir.comparable_ty -> 'a sampler

    val stack : ('a, 'b) Script_typed_ir.stack_ty -> ('a * 'b) sampler
  end = struct
    let address rng_state =
      if Base_samplers.uniform_bool rng_state then
        let contract =
          Alpha_context.Contract.implicit_contract
            (Crypto_samplers.pkh rng_state)
        in
        {
          destination = Contract contract;
          entrypoint = Alpha_context.Entrypoint.default;
        }
      else
        (* For a description of the format, see
           tezos-codec describe alpha.contract binary encoding *)
        let string =
          "\001" ^ Base_samplers.uniform_string ~nbytes:20 rng_state ^ "\000"
        in
        let contract =
          Data_encoding.Binary.of_string_exn
            Alpha_context.Contract.encoding
            string
        in
        let ep =
          Alpha_context.Entrypoint.of_string_strict_exn
          @@ Base_samplers.string ~size:{min = 1; max = 31} rng_state
        in
        {destination = Contract contract; entrypoint = ep}

    let tx_rollup_l2_address rng_state =
      let seed =
        Bytes.init 32 (fun _ -> char_of_int @@ Random.State.int rng_state 255)
      in
      let secret_key = Bls12_381.Signature.generate_sk seed in
      Tx_rollup_l2_address.Indexable.value
        (Tx_rollup_l2_address.of_bls_pk
        @@ Bls12_381.Signature.MinPk.derive_pk secret_key)

    let chain_id rng_state =
      let string = Base_samplers.uniform_string ~nbytes:4 rng_state in
      Data_encoding.Binary.of_string_exn Script_chain_id.encoding string

    let signature rng_state =
      Script_signature.make (Michelson_base.signature rng_state)

    let rec value : type a. a Script_typed_ir.ty -> a sampler =
      let open Script_typed_ir in
      fun typ ->
        match typ with
        | Never_t -> assert false
        | Unit_t -> M.return ()
        | Int_t -> Michelson_base.int
        | Nat_t -> Michelson_base.nat
        | Signature_t -> signature
        | String_t -> Michelson_base.string
        | Bytes_t -> Michelson_base.bytes
        | Mutez_t -> Michelson_base.tez
        | Key_hash_t -> Crypto_samplers.pkh
        | Key_t -> Crypto_samplers.pk
        | Timestamp_t -> Michelson_base.timestamp
        | Bool_t -> Base_samplers.uniform_bool
        | Address_t -> address
        | Tx_rollup_l2_address_t -> tx_rollup_l2_address
        | Pair_t (left_t, right_t, _) ->
            M.(
              let* left_v = value left_t in
              let* right_v = value right_t in
              return (left_v, right_v))
        | Union_t (left_t, right_t, _) ->
            fun rng_state ->
              if Base_samplers.uniform_bool rng_state then
                L (value left_t rng_state)
              else R (value right_t rng_state)
        | Lambda_t (arg_ty, ret_ty, _) -> generate_lambda arg_ty ret_ty
        | Option_t (ty, _) ->
            fun rng_state ->
              if Base_samplers.uniform_bool rng_state then None
              else Some (value ty rng_state)
        | List_t (elt_ty, _) -> generate_list elt_ty
        | Set_t (elt_ty, _) -> generate_set elt_ty
        | Map_t (key_ty, val_ty, _) -> generate_map key_ty val_ty
        | Contract_t (arg_ty, _) -> generate_contract arg_ty
        | Operation_t -> generate_operation
        | Big_map_t (key_ty, val_ty, _) -> generate_big_map key_ty val_ty
        | Chain_id_t -> chain_id
        | Bls12_381_g1_t -> generate_bls12_381_g1
        | Bls12_381_g2_t -> generate_bls12_381_g2
        | Bls12_381_fr_t -> generate_bls12_381_fr
        | Ticket_t (contents_ty, _) ->
            let ty = comparable_downcast contents_ty in
            generate_ticket ty
        | Sapling_transaction_t _ ->
            fail_sampling
              "Michelson_samplers: sapling transactions not handled yet"
        | Sapling_state_t _ ->
            fail_sampling "Michelson_samplers: sapling state not handled yet"
        | Chest_key_t ->
            fail_sampling "Michelson_samplers: chest key not handled yet"
        | Chest_t -> fail_sampling "Michelson_samplers: chest not handled yet"

    and generate_lambda :
        type arg ret.
        arg Script_typed_ir.ty ->
        ret Script_typed_ir.ty ->
        (arg, ret) Script_typed_ir.lambda sampler =
     fun _arg_ty _ret_ty _rng_state ->
      fail_sampling "Michelson_samplers: lambda not handled yet"

    and generate_list :
        type elt.
        elt Script_typed_ir.ty -> elt Script_typed_ir.boxed_list sampler =
     fun elt_type ->
      let open M in
      let* (length, elements) =
        Structure_samplers.list
          ~range:P.parameters.list_size
          ~sampler:(value elt_type)
      in
      return Script_typed_ir.{elements; length}

    (* Note that we might very well generate sets smaller than the specified range (consider the
       case of a set of type [unit]). *)
    and generate_set :
        type elt.
        elt Script_typed_ir.comparable_ty -> elt Script_typed_ir.set sampler =
     fun elt_ty ->
      let open M in
      let ety = comparable_downcast elt_ty in
      let* (_, elements) =
        Structure_samplers.list
          ~range:P.parameters.set_size
          ~sampler:(value ety)
      in
      return
      @@ List.fold_left
           (fun set x -> Script_set.update x true set)
           (Script_set.empty elt_ty)
           elements

    and generate_map :
        type key elt.
        key Script_typed_ir.comparable_ty ->
        elt Script_typed_ir.ty ->
        (key, elt) Script_typed_ir.map sampler =
     fun key_ty elt_ty rng_state ->
      let size =
        Base_samplers.sample_in_interval rng_state ~range:P.parameters.map_size
      in
      let kty = comparable_downcast key_ty in
      let keys = List.init size (fun _ -> value kty rng_state) in
      let elts = List.init size (fun _ -> value elt_ty rng_state) in
      List.fold_left2
        (fun map key elt -> Script_map.update key (Some elt) map)
        (Script_map.empty key_ty)
        keys
        elts

    and generate_big_map :
        type key elt.
        key Script_typed_ir.comparable_ty ->
        elt Script_typed_ir.ty ->
        (key, elt) Script_typed_ir.big_map sampler =
      let open Script_typed_ir in
      fun key_ty elt_ty rng_state ->
        let open TzPervasives in
        let result =
          Lwt_main.run
            ( Execution_context.make ~rng_state >>=? fun (ctxt, _) ->
              let big_map = Script_ir_translator.empty_big_map key_ty elt_ty in
              (* Cannot have big maps under big maps *)
              option_t (-1) elt_ty |> Environment.wrap_tzresult
              >>?= fun opt_elt_ty ->
              let map = generate_map key_ty opt_elt_ty rng_state in
              Script_map.fold
                (fun k v acc ->
                  acc >>=? fun (bm, ctxt_acc) ->
                  Script_ir_translator.big_map_update ctxt_acc k v bm)
                map
                (return (big_map, ctxt))
              >|= Environment.wrap_tzresult
              >>=? fun (big_map, _) -> return big_map )
        in
        match result with
        | Ok x -> x
        | Error e ->
            Format.eprintf
              "%a@."
              (Error_monad.TzTrace.pp_print Error_monad.pp)
              e ;
            fail_sampling "raise_if_error"

    and generate_contract :
        type arg.
        arg Script_typed_ir.ty -> arg Script_typed_ir.typed_contract sampler =
     fun arg_ty ->
      let open M in
      let* address = value address_t in
      return (Typed_contract {arg_ty; address})

    and generate_operation : Script_typed_ir.operation sampler =
     fun rng_state ->
      let transfer = generate_transfer_tokens rng_state in
      Script_typed_ir.{piop = transfer; lazy_storage_diff = None}

    and generate_transfer_tokens :
        Alpha_context.packed_internal_operation sampler =
     fun _rng_state -> fail_sampling "generate_transfer_tokens: unimplemented"

    and generate_bls12_381_g1 : Script_bls.G1.t sampler =
     fun rng_state ->
      let b = Bls12_381.G1.(to_bytes (random ~state:rng_state ())) in
      match Script_bls.G1.of_bytes_opt b with
      | Some x -> x
      | None -> assert false

    and generate_bls12_381_g2 : Script_bls.G2.t sampler =
     fun rng_state ->
      let b = Bls12_381.G2.(to_bytes (random ~state:rng_state ())) in
      match Script_bls.G2.of_bytes_opt b with
      | Some x -> x
      | None -> assert false

    and generate_bls12_381_fr : Script_bls.Fr.t sampler =
     fun rng_state ->
      let b = Bls12_381.Fr.(to_bytes (random ~state:rng_state ())) in
      match Script_bls.Fr.of_bytes_opt b with
      | Some x -> x
      | None -> assert false

    and generate_ticket :
        type a. a Script_typed_ir.ty -> a Script_typed_ir.ticket sampler =
     fun ty rng_state ->
      let contents = value ty rng_state in
      let ticketer =
        Alpha_context.Contract.implicit_contract (Crypto_samplers.pkh rng_state)
      in
      let amount = Michelson_base.nat rng_state in
      Script_typed_ir.{ticketer; contents; amount}

    let comparable ty = value (comparable_downcast ty)

    (* Random stack generation. *)
    let rec stack : type a b. (a, b) Script_typed_ir.stack_ty -> (a * b) sampler
        =
      let open M in
      let open Script_typed_ir in
      fun stack_ty ->
        match stack_ty with
        | Item_t (ty, tl) ->
            let* elt = value ty in
            let* tl = stack tl in
            return ((elt, tl) : a * b)
        | Bot_t -> return (EmptyCell, EmptyCell)
  end
end

module Internal_for_tests = struct
  type nonrec type_name = type_name
end
