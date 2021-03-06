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
open Script
open Script_typed_ir
open Script_ir_translator

(* ---- Run-time errors -----------------------------------------------------*)

type execution_trace =
  (Script.location * Gas.t * (Script.expr * string option) list) list

type error +=
  | Reject of Script.location * Script.expr * execution_trace option

type error += Overflow of Script.location * execution_trace option

type error += Runtime_contract_error : Contract.t * Script.expr -> error

type error += Bad_contract_parameter of Contract.t (* `Permanent *)

type error += Cannot_serialize_log

type error += Cannot_serialize_failure

type error += Cannot_serialize_storage

type error += Not_a_baker_contract

let () =
  let open Data_encoding in
  let trace_encoding =
    list
    @@ obj3
         (req "location" Script.location_encoding)
         (req "gas" Gas.encoding)
         (req
            "stack"
            (list (obj2 (req "item" Script.expr_encoding) (opt "annot" string))))
  in
  (* Reject *)
  register_error_kind
    `Temporary
    ~id:"michelson_v1.script_rejected"
    ~title:"Script failed"
    ~description:"A FAILWITH instruction was reached"
    (obj3
       (req "location" Script.location_encoding)
       (req "with" Script.expr_encoding)
       (opt "trace" trace_encoding))
    (function Reject (loc, v, trace) -> Some (loc, v, trace) | _ -> None)
    (fun (loc, v, trace) -> Reject (loc, v, trace)) ;
  (* Overflow *)
  register_error_kind
    `Temporary
    ~id:"michelson_v1.script_overflow"
    ~title:"Script failed (overflow error)"
    ~description:
      "A FAIL instruction was reached due to the detection of an overflow"
    (obj2
       (req "location" Script.location_encoding)
       (opt "trace" trace_encoding))
    (function Overflow (loc, trace) -> Some (loc, trace) | _ -> None)
    (fun (loc, trace) -> Overflow (loc, trace)) ;
  (* Runtime contract error *)
  register_error_kind
    `Temporary
    ~id:"michelson_v1.runtime_error"
    ~title:"Script runtime error"
    ~description:"Toplevel error for all runtime script errors"
    (obj2
       (req "contract_handle" Contract.encoding)
       (req "contract_code" Script.expr_encoding))
    (function
      | Runtime_contract_error (contract, expr) ->
          Some (contract, expr)
      | _ ->
          None)
    (fun (contract, expr) -> Runtime_contract_error (contract, expr)) ;
  (* Bad contract parameter *)
  register_error_kind
    `Permanent
    ~id:"michelson_v1.bad_contract_parameter"
    ~title:"Contract supplied an invalid parameter"
    ~description:
      "Either no parameter was supplied to a contract with a non-unit \
       parameter type, a non-unit parameter was passed to an account, or a \
       parameter was supplied of the wrong type"
    Data_encoding.(obj1 (req "contract" Contract.encoding))
    (function Bad_contract_parameter c -> Some c | _ -> None)
    (fun c -> Bad_contract_parameter c) ;
  (* Cannot serialize log *)
  register_error_kind
    `Temporary
    ~id:"michelson_v1.cannot_serialize_log"
    ~title:"Not enough gas to serialize execution trace"
    ~description:
      "Execution trace with stacks was to big to be serialized with the \
       provided gas"
    Data_encoding.empty
    (function Cannot_serialize_log -> Some () | _ -> None)
    (fun () -> Cannot_serialize_log) ;
  (* Cannot serialize failure *)
  register_error_kind
    `Temporary
    ~id:"michelson_v1.cannot_serialize_failure"
    ~title:"Not enough gas to serialize argument of FAILWITH"
    ~description:
      "Argument of FAILWITH was too big to be serialized with the provided gas"
    Data_encoding.empty
    (function Cannot_serialize_failure -> Some () | _ -> None)
    (fun () -> Cannot_serialize_failure) ;
  (* Cannot serialize storage *)
  register_error_kind
    `Temporary
    ~id:"michelson_v1.cannot_serialize_storage"
    ~title:"Not enough gas to serialize execution storage"
    ~description:
      "The returned storage was too big to be serialized with the provided gas"
    Data_encoding.empty
    (function Cannot_serialize_storage -> Some () | _ -> None)
    (fun () -> Cannot_serialize_storage) ;
  (* Not a baker contract *)
  register_error_kind
    `Permanent
    ~id:"michelson_v1.not_a_baker_contract"
    ~title:"Not a baker contract"
    ~description:"Instruction is only valid for baker contracts"
    Data_encoding.empty
    (function Not_a_baker_contract -> Some () | _ -> None)
    (fun () -> Not_a_baker_contract)

(* ---- interpreter ---------------------------------------------------------*)

let unparse_stack ctxt (stack, stack_ty) =
  (* We drop the gas limit as this function is only used for debugging/errors. *)
  let ctxt = Gas.set_unlimited ctxt in
  let rec unparse_stack :
      type a.
      a stack_ty * a -> (Script.expr * string option) list tzresult Lwt.t =
    function
    | (Empty_t, ()) ->
        return_nil
    | (Item_t (ty, rest_ty, annot), (v, rest)) ->
        unparse_data ctxt Readable ty v
        >>=? fun (data, _ctxt) ->
        unparse_stack (rest_ty, rest)
        >|=? fun rest ->
        let annot =
          match Script_ir_annot.unparse_var_annot annot with
          | [] ->
              None
          | [a] ->
              Some a
          | _ ->
              assert false
        in
        let data = Micheline.strip_locations data in
        (data, annot) :: rest
  in
  unparse_stack (stack_ty, stack)

module Interp_costs = Michelson_v1_gas.Cost_of.Interpreter

let rec interp_stack_prefix_preserving_operation :
    type fbef bef faft aft result.
    (fbef -> (faft * result) tzresult Lwt.t) ->
    (fbef, faft, bef, aft) stack_prefix_preservation_witness ->
    bef ->
    (aft * result) tzresult Lwt.t =
 fun f n stk ->
  match (n, stk) with
  | ( Prefix
        (Prefix
          (Prefix
            (Prefix
              (Prefix
                (Prefix
                  (Prefix
                    (Prefix
                      (Prefix
                        (Prefix
                          (Prefix
                            (Prefix (Prefix (Prefix (Prefix (Prefix n))))))))))))))),
      ( v0,
        ( v1,
          ( v2,
            ( v3,
              ( v4,
                ( v5,
                  ( v6,
                    (v7, (v8, (v9, (va, (vb, (vc, (vd, (ve, (vf, rest)))))))))
                  ) ) ) ) ) ) ) ) ->
      interp_stack_prefix_preserving_operation f n rest
      >|=? fun (rest', result) ->
      ( ( v0,
          ( v1,
            ( v2,
              ( v3,
                ( v4,
                  ( v5,
                    ( v6,
                      ( v7,
                        (v8, (v9, (va, (vb, (vc, (vd, (ve, (vf, rest'))))))))
                      ) ) ) ) ) ) ) ),
        result )
  | (Prefix (Prefix (Prefix (Prefix n))), (v0, (v1, (v2, (v3, rest))))) ->
      interp_stack_prefix_preserving_operation f n rest
      >|=? fun (rest', result) -> ((v0, (v1, (v2, (v3, rest')))), result)
  | (Prefix n, (v, rest)) ->
      interp_stack_prefix_preserving_operation f n rest
      >|=? fun (rest', result) -> ((v, rest'), result)
  | (Rest, v) ->
      f v

type step_constants = {
  source : Contract.t;
  payer : Contract.t;
  self : Contract.t;
  amount : Tez.t;
  chain_id : Chain_id.t;
}

type log_element =
  | Log_element :
      context * Script.location * 'a * 'a Script_typed_ir.stack_ty
      -> log_element

module type STEP_LOGGER = sig
  val log_interp :
    context -> ('bef, 'aft) Script_typed_ir.descr -> 'bef -> unit

  val log_entry : context -> ('bef, 'aft) Script_typed_ir.descr -> 'bef -> unit

  val log_exit : context -> ('bef, 'aft) Script_typed_ir.descr -> 'aft -> unit

  val get_log : unit -> execution_trace option tzresult Lwt.t
end

type logger = (module STEP_LOGGER)

module Trace_logger () : STEP_LOGGER = struct
  let log : log_element list ref = ref []

  let log_interp ctxt descr stack =
    log := Log_element (ctxt, descr.loc, stack, descr.bef) :: !log

  let log_entry _ctxt _descr _stack = ()

  let log_exit ctxt descr stack =
    log := Log_element (ctxt, descr.loc, stack, descr.aft) :: !log

  let get_log () =
    map_s
      (fun (Log_element (ctxt, loc, stack, stack_ty)) ->
        trace Cannot_serialize_log (unparse_stack ctxt (stack, stack_ty))
        >>=? fun stack -> return (loc, Gas.level ctxt, stack))
      !log
    >>=? fun res -> return (Some (List.rev res))
end

module No_trace : STEP_LOGGER = struct
  let log_interp _ctxt _descr _stack = ()

  let log_entry _ctxt _descr _stack = ()

  let log_exit _ctxt _descr _stack = ()

  let get_log () = return_none
end

let cost_of_instr : type b a. (b, a) descr -> b -> Gas.cost =
 fun descr stack ->
  let cycle_cost = Interp_costs.cycle in
  let instr_cost =
    match (descr.instr, stack) with
    | (Drop, _) ->
        Interp_costs.stack_op
    | (Dup, _) ->
        Interp_costs.stack_op
    | (Swap, _) ->
        Interp_costs.stack_op
    | (Const _, _) ->
        Interp_costs.push
    | (Cons_some, _) ->
        Interp_costs.wrap
    | (Cons_none _, _) ->
        Interp_costs.variant_no_data
    | (If_none _, _) ->
        Interp_costs.branch
    | (Cons_pair, _) ->
        Interp_costs.pair
    | (Unpair, _) ->
        Interp_costs.unpair
    | (Car, _) ->
        Interp_costs.pair_access
    | (Cdr, _) ->
        Interp_costs.pair_access
    | (Cons_left, _) ->
        Interp_costs.wrap
    | (Cons_right, _) ->
        Interp_costs.wrap
    | (If_left _, _) ->
        Interp_costs.branch
    | (Cons_list, _) ->
        Interp_costs.cons
    | (Nil, _) ->
        Interp_costs.variant_no_data
    | (If_cons _, _) ->
        Interp_costs.branch
    | (List_map _, (list, _)) ->
        Interp_costs.list_map list
    | (List_size, _) ->
        Interp_costs.push
    | (List_iter _, (l, _)) ->
        Interp_costs.list_iter l
    | (Empty_set _, _) ->
        Interp_costs.empty_set
    | (Set_iter _, (set, _)) ->
        Interp_costs.set_iter set
    | (Set_mem, (v, (set, _))) ->
        Interp_costs.set_mem v set
    | (Set_update, (v, (presence, (set, _)))) ->
        Interp_costs.set_update v presence set
    | (Set_size, _) ->
        Interp_costs.set_size
    | (Empty_map _, _) ->
        Interp_costs.empty_map
    | (Map_map _, (map, _)) ->
        Interp_costs.map_map map
    | (Map_iter _, (map, _)) ->
        Interp_costs.map_iter map
    | (Map_mem, (v, (map, _rest))) ->
        Interp_costs.map_mem v map
    | (Map_get, (v, (map, _rest))) ->
        Interp_costs.map_get v map
    | (Map_update, (k, (v, (map, _)))) ->
        Interp_costs.map_update k v map
    | (Map_size, _) ->
        Interp_costs.map_size
    | (Empty_big_map _, _) ->
        Interp_costs.empty_map
    | (Big_map_mem, (key, (map, _))) ->
        Interp_costs.map_mem key map.diff
    | (Big_map_get, (key, (map, _))) ->
        Interp_costs.map_get key map.diff
    | (Big_map_update, (key, (maybe_value, (map, _)))) ->
        Interp_costs.map_update key (Some maybe_value) map.diff
    | (Add_seconds_to_timestamp, (n, (t, _))) ->
        Interp_costs.add_timestamp t n
    | (Add_timestamp_to_seconds, (t, (n, _))) ->
        Interp_costs.add_timestamp t n
    | (Sub_timestamp_seconds, (t, (s, _))) ->
        Interp_costs.sub_timestamp t s
    | (Diff_timestamps, (t1, (t2, _))) ->
        Interp_costs.diff_timestamps t1 t2
    | (Concat_string_pair, (_x, (_y, _))) ->
        Interp_costs.concat_string ~length:2
    | (Concat_string, (ss, _)) ->
        Interp_costs.concat_string ~length:ss.Script_typed_ir.length
    | (Slice_string, (_offset, (length, (_s, _)))) ->
        let length = Script_int.to_zint length in
        Interp_costs.slice_string (Z.to_int length)
    | (String_size, _) ->
        Interp_costs.push
    | (Concat_bytes_pair, (_x, (_y, _))) ->
        Interp_costs.concat_bytes ~length:2
    | (Concat_bytes, (ss, _)) ->
        Interp_costs.concat_bytes ~length:ss.Script_typed_ir.length
    | (Slice_bytes, (_offset, (length, (_s, _)))) ->
        let length = Script_int.to_zint length in
        Interp_costs.slice_string (Z.to_int length)
    | (Bytes_size, _) ->
        Interp_costs.push
    | (Add_tez, _) ->
        Interp_costs.int64_op
    | (Sub_tez, _) ->
        Interp_costs.int64_op
    | (Mul_teznat, _) ->
        Gas.(Interp_costs.int64_op +@ Interp_costs.z_to_int64)
    | (Mul_nattez, _) ->
        Gas.(Interp_costs.int64_op +@ Interp_costs.z_to_int64)
    | (Or, (x, (y, _))) ->
        Interp_costs.bool_binop x y
    | (And, (x, (y, _))) ->
        Interp_costs.bool_binop x y
    | (Xor, (x, (y, _))) ->
        Interp_costs.bool_binop x y
    | (Not, (x, _)) ->
        Interp_costs.bool_unop x
    | (Is_nat, (x, _)) ->
        Interp_costs.abs x
    | (Abs_int, (x, _)) ->
        Interp_costs.abs x
    | (Int_nat, (x, _)) ->
        Interp_costs.int x
    | (Neg_int, (x, _)) ->
        Interp_costs.neg x
    | (Neg_nat, (x, _)) ->
        Interp_costs.neg x
    | (Add_intint, (x, (y, _))) ->
        Interp_costs.add x y
    | (Add_intnat, (x, (y, _))) ->
        Interp_costs.add x y
    | (Add_natint, (x, (y, _))) ->
        Interp_costs.add x y
    | (Add_natnat, (x, (y, _))) ->
        Interp_costs.add x y
    | (Sub_int, (x, (y, _))) ->
        Interp_costs.sub x y
    | (Mul_intint, (x, (y, _))) ->
        Interp_costs.mul x y
    | (Mul_intnat, (x, (y, _))) ->
        Interp_costs.mul x y
    | (Mul_natint, (x, (y, _))) ->
        Interp_costs.mul x y
    | (Mul_natnat, (x, (y, _))) ->
        Interp_costs.mul x y
    | (Ediv_teznat, (x, (y, _))) ->
        let open Gas in
        let x = Script_int.of_int64 (Tez.to_mutez x) in
        Interp_costs.int64_to_z +@ Interp_costs.div x y
    | (Ediv_tez, (x, (y, _))) ->
        let open Gas in
        let x = Script_int.abs (Script_int.of_int64 (Tez.to_mutez x)) in
        let y = Script_int.abs (Script_int.of_int64 (Tez.to_mutez y)) in
        Interp_costs.int64_to_z +@ Interp_costs.int64_to_z
        +@ Interp_costs.div x y
    | (Ediv_intint, (x, (y, _))) ->
        Interp_costs.div x y
    | (Ediv_intnat, (x, (y, _))) ->
        Interp_costs.div x y
    | (Ediv_natint, (x, (y, _))) ->
        Interp_costs.div x y
    | (Ediv_natnat, (x, (y, _))) ->
        Interp_costs.div x y
    | (Lsl_nat, (x, (y, _))) ->
        Interp_costs.shift_left x y
    | (Lsr_nat, (x, (y, _))) ->
        Interp_costs.shift_right x y
    | (Or_nat, (x, (y, _))) ->
        Interp_costs.logor x y
    | (And_nat, (x, (y, _))) ->
        Interp_costs.logand x y
    | (And_int_nat, (x, (y, _))) ->
        Interp_costs.logand x y
    | (Xor_nat, (x, (y, _))) ->
        Interp_costs.logxor x y
    | (Not_int, (x, _)) ->
        Interp_costs.lognot x
    | (Not_nat, (x, _)) ->
        Interp_costs.lognot x
    | (Seq _, _) ->
        Gas.free
    | (If _, _) ->
        Interp_costs.branch
    | (Loop _, _) ->
        Interp_costs.loop_cycle
    | (Loop_left _, _) ->
        Interp_costs.loop_cycle
    | (Dip _, _) ->
        Interp_costs.stack_op
    | (Exec, _) ->
        Interp_costs.exec
    | (Apply _, _) ->
        Interp_costs.apply
    | (Lambda _, _) ->
        Interp_costs.push
    | (Failwith _, _) ->
        Gas.free
    | (Nop, _) ->
        Gas.free
    | (Compare ty, (a, (b, _))) ->
        Interp_costs.compare ty a b
    | (Eq, _) ->
        Interp_costs.compare_res
    | (Neq, _) ->
        Interp_costs.compare_res
    | (Lt, _) ->
        Interp_costs.compare_res
    | (Le, _) ->
        Interp_costs.compare_res
    | (Gt, _) ->
        Interp_costs.compare_res
    | (Ge, _) ->
        Interp_costs.compare_res
    | (Pack _, _) ->
        Gas.free
    | (Unpack _, _) ->
        Gas.free
    | (Address, _) ->
        Interp_costs.address
    | (Contract _, _) ->
        Interp_costs.contract
    | (Transfer_tokens, _) ->
        Interp_costs.transfer
    | (Implicit_account, _) ->
        Interp_costs.implicit_account
    | (Create_contract_legacy _, _) ->
        Interp_costs.create_contract
    | (Create_contract _, _) ->
        Interp_costs.create_contract
    | (Set_delegate_legacy, _) ->
        Interp_costs.set_delegate
    | (Set_delegate, _) ->
        Interp_costs.set_delegate
    | (Balance, _) ->
        Interp_costs.balance
    | (Level, _) ->
        Interp_costs.level
    | (Now, _) ->
        Interp_costs.now
    | (Check_signature, (key, (_, (message, _)))) ->
        Interp_costs.check_signature key message
    | (Hash_key, _) ->
        Interp_costs.hash_key
    | (Blake2b, (bytes, _)) ->
        Interp_costs.hash_blake2b bytes
    | (Sha256, (bytes, _)) ->
        Interp_costs.hash_sha256 bytes
    | (Sha512, (bytes, _)) ->
        Interp_costs.hash_sha512 bytes
    | (Source, _) ->
        Interp_costs.source
    | (Sender, _) ->
        Interp_costs.source
    | (Self _, _) ->
        Interp_costs.self
    | (Self_address, _) ->
        Interp_costs.self
    | (Amount, _) ->
        Interp_costs.amount
    | (Dig (n, _), _) ->
        Interp_costs.stack_n_op n
    | (Dug (n, _), _) ->
        Interp_costs.stack_n_op n
    | (Dipn (n, _, _), _) ->
        Interp_costs.stack_n_op n
    | (Dropn (n, _), _) ->
        Interp_costs.stack_n_op n
    | (ChainId, _) ->
        Interp_costs.chain_id
    | (Never, (_, _)) ->
        .
    | (Voting_power, _) ->
        Interp_costs.get_voting_power
    | (Total_voting_power, _) ->
        Interp_costs.get_total_voting_power
    | (Keccak, (bytes, _)) ->
        Interp_costs.hash_keccak bytes
    | (Sha3, (bytes, _)) ->
        Interp_costs.hash_sha3 bytes
    | (Add_bls12_381_g1, _) ->
        Interp_costs.add_bls12_381_g1
    | (Add_bls12_381_g2, _) ->
        Interp_costs.add_bls12_381_g2
    | (Add_bls12_381_fr, _) ->
        Interp_costs.add_bls12_381_fr
    | (Mul_bls12_381_g1, _) ->
        Interp_costs.mul_bls12_381_g1
    | (Mul_bls12_381_g2, _) ->
        Interp_costs.mul_bls12_381_g2
    | (Mul_bls12_381_fr, _) ->
        Interp_costs.mul_bls12_381_fr
    | (Neg_bls12_381_g1, _) ->
        Interp_costs.neg_bls12_381_g1
    | (Neg_bls12_381_g2, _) ->
        Interp_costs.neg_bls12_381_g2
    | (Neg_bls12_381_fr, _) ->
        Interp_costs.neg_bls12_381_fr
    | (Pairing_check_bls12_381, (pairs, _)) ->
        Interp_costs.pairing_check_bls12_381 pairs.length
    | (Submit_proposals, _) ->
        Interp_costs.baker_operation
    | (Submit_ballot, _) ->
        Interp_costs.baker_operation
    | (Set_baker_active, _) ->
        Interp_costs.baker_operation
    | (Set_baker_consensus_key, _) ->
        Interp_costs.baker_operation
    | (Set_baker_pvss_key, _) ->
        Interp_costs.baker_operation
    | (Toggle_baker_delegations, _) ->
        Interp_costs.baker_operation
    | (Sapling_empty_state, _) ->
        Interp_costs.sapling_empty_state
    | (Sapling_verify_update, _) ->
        Interp_costs.sapling_verify_update
  in
  Gas.(cycle_cost +@ instr_cost)

let rec step :
    type b a.
    logger ->
    context ->
    step_constants ->
    (b, a) descr ->
    b ->
    (a * context) tzresult Lwt.t =
 fun logger ctxt step_constants ({instr; loc; _} as descr) stack ->
  let gas = cost_of_instr descr stack in
  Gas.consume ctxt gas
  >>?= fun ctxt ->
  let module Log = (val logger) in
  Log.log_entry ctxt descr stack ;
  let logged_return : a * context -> (a * context) tzresult Lwt.t =
   fun (ret, ctxt) ->
    Log.log_exit ctxt descr ret ;
    return (ret, ctxt)
  in
  let is_self_baker : baker_hash tzresult Lwt.t =
    match Contract.is_baker step_constants.self with
    | None ->
        fail Not_a_baker_contract
    | Some baker ->
        return baker
  in
  match (instr, stack) with
  (* stack ops *)
  | (Drop, (_, rest)) ->
      logged_return (rest, ctxt)
  | (Dup, (v, rest)) ->
      logged_return ((v, (v, rest)), ctxt)
  | (Swap, (vi, (vo, rest))) ->
      logged_return ((vo, (vi, rest)), ctxt)
  | (Const v, rest) ->
      logged_return ((v, rest), ctxt)
  (* options *)
  | (Cons_some, (v, rest)) ->
      logged_return ((Some v, rest), ctxt)
  | (Cons_none _, rest) ->
      logged_return ((None, rest), ctxt)
  | (If_none (bt, _), (None, rest)) ->
      step logger ctxt step_constants bt rest
  | (If_none (_, bf), (Some v, rest)) ->
      step logger ctxt step_constants bf (v, rest)
  (* pairs *)
  | (Cons_pair, (a, (b, rest))) ->
      logged_return (((a, b), rest), ctxt)
  | (Unpair, ((a, b), rest)) ->
      logged_return ((a, (b, rest)), ctxt)
  | (Car, ((a, _), rest)) ->
      logged_return ((a, rest), ctxt)
  | (Cdr, ((_, b), rest)) ->
      logged_return ((b, rest), ctxt)
  (* unions *)
  | (Cons_left, (v, rest)) ->
      logged_return ((L v, rest), ctxt)
  | (Cons_right, (v, rest)) ->
      logged_return ((R v, rest), ctxt)
  | (If_left (bt, _), (L v, rest)) ->
      step logger ctxt step_constants bt (v, rest)
  | (If_left (_, bf), (R v, rest)) ->
      step logger ctxt step_constants bf (v, rest)
  (* lists *)
  | (Cons_list, (hd, (tl, rest))) ->
      logged_return ((list_cons hd tl, rest), ctxt)
  | (Nil, rest) ->
      logged_return ((list_empty, rest), ctxt)
  | (If_cons (_, bf), ({elements = []; _}, rest)) ->
      step logger ctxt step_constants bf rest
  | (If_cons (bt, _), ({elements = hd :: tl; length}, rest)) ->
      let tl = {elements = tl; length = length - 1} in
      step logger ctxt step_constants bt (hd, (tl, rest))
  | (List_map body, (list, rest)) ->
      let rec loop rest ctxt l acc =
        match l with
        | [] ->
            let result = {elements = List.rev acc; length = list.length} in
            return ((result, rest), ctxt)
        | hd :: tl ->
            step logger ctxt step_constants body (hd, rest)
            >>=? fun ((hd, rest), ctxt) -> loop rest ctxt tl (hd :: acc)
      in
      loop rest ctxt list.elements []
      >>=? fun (res, ctxt) -> logged_return (res, ctxt)
  | (List_size, (list, rest)) ->
      logged_return ((Script_int.(abs (of_int list.length)), rest), ctxt)
  | (List_iter body, (l, init)) ->
      let rec loop ctxt l stack =
        match l with
        | [] ->
            return (stack, ctxt)
        | hd :: tl ->
            step logger ctxt step_constants body (hd, stack)
            >>=? fun (stack, ctxt) -> loop ctxt tl stack
      in
      loop ctxt l.elements init
      >>=? fun (res, ctxt) -> logged_return (res, ctxt)
  (* sets *)
  | (Empty_set t, rest) ->
      logged_return ((empty_set t, rest), ctxt)
  | (Set_iter body, (set, init)) ->
      set_fold_m
        (fun item (stack, ctxt) ->
          step logger ctxt step_constants body (item, stack))
        set
        (init, ctxt)
      >>=? fun (res, ctxt) -> logged_return (res, ctxt)
  | (Set_mem, (v, (set, rest))) ->
      logged_return ((set_mem v set, rest), ctxt)
  | (Set_update, (v, (presence, (set, rest)))) ->
      logged_return ((set_update v presence set, rest), ctxt)
  | (Set_size, (set, rest)) ->
      logged_return ((set_size set, rest), ctxt)
  (* maps *)
  | (Empty_map (t, _), rest) ->
      logged_return ((empty_map t, rest), ctxt)
  | (Map_map body, (map, rest)) ->
      map_fold_m
        (fun ((k, _) as item) (rest, ctxt, acc) ->
          step logger ctxt step_constants body (item, rest)
          >|=? fun ((item, rest), ctxt) ->
          (rest, ctxt, map_update k (Some item) acc))
        map
        (rest, ctxt, empty_map (map_key_ty map))
      >>=? fun (rest, ctxt, res) -> logged_return ((res, rest), ctxt)
  | (Map_iter body, (map, init)) ->
      map_fold_m
        (fun item (stack, ctxt) ->
          step logger ctxt step_constants body (item, stack))
        map
        (init, ctxt)
      >>=? fun (res, ctxt) -> logged_return (res, ctxt)
  | (Map_mem, (v, (map, rest))) ->
      logged_return ((map_mem v map, rest), ctxt)
  | (Map_get, (v, (map, rest))) ->
      logged_return ((map_get v map, rest), ctxt)
  | (Map_update, (k, (v, (map, rest)))) ->
      logged_return ((map_update k v map, rest), ctxt)
  | (Map_size, (map, rest)) ->
      logged_return ((map_size map, rest), ctxt)
  (* Big map operations *)
  | (Empty_big_map (tk, tv), rest) ->
      logged_return ((Script_ir_translator.empty_big_map tk tv, rest), ctxt)
  | (Big_map_mem, (key, (map, rest))) ->
      Script_ir_translator.big_map_mem ctxt key map
      >>=? fun (res, ctxt) -> logged_return ((res, rest), ctxt)
  | (Big_map_get, (key, (map, rest))) ->
      Script_ir_translator.big_map_get ctxt key map
      >>=? fun (res, ctxt) -> logged_return ((res, rest), ctxt)
  | (Big_map_update, (key, (maybe_value, (map, rest)))) ->
      let big_map = Script_ir_translator.big_map_update key maybe_value map in
      logged_return ((big_map, rest), ctxt)
  (* timestamp operations *)
  | (Add_seconds_to_timestamp, (n, (t, rest))) ->
      let result = Script_timestamp.add_delta t n in
      logged_return ((result, rest), ctxt)
  | (Add_timestamp_to_seconds, (t, (n, rest))) ->
      let result = Script_timestamp.add_delta t n in
      logged_return ((result, rest), ctxt)
  | (Sub_timestamp_seconds, (t, (s, rest))) ->
      let result = Script_timestamp.sub_delta t s in
      logged_return ((result, rest), ctxt)
  | (Diff_timestamps, (t1, (t2, rest))) ->
      let result = Script_timestamp.diff t1 t2 in
      logged_return ((result, rest), ctxt)
  (* string operations *)
  | (Concat_string_pair, (x, (y, rest))) ->
      let s = String.concat "" [x; y] in
      logged_return ((s, rest), ctxt)
  | (Concat_string, (ss, rest)) ->
      let s = String.concat "" ss.elements in
      logged_return ((s, rest), ctxt)
  | (Slice_string, (offset, (length, (s, rest)))) ->
      let s_length = Z.of_int (String.length s) in
      let offset = Script_int.to_zint offset in
      let length = Script_int.to_zint length in
      if Compare.Z.(offset < s_length && Z.add offset length <= s_length) then
        logged_return
          ( (Some (String.sub s (Z.to_int offset) (Z.to_int length)), rest),
            ctxt )
      else logged_return ((None, rest), ctxt)
  | (String_size, (s, rest)) ->
      logged_return ((Script_int.(abs (of_int (String.length s))), rest), ctxt)
  (* bytes operations *)
  | (Concat_bytes_pair, (x, (y, rest))) ->
      let s = Bytes.cat x y in
      logged_return ((s, rest), ctxt)
  | (Concat_bytes, (ss, rest)) ->
      let s = Bytes.concat Bytes.empty ss.elements in
      logged_return ((s, rest), ctxt)
  | (Slice_bytes, (offset, (length, (s, rest)))) ->
      let s_length = Z.of_int (Bytes.length s) in
      let offset = Script_int.to_zint offset in
      let length = Script_int.to_zint length in
      if Compare.Z.(offset < s_length && Z.add offset length <= s_length) then
        logged_return
          ((Some (Bytes.sub s (Z.to_int offset) (Z.to_int length)), rest), ctxt)
      else logged_return ((None, rest), ctxt)
  | (Bytes_size, (s, rest)) ->
      logged_return ((Script_int.(abs (of_int (Bytes.length s))), rest), ctxt)
  (* currency operations *)
  | (Add_tez, (x, (y, rest))) ->
      Tez.(x +? y) >>?= fun res -> logged_return ((res, rest), ctxt)
  | (Sub_tez, (x, (y, rest))) ->
      Tez.(x -? y) >>?= fun res -> logged_return ((res, rest), ctxt)
  | (Mul_teznat, (x, (y, rest))) -> (
    match Script_int.to_int64 y with
    | None ->
        Log.get_log () >>=? fun log -> fail (Overflow (loc, log))
    | Some y ->
        Tez.(x *? y) >>?= fun res -> logged_return ((res, rest), ctxt) )
  | (Mul_nattez, (y, (x, rest))) -> (
    match Script_int.to_int64 y with
    | None ->
        Log.get_log () >>=? fun log -> fail (Overflow (loc, log))
    | Some y ->
        Tez.(x *? y) >>?= fun res -> logged_return ((res, rest), ctxt) )
  (* boolean operations *)
  | (Or, (x, (y, rest))) ->
      logged_return ((x || y, rest), ctxt)
  | (And, (x, (y, rest))) ->
      logged_return ((x && y, rest), ctxt)
  | (Xor, (x, (y, rest))) ->
      logged_return ((Compare.Bool.(x <> y), rest), ctxt)
  | (Not, (x, rest)) ->
      logged_return ((not x, rest), ctxt)
  (* integer operations *)
  | (Is_nat, (x, rest)) ->
      logged_return ((Script_int.is_nat x, rest), ctxt)
  | (Abs_int, (x, rest)) ->
      logged_return ((Script_int.abs x, rest), ctxt)
  | (Int_nat, (x, rest)) ->
      logged_return ((Script_int.int x, rest), ctxt)
  | (Neg_int, (x, rest)) ->
      logged_return ((Script_int.neg x, rest), ctxt)
  | (Neg_nat, (x, rest)) ->
      logged_return ((Script_int.neg x, rest), ctxt)
  | (Add_intint, (x, (y, rest))) ->
      logged_return ((Script_int.add x y, rest), ctxt)
  | (Add_intnat, (x, (y, rest))) ->
      logged_return ((Script_int.add x y, rest), ctxt)
  | (Add_natint, (x, (y, rest))) ->
      logged_return ((Script_int.add x y, rest), ctxt)
  | (Add_natnat, (x, (y, rest))) ->
      logged_return ((Script_int.add_n x y, rest), ctxt)
  | (Sub_int, (x, (y, rest))) ->
      logged_return ((Script_int.sub x y, rest), ctxt)
  | (Mul_intint, (x, (y, rest))) ->
      logged_return ((Script_int.mul x y, rest), ctxt)
  | (Mul_intnat, (x, (y, rest))) ->
      logged_return ((Script_int.mul x y, rest), ctxt)
  | (Mul_natint, (x, (y, rest))) ->
      logged_return ((Script_int.mul x y, rest), ctxt)
  | (Mul_natnat, (x, (y, rest))) ->
      logged_return ((Script_int.mul_n x y, rest), ctxt)
  | (Ediv_teznat, (x, (y, rest))) ->
      let x = Script_int.of_int64 (Tez.to_mutez x) in
      let result =
        match Script_int.ediv x y with
        | None ->
            None
        | Some (q, r) -> (
          match (Script_int.to_int64 q, Script_int.to_int64 r) with
          | (Some q, Some r) -> (
            match (Tez.of_mutez q, Tez.of_mutez r) with
            | (Some q, Some r) ->
                Some (q, r)
            (* Cannot overflow *)
            | _ ->
                assert false )
          (* Cannot overflow *)
          | _ ->
              assert false )
      in
      logged_return ((result, rest), ctxt)
  | (Ediv_tez, (x, (y, rest))) ->
      let x = Script_int.abs (Script_int.of_int64 (Tez.to_mutez x)) in
      let y = Script_int.abs (Script_int.of_int64 (Tez.to_mutez y)) in
      let result =
        match Script_int.ediv_n x y with
        | None ->
            None
        | Some (q, r) -> (
          match Script_int.to_int64 r with
          | None ->
              assert false (* Cannot overflow *)
          | Some r -> (
            match Tez.of_mutez r with
            | None ->
                assert false (* Cannot overflow *)
            | Some r ->
                Some (q, r) ) )
      in
      logged_return ((result, rest), ctxt)
  | (Ediv_intint, (x, (y, rest))) ->
      logged_return ((Script_int.ediv x y, rest), ctxt)
  | (Ediv_intnat, (x, (y, rest))) ->
      logged_return ((Script_int.ediv x y, rest), ctxt)
  | (Ediv_natint, (x, (y, rest))) ->
      logged_return ((Script_int.ediv x y, rest), ctxt)
  | (Ediv_natnat, (x, (y, rest))) ->
      logged_return ((Script_int.ediv_n x y, rest), ctxt)
  | (Lsl_nat, (x, (y, rest))) -> (
    match Script_int.shift_left_n x y with
    | None ->
        Log.get_log () >>=? fun log -> fail (Overflow (loc, log))
    | Some x ->
        logged_return ((x, rest), ctxt) )
  | (Lsr_nat, (x, (y, rest))) -> (
    match Script_int.shift_right_n x y with
    | None ->
        Log.get_log () >>=? fun log -> fail (Overflow (loc, log))
    | Some r ->
        logged_return ((r, rest), ctxt) )
  | (Or_nat, (x, (y, rest))) ->
      logged_return ((Script_int.logor x y, rest), ctxt)
  | (And_nat, (x, (y, rest))) ->
      logged_return ((Script_int.logand x y, rest), ctxt)
  | (And_int_nat, (x, (y, rest))) ->
      logged_return ((Script_int.logand x y, rest), ctxt)
  | (Xor_nat, (x, (y, rest))) ->
      logged_return ((Script_int.logxor x y, rest), ctxt)
  | (Not_int, (x, rest)) ->
      logged_return ((Script_int.lognot x, rest), ctxt)
  | (Not_nat, (x, rest)) ->
      logged_return ((Script_int.lognot x, rest), ctxt)
  (* control *)
  | (Seq (hd, tl), stack) ->
      step logger ctxt step_constants hd stack
      >>=? fun (trans, ctxt) -> step logger ctxt step_constants tl trans
  | (If (bt, _), (true, rest)) ->
      step logger ctxt step_constants bt rest
  | (If (_, bf), (false, rest)) ->
      step logger ctxt step_constants bf rest
  | (Loop body, (true, rest)) ->
      step logger ctxt step_constants body rest
      >>=? fun (trans, ctxt) -> step logger ctxt step_constants descr trans
  | (Loop _, (false, rest)) ->
      logged_return (rest, ctxt)
  | (Loop_left body, (L v, rest)) ->
      step logger ctxt step_constants body (v, rest)
      >>=? fun (trans, ctxt) -> step logger ctxt step_constants descr trans
  | (Loop_left _, (R v, rest)) ->
      logged_return ((v, rest), ctxt)
  | (Dip b, (ign, rest)) ->
      step logger ctxt step_constants b rest
      >>=? fun (res, ctxt) -> logged_return ((ign, res), ctxt)
  | (Exec, (arg, (lam, rest))) ->
      interp logger ctxt step_constants lam arg
      >>=? fun (res, ctxt) -> logged_return ((res, rest), ctxt)
  | (Apply capture_ty, (capture, (lam, rest))) -> (
      let (Lam (descr, expr)) = lam in
      let (Item_t (full_arg_ty, _, _)) = descr.bef in
      unparse_data ctxt Optimized capture_ty capture
      >>=? fun (const_expr, ctxt) ->
      unparse_ty ctxt capture_ty
      >>?= fun (ty_expr, ctxt) ->
      match full_arg_ty with
      | Pair_t ((capture_ty, _, _), (arg_ty, _, _), _) ->
          let arg_stack_ty = Item_t (arg_ty, Empty_t, None) in
          let const_descr =
            ( {
                loc = descr.loc;
                bef = arg_stack_ty;
                aft = Item_t (capture_ty, arg_stack_ty, None);
                instr = Const capture;
              }
              : (_, _) descr )
          in
          let pair_descr =
            ( {
                loc = descr.loc;
                bef = Item_t (capture_ty, arg_stack_ty, None);
                aft = Item_t (full_arg_ty, Empty_t, None);
                instr = Cons_pair;
              }
              : (_, _) descr )
          in
          let seq_descr =
            ( {
                loc = descr.loc;
                bef = arg_stack_ty;
                aft = Item_t (full_arg_ty, Empty_t, None);
                instr = Seq (const_descr, pair_descr);
              }
              : (_, _) descr )
          in
          let full_descr =
            ( {
                loc = descr.loc;
                bef = arg_stack_ty;
                aft = descr.aft;
                instr = Seq (seq_descr, descr);
              }
              : (_, _) descr )
          in
          let full_expr =
            Micheline.Seq
              ( 0,
                [ Prim (0, I_PUSH, [ty_expr; const_expr], []);
                  Prim (0, I_PAIR, [], []);
                  expr ] )
          in
          let lam' = Lam (full_descr, full_expr) in
          logged_return ((lam', rest), ctxt)
      | _ ->
          assert false )
  | (Lambda lam, rest) ->
      logged_return ((lam, rest), ctxt)
  | (Failwith tv, (v, _)) ->
      trace Cannot_serialize_failure (unparse_data ctxt Optimized tv v)
      >>=? fun (v, _ctxt) ->
      let v = Micheline.strip_locations v in
      Log.get_log () >>=? fun log -> fail (Reject (loc, v, log))
  | (Nop, stack) ->
      logged_return (stack, ctxt)
  (* comparison *)
  | (Compare ty, (a, (b, rest))) ->
      logged_return
        ( ( Script_int.of_int @@ Script_ir_translator.compare_comparable ty a b,
            rest ),
          ctxt )
  (* comparators *)
  | (Eq, (cmpres, rest)) ->
      let cmpres = Script_int.compare cmpres Script_int.zero in
      let cmpres = Compare.Int.(cmpres = 0) in
      logged_return ((cmpres, rest), ctxt)
  | (Neq, (cmpres, rest)) ->
      let cmpres = Script_int.compare cmpres Script_int.zero in
      let cmpres = Compare.Int.(cmpres <> 0) in
      logged_return ((cmpres, rest), ctxt)
  | (Lt, (cmpres, rest)) ->
      let cmpres = Script_int.compare cmpres Script_int.zero in
      let cmpres = Compare.Int.(cmpres < 0) in
      logged_return ((cmpres, rest), ctxt)
  | (Le, (cmpres, rest)) ->
      let cmpres = Script_int.compare cmpres Script_int.zero in
      let cmpres = Compare.Int.(cmpres <= 0) in
      logged_return ((cmpres, rest), ctxt)
  | (Gt, (cmpres, rest)) ->
      let cmpres = Script_int.compare cmpres Script_int.zero in
      let cmpres = Compare.Int.(cmpres > 0) in
      logged_return ((cmpres, rest), ctxt)
  | (Ge, (cmpres, rest)) ->
      let cmpres = Script_int.compare cmpres Script_int.zero in
      let cmpres = Compare.Int.(cmpres >= 0) in
      logged_return ((cmpres, rest), ctxt)
  (* packing *)
  | (Pack t, (value, rest)) ->
      Script_ir_translator.pack_data ctxt t value
      >>=? fun (bytes, ctxt) -> logged_return ((bytes, rest), ctxt)
  | (Unpack t, (bytes, rest)) ->
      Gas.check_enough ctxt (Script.serialized_cost bytes)
      >>?= fun () ->
      if
        Compare.Int.(Bytes.length bytes >= 1)
        && Compare.Int.(TzEndian.get_uint8 bytes 0 = 0x05)
      then
        let bytes = Bytes.sub bytes 1 (Bytes.length bytes - 1) in
        match Data_encoding.Binary.of_bytes Script.expr_encoding bytes with
        | None ->
            Gas.consume ctxt (Interp_costs.unpack_failed bytes)
            >>?= fun ctxt -> logged_return ((None, rest), ctxt)
        | Some expr -> (
            Gas.consume ctxt (Script.deserialized_cost expr)
            >>?= fun ctxt ->
            parse_data ctxt ~legacy:false t (Micheline.root expr)
            >>= function
            | Ok (value, ctxt) ->
                logged_return ((Some value, rest), ctxt)
            | Error _ignored ->
                Gas.consume ctxt (Interp_costs.unpack_failed bytes)
                >>?= fun ctxt -> logged_return ((None, rest), ctxt) )
      else logged_return ((None, rest), ctxt)
  (* protocol *)
  | (Address, ((_, address), rest)) ->
      logged_return ((address, rest), ctxt)
  | (Contract (t, entrypoint), (contract, rest)) -> (
    match (contract, entrypoint) with
    | ((contract, "default"), entrypoint) | ((contract, entrypoint), "default")
      ->
        Script_ir_translator.parse_contract_for_script
          ~legacy:false
          ctxt
          loc
          t
          contract
          ~entrypoint
        >>=? fun (ctxt, maybe_contract) ->
        logged_return ((maybe_contract, rest), ctxt)
    | _ ->
        logged_return ((None, rest), ctxt) )
  (* operations *)
  | (Transfer_tokens, (p, (amount, ((tp, (destination, entrypoint)), rest))))
    ->
      collect_lazy_storage ctxt tp p
      >>?= fun (to_duplicate, ctxt) ->
      let to_update = no_lazy_storage_id in
      extract_lazy_storage_diff
        ctxt
        Optimized
        tp
        p
        ~to_duplicate
        ~to_update
        ~temporary:true
      >>=? fun (p, lazy_storage_diff, ctxt) ->
      unparse_data ctxt Optimized tp p
      >>=? fun (p, ctxt) ->
      let operation =
        Transaction
          {
            amount;
            destination;
            entrypoint;
            parameters = Script.lazy_expr (Micheline.strip_locations p);
          }
      in
      fresh_internal_nonce ctxt
      >>?= fun (ctxt, nonce) ->
      logged_return
        ( ( ( Internal_manager_operation
                {source = step_constants.self; operation; nonce},
              lazy_storage_diff ),
            rest ),
          ctxt )
  | (Implicit_account, (key, rest)) ->
      let contract = Contract.implicit_contract key in
      logged_return (((Unit_t None, (contract, "default")), rest), ctxt)
  | ( Create_contract_legacy
        (storage_type, param_type, Lam (_, code), root_name),
      (* Removed the instruction's arguments manager, spendable and delegatable *)
    (delegate, (credit, (init, rest))) ) ->
      unparse_ty ctxt param_type
      >>?= fun (unparsed_param_type, ctxt) ->
      let unparsed_param_type =
        Script_ir_translator.add_field_annot root_name None unparsed_param_type
      in
      unparse_ty ctxt storage_type
      >>?= fun (unparsed_storage_type, ctxt) ->
      let code =
        Micheline.strip_locations
          (Seq
             ( 0,
               [ Prim (0, K_parameter, [unparsed_param_type], []);
                 Prim (0, K_storage, [unparsed_storage_type], []);
                 Prim (0, K_code, [code], []) ] ))
      in
      collect_lazy_storage ctxt storage_type init
      >>?= fun (to_duplicate, ctxt) ->
      let to_update = no_lazy_storage_id in
      extract_lazy_storage_diff
        ctxt
        Optimized
        storage_type
        init
        ~to_duplicate
        ~to_update
        ~temporary:true
      >>=? fun (init, lazy_storage_diff, ctxt) ->
      unparse_data ctxt Optimized storage_type init
      >>=? fun (storage, ctxt) ->
      let storage = Micheline.strip_locations storage in
      Contract.fresh_contract_from_current_nonce ctxt
      >>?= fun (ctxt, contract) ->
      let operation =
        Origination_legacy
          {
            credit;
            delegate;
            preorigination = Some contract;
            script =
              {
                code = Script.lazy_expr code;
                storage = Script.lazy_expr storage;
              };
          }
      in
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      logged_return
        ( ( ( Internal_manager_operation
                {source = step_constants.self; operation; nonce},
              lazy_storage_diff ),
            ((contract, "default"), rest) ),
          ctxt )
  | ( Create_contract (storage_type, param_type, Lam (_, code), root_name),
      (* Changed the type of delegate from [public_key_hash option] to
        [baker_hash option] *)
    (delegate, (credit, (init, rest))) ) ->
      unparse_ty ctxt param_type
      >>?= fun (unparsed_param_type, ctxt) ->
      let unparsed_param_type =
        Script_ir_translator.add_field_annot root_name None unparsed_param_type
      in
      unparse_ty ctxt storage_type
      >>?= fun (unparsed_storage_type, ctxt) ->
      let code =
        Micheline.strip_locations
          (Seq
             ( 0,
               [ Prim (0, K_parameter, [unparsed_param_type], []);
                 Prim (0, K_storage, [unparsed_storage_type], []);
                 Prim (0, K_code, [code], []) ] ))
      in
      collect_lazy_storage ctxt storage_type init
      >>?= fun (to_duplicate, ctxt) ->
      let to_update = no_lazy_storage_id in
      extract_lazy_storage_diff
        ctxt
        Optimized
        storage_type
        init
        ~to_duplicate
        ~to_update
        ~temporary:true
      >>=? fun (init, lazy_storage_diff, ctxt) ->
      unparse_data ctxt Optimized storage_type init
      >>=? fun (storage, ctxt) ->
      let storage = Micheline.strip_locations storage in
      Contract.fresh_contract_from_current_nonce ctxt
      >>?= fun (ctxt, contract) ->
      let operation =
        Origination
          {
            credit;
            delegate;
            preorigination = Some contract;
            script =
              {
                code = Script.lazy_expr code;
                storage = Script.lazy_expr storage;
              };
          }
      in
      fresh_internal_nonce ctxt
      >>?= fun (ctxt, nonce) ->
      logged_return
        ( ( ( Internal_manager_operation
                {source = step_constants.self; operation; nonce},
              lazy_storage_diff ),
            ((contract, "default"), rest) ),
          ctxt )
  | (Set_delegate_legacy, (delegate, rest)) ->
      let operation = Delegation_legacy delegate in
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      logged_return
        ( ( ( Internal_manager_operation
                {source = step_constants.self; operation; nonce},
              None ),
            rest ),
          ctxt )
  | (Set_delegate, (delegate, rest)) ->
      (* Changed the type of delegate from [public_key_hash option] to
        [baker_hash option] *)
      let operation = Delegation delegate in
      fresh_internal_nonce ctxt
      >>?= fun (ctxt, nonce) ->
      logged_return
        ( ( ( Internal_manager_operation
                {source = step_constants.self; operation; nonce},
              None ),
            rest ),
          ctxt )
  (* baker operations *)
  | (Submit_proposals, (proposals, rest)) ->
      is_self_baker
      >>=? fun baker ->
      let period = Level.(current ctxt).voting_period in
      let operation =
        Baker_proposals {period; proposals = proposals.elements}
      in
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      logged_return
        ((Internal_baker_operation {baker; operation; nonce}, rest), ctxt)
  | (Submit_ballot, (proposal, (yays, (nays, (passes, rest))))) ->
      is_self_baker
      >>=? fun baker ->
      let period = Level.(current ctxt).voting_period in
      let convert_vote v =
        match Script_int.to_int v with
        | None ->
            Log.get_log () >>=? fun log -> fail (Overflow (loc, log))
        | Some vote ->
            return vote
      in
      convert_vote yays
      >>=? fun yays_per_roll ->
      convert_vote nays
      >>=? fun nays_per_roll ->
      convert_vote passes
      >>=? fun passes_per_roll ->
      let ballot = Vote.{yays_per_roll; nays_per_roll; passes_per_roll} in
      let operation = Baker_ballot {period; proposal; ballot} in
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      logged_return
        ((Internal_baker_operation {baker; operation; nonce}, rest), ctxt)
  | (Set_baker_active, (active, rest)) ->
      is_self_baker
      >>=? fun baker ->
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      let operation : _ Alpha_context.baker_operation =
        Set_baker_active active
      in
      logged_return
        ((Internal_baker_operation {baker; operation; nonce}, rest), ctxt)
  | (Toggle_baker_delegations, (accept, rest)) ->
      is_self_baker
      >>=? fun baker ->
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      let operation : _ Alpha_context.baker_operation =
        Toggle_baker_delegations accept
      in
      logged_return
        ((Internal_baker_operation {baker; operation; nonce}, rest), ctxt)
  | (Set_baker_consensus_key, (key, rest)) ->
      is_self_baker
      >>=? fun baker ->
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      let operation : _ Alpha_context.baker_operation =
        Set_baker_consensus_key key
      in
      logged_return
        ((Internal_baker_operation {baker; operation; nonce}, rest), ctxt)
  | (Set_baker_pvss_key, (key, rest)) ->
      is_self_baker
      >>=? fun baker ->
      Lwt.return (fresh_internal_nonce ctxt)
      >>=? fun (ctxt, nonce) ->
      let operation : _ Alpha_context.baker_operation =
        Set_baker_pvss_key key
      in
      logged_return
        ((Internal_baker_operation {baker; operation; nonce}, rest), ctxt)
  | (Balance, rest) ->
      Contract.get_balance ctxt step_constants.self
      >>=? fun balance -> logged_return ((balance, rest), ctxt)
  | (Level, rest) ->
      let level =
        (Level.current ctxt).level |> Raw_level.to_int32 |> Script_int.of_int32
        |> Script_int.abs
      in
      logged_return ((level, rest), ctxt)
  | (Now, rest) ->
      let now = Script_timestamp.now ctxt in
      logged_return ((now, rest), ctxt)
  | (Check_signature, (key, (signature, (message, rest)))) ->
      let res = Signature.check key signature message in
      logged_return ((res, rest), ctxt)
  | (Hash_key, (key, rest)) ->
      logged_return ((Signature.Public_key.hash key, rest), ctxt)
  | (Blake2b, (bytes, rest)) ->
      let hash = Raw_hashes.blake2b bytes in
      logged_return ((hash, rest), ctxt)
  | (Sha256, (bytes, rest)) ->
      let hash = Raw_hashes.sha256 bytes in
      logged_return ((hash, rest), ctxt)
  | (Sha512, (bytes, rest)) ->
      let hash = Raw_hashes.sha512 bytes in
      logged_return ((hash, rest), ctxt)
  | (Source, rest) ->
      logged_return (((step_constants.payer, "default"), rest), ctxt)
  | (Sender, rest) ->
      logged_return (((step_constants.source, "default"), rest), ctxt)
  | (Self (t, entrypoint), rest) ->
      logged_return (((t, (step_constants.self, entrypoint)), rest), ctxt)
  | (Self_address, rest) ->
      logged_return (((step_constants.self, "default"), rest), ctxt)
  | (Amount, rest) ->
      logged_return ((step_constants.amount, rest), ctxt)
  | (Dig (_n, n'), stack) ->
      interp_stack_prefix_preserving_operation
        (fun (v, rest) -> return (rest, v))
        n'
        stack
      >>=? fun (aft, x) -> logged_return ((x, aft), ctxt)
  | (Dug (_n, n'), (v, rest)) ->
      interp_stack_prefix_preserving_operation
        (fun stk -> return ((v, stk), ()))
        n'
        rest
      >>=? fun (aft, ()) -> logged_return (aft, ctxt)
  | (Dipn (_n, n', b), stack) ->
      interp_stack_prefix_preserving_operation
        (fun stk -> step logger ctxt step_constants b stk)
        n'
        stack
      >>=? fun (aft, ctxt') -> logged_return (aft, ctxt')
  | (Dropn (_n, n'), stack) ->
      interp_stack_prefix_preserving_operation
        (fun stk -> return (stk, stk))
        n'
        stack
      >>=? fun (_, rest) -> logged_return (rest, ctxt)
  | (Sapling_empty_state, rest) ->
      logged_return ((Sapling.empty_state ~memo_size:0 (), rest), ctxt)
  | (Sapling_verify_update, (transaction, (state, rest))) -> (
      let address = Contract.to_b58check step_constants.self in
      let chain_id = Chain_id.to_b58check step_constants.chain_id in
      let anti_replay = address ^ chain_id in
      Sapling.verify_update ctxt state transaction anti_replay
      >>=? fun (ctxt, balance_state_opt) ->
      match balance_state_opt with
      | Some (balance, state) ->
          logged_return
            ((Some (Script_int.of_int64 balance, state), rest), ctxt)
      | None ->
          logged_return ((None, rest), ctxt) )
  | (ChainId, rest) ->
      logged_return ((step_constants.chain_id, rest), ctxt)
  | (Never, (_, _)) ->
      .
  | (Voting_power, (baker_hash, rest)) ->
      Vote.get_voting_power ctxt baker_hash
      >>=? fun (ctxt, rolls) ->
      logged_return ((Script_int.(abs (of_int32 rolls)), rest), ctxt)
  | (Total_voting_power, rest) ->
      Vote.get_total_voting_power ctxt
      >>=? fun (ctxt, rolls) ->
      logged_return ((Script_int.(abs (of_int32 rolls)), rest), ctxt)
  | (Keccak, (bytes, rest)) ->
      let hash = Raw_hashes.keccak256 bytes in
      logged_return ((hash, rest), ctxt)
  | (Sha3, (bytes, rest)) ->
      let hash = Raw_hashes.sha3_256 bytes in
      logged_return ((hash, rest), ctxt)
  | (Add_bls12_381_g1, (x, (y, rest))) ->
      logged_return ((Bls12_381.G1.add x y, rest), ctxt)
  | (Add_bls12_381_g2, (x, (y, rest))) ->
      logged_return ((Bls12_381.G2.add x y, rest), ctxt)
  | (Add_bls12_381_fr, (x, (y, rest))) ->
      logged_return ((Bls12_381.Fr.add x y, rest), ctxt)
  | (Mul_bls12_381_g1, (x, (y, rest))) ->
      logged_return ((Bls12_381.G1.mul x y, rest), ctxt)
  | (Mul_bls12_381_g2, (x, (y, rest))) ->
      logged_return ((Bls12_381.G2.mul x y, rest), ctxt)
  | (Mul_bls12_381_fr, (x, (y, rest))) ->
      logged_return ((Bls12_381.Fr.mul x y, rest), ctxt)
  | (Neg_bls12_381_g1, (x, rest)) ->
      logged_return ((Bls12_381.G1.negate x, rest), ctxt)
  | (Neg_bls12_381_g2, (x, rest)) ->
      logged_return ((Bls12_381.G2.negate x, rest), ctxt)
  | (Neg_bls12_381_fr, (x, rest)) ->
      logged_return ((Bls12_381.Fr.negate x, rest), ctxt)
  | (Pairing_check_bls12_381, (pairs, rest)) ->
      let check =
        match pairs.elements with
        | [] ->
            true
        | pairs ->
            Bls12_381.(
              miller_loop pairs |> final_exponentiation
              |> Option.map Gt.(eq one)
              |> Option.value ~default:false)
      in
      logged_return ((check, rest), ctxt)

and interp :
    type p r.
    logger ->
    context ->
    step_constants ->
    (p, r) lambda ->
    p ->
    (r * context) tzresult Lwt.t =
 fun logger ctxt step_constants (Lam (code, _)) arg ->
  let stack = (arg, ()) in
  let module Log = (val logger) in
  Log.log_interp ctxt code stack ;
  step logger ctxt step_constants code stack
  >|=? fun ((ret, ()), ctxt) -> (ret, ctxt)

(* ---- contract handling ---------------------------------------------------*)

type execution_result = {
  ctxt : context;
  code : Script.expr;
  storage : Script.expr;
  lazy_storage_diff : Lazy_storage.diffs option;
  operations : packed_internal_operation list;
}

let execute_with_result
    ~(f :
       'ret ->
       Lazy_storage.diffs option ->
       packed_internal_operation list * Lazy_storage.diffs option) logger ctxt
    mode step_constants ~entrypoint unparsed_code
    (parsed_script : 'ret ex_script) parameter :
    execution_result tzresult Lwt.t =
  let arg = Micheline.root parameter in
  let (Ex_script {code; arg_type; storage; storage_type; root_name}) =
    parsed_script
  in
  record_trace
    (Bad_contract_parameter step_constants.self)
    (find_entrypoint arg_type ~root_name entrypoint)
  >>?= fun (box, _) ->
  trace
    (Bad_contract_parameter step_constants.self)
    (parse_data ctxt ~legacy:false arg_type (box arg))
  >>=? fun (arg, ctxt) ->
  Script.force_decode_in_context ctxt unparsed_code
  >>?= fun (script_code, ctxt) ->
  Script_ir_translator.collect_lazy_storage ctxt arg_type arg
  >>?= fun (to_duplicate, ctxt) ->
  Script_ir_translator.collect_lazy_storage ctxt storage_type storage
  >>?= fun (to_update, ctxt) ->
  trace
    (Runtime_contract_error (step_constants.self, script_code))
    (interp logger ctxt step_constants code (arg, storage))
  >>=? fun ((output, storage), ctxt) ->
  Script_ir_translator.extract_lazy_storage_diff
    ctxt
    mode
    ~temporary:false
    ~to_duplicate
    ~to_update
    storage_type
    storage
  >>=? fun (storage, lazy_storage_diff, ctxt) ->
  trace Cannot_serialize_storage (unparse_data ctxt mode storage_type storage)
  >|=? fun (storage, ctxt) ->
  let (operations, lazy_storage_diff) = f output lazy_storage_diff in
  {
    ctxt;
    code = script_code;
    storage = Micheline.strip_locations storage;
    lazy_storage_diff;
    operations;
  }

let extract_lazy_storage_diffs op_diffs lazy_storage_diff =
  match
    List.flatten
      (List.map (Option.value ~default:[]) (op_diffs @ [lazy_storage_diff]))
  with
  | [] ->
      None
  | diff ->
      Some diff

let execute logger ctxt mode step_constants ~entrypoint script parameter :
    execution_result tzresult Lwt.t =
  parse_script ctxt script ~legacy:true
  >>=? fun (Ex_originated_script parsed_script, ctxt) ->
  let f output lazy_storage_diff =
    let (ops, op_diffs) = List.split output.elements in
    let lazy_storage_diff =
      extract_lazy_storage_diffs op_diffs lazy_storage_diff
    in
    (ops, lazy_storage_diff)
  in
  execute_with_result
    ~f
    logger
    ctxt
    mode
    step_constants
    ~entrypoint
    script.code
    (Ex_script parsed_script)
    parameter

let execute_baker logger ctxt mode step_constants ~entrypoint script parameter
    : execution_result tzresult Lwt.t =
  parse_baker_script ctxt script ~legacy:true
  >>=? fun (Ex_baker_script parsed_script, ctxt) ->
  let f (ops, baker_ops) lazy_storage_diff =
    let (ops, op_diffs) = List.split ops.elements in
    let baker_ops = baker_ops.elements in
    let lazy_storage_diff =
      extract_lazy_storage_diffs op_diffs lazy_storage_diff
    in
    (ops @ baker_ops, lazy_storage_diff)
  in
  execute_with_result
    ~f
    logger
    ctxt
    mode
    step_constants
    ~entrypoint
    script.code
    (Ex_script parsed_script)
    parameter

let trace ctxt mode step_constants ~script ~entrypoint ~parameter =
  let module Logger = Trace_logger () in
  let logger = (module Logger : STEP_LOGGER) in
  execute logger ctxt mode step_constants ~entrypoint script parameter
  >>=? fun result ->
  Logger.get_log ()
  >|=? fun trace ->
  let trace = Option.value ~default:[] trace in
  (result, trace)

let trace_baker ctxt mode step_constants ~script ~entrypoint ~parameter =
  let module Logger = Trace_logger () in
  let logger = (module Logger : STEP_LOGGER) in
  execute_baker logger ctxt mode step_constants ~entrypoint script parameter
  >>=? fun result ->
  Logger.get_log ()
  >|=? fun trace ->
  let trace = Option.value ~default:[] trace in
  (result, trace)

let execute ctxt mode step_constants ~script ~entrypoint ~parameter =
  let logger = (module No_trace : STEP_LOGGER) in
  execute logger ctxt mode step_constants ~entrypoint script parameter

let execute_baker ctxt mode step_constants ~script ~entrypoint ~parameter =
  let logger = (module No_trace : STEP_LOGGER) in
  execute_baker logger ctxt mode step_constants ~entrypoint script parameter
