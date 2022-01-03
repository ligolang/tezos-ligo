(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2021 Oxhead Alpha <info@oxheadalpha.com>                    *)
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

let just_ctxt (ctxt, _, _) = ctxt

open Tx_rollup_commitment_repr

let get_next_level ctxt tx_rollup level =
  Tx_rollup_inbox_storage.get_adjacent_levels ctxt level tx_rollup
  >|=? fun (ctxt, _, successor_level) -> (ctxt, successor_level)

let get_prev_level ctxt tx_rollup level =
  Tx_rollup_inbox_storage.get_adjacent_levels ctxt level tx_rollup
  >|=? fun (ctxt, predecessor_level, _) -> (ctxt, predecessor_level)

(* This indicates a programming error. *)
type error += (*`Temporary*) Commitment_bond_negative of int

let adjust_commitment_bond ctxt tx_rollup pkh delta =
  let bond_key = (tx_rollup, pkh) in
  Storage.Tx_rollup.Commitment_bond.find ctxt bond_key
  >>=? fun (ctxt, commitment) ->
  let count =
    match commitment with Some count -> count + delta | None -> delta
  in
  fail_when Compare.Int.(count < 0) (Commitment_bond_negative count)
  >>=? fun () ->
  Storage.Tx_rollup.Commitment_bond.add ctxt bond_key count >|=? just_ctxt

let remove_bond :
    Raw_context.t ->
    Tx_rollup_repr.t ->
    Signature.public_key_hash ->
    Raw_context.t tzresult Lwt.t =
 fun ctxt tx_rollup contract ->
  let bond_key = (tx_rollup, contract) in
  Storage.Tx_rollup.Commitment_bond.find ctxt bond_key >>=? fun (ctxt, bond) ->
  match bond with
  | None -> fail (Bond_does_not_exist contract)
  | Some 0 ->
      Storage.Tx_rollup.Commitment_bond.remove ctxt bond_key >|=? just_ctxt
  | Some _ -> fail (Bond_in_use contract)

let check_commitment_predecessor_hash ctxt tx_rollup
    (commitment : Tx_rollup_commitment_repr.t) =
  let level = commitment.level in
  (* Check that level has the correct predecessor *)
  get_prev_level ctxt tx_rollup level >>=? fun (ctxt, predecessor_level) ->
  match (predecessor_level, commitment.predecessor) with
  | (None, None) -> return ctxt
  | (Some _, None) | (None, Some _) -> fail Wrong_commitment_predecessor_level
  | (Some predecessor_level, Some hash) ->
      (* The predecessor level must include this commitment*)
      Storage.Tx_rollup.Commitment.get ctxt (predecessor_level, tx_rollup)
      >>=? fun (ctxt, predecesor_commitment) ->
      let expected_hash =
        Tx_rollup_commitment_repr.hash predecesor_commitment.commitment
      in
      fail_unless
        Tx_rollup_commitment_repr.Commitment_hash.(hash = expected_hash)
        Missing_commitment_predecessor
      >>=? fun () -> return ctxt

let add_commitment ctxt tx_rollup pkh (commitment : Tx_rollup_commitment_repr.t)
    =
  let key = (commitment.level, tx_rollup) in
  Tx_rollup_inbox_storage.get ctxt ~level:(`Level commitment.level) tx_rollup
  >>=? fun (ctxt, inbox) ->
  let expected_len = List.length inbox.contents in
  let actual_len = List.length commitment.batches in
  fail_unless Compare.Int.(expected_len = actual_len) Wrong_batch_count
  >>=? fun () ->
  Storage.Tx_rollup.Commitment.mem ctxt key >>=? fun (ctxt, old_commitment) ->
  fail_when old_commitment (Level_already_has_commitment commitment.level)
  >>=? fun () ->
  check_commitment_predecessor_hash ctxt tx_rollup commitment >>=? fun ctxt ->
  let current_level = (Raw_context.current_level ctxt).level in
  let submitted : Tx_rollup_commitment_repr.Submitted_commitment.t =
    {commitment; committer = pkh; submitted_at = current_level}
  in
  Storage.Tx_rollup.Commitment.add ctxt key submitted >>=? fun (ctxt, _, _) ->
  adjust_commitment_bond ctxt tx_rollup pkh 1

let retire_rollup_level :
    Raw_context.t ->
    Tx_rollup_repr.t ->
    Raw_level_repr.t ->
    Raw_level_repr.t ->
    (Raw_context.t * [> `No_commitment | `Commitment_too_late | `Retired])
    tzresult
    Lwt.t =
 fun ctxt tx_rollup level last_level_to_finalize ->
  let key = (level, tx_rollup) in
  Storage.Tx_rollup.Commitment.find ctxt key >>=? function
  | (_, None) -> return (ctxt, `No_commitment)
  | (ctxt, Some accepted) ->
      if Raw_level_repr.(accepted.submitted_at > last_level_to_finalize) then
        return (ctxt, `Commitment_too_late)
      else
        adjust_commitment_bond ctxt tx_rollup accepted.committer (-1)
        >>=? fun ctxt -> return (ctxt, `Retired)

let get_commitment :
    Raw_context.t ->
    Tx_rollup_repr.t ->
    Raw_level_repr.t ->
    (Raw_context.t * Tx_rollup_commitment_repr.Submitted_commitment.t option)
    tzresult
    Lwt.t =
 fun ctxt tx_rollup level ->
  Storage.Tx_rollup.State.find ctxt tx_rollup >>=? fun (ctxt, state) ->
  match state with
  | None -> fail @@ Tx_rollup_state_storage.Tx_rollup_does_not_exist tx_rollup
  | Some _ -> Storage.Tx_rollup.Commitment.find ctxt (level, tx_rollup)

let pending_bonded_commitments :
    Raw_context.t ->
    Tx_rollup_repr.t ->
    Signature.public_key_hash ->
    (Raw_context.t * int) tzresult Lwt.t =
 fun ctxt tx_rollup pkh ->
  Storage.Tx_rollup.Commitment_bond.find ctxt (tx_rollup, pkh)
  >|=? fun (ctxt, pending) -> (ctxt, Option.value ~default:0 pending)

let has_bond :
    Raw_context.t ->
    Tx_rollup_repr.t ->
    Signature.public_key_hash ->
    (Raw_context.t * bool) tzresult Lwt.t =
 fun ctxt tx_rollup pkh ->
  Storage.Tx_rollup.Commitment_bond.find ctxt (tx_rollup, pkh)
  >|=? fun (ctxt, pending) -> (ctxt, Option.is_some pending)

let finalize_pending_commitments ctxt tx_rollup last_level_to_finalize =
  Tx_rollup_state_storage.get ctxt tx_rollup >>=? fun (ctxt, state) ->
  let first_unfinalized_level =
    Tx_rollup_state_repr.first_unfinalized_level state
  in
  match first_unfinalized_level with
  | None -> return ctxt
  | Some first_unfinalized_level ->
      let rec finalize_level ctxt level top finalized_count =
        if Raw_level_repr.(level > top) then
          return (ctxt, finalized_count, Some level)
        else
          retire_rollup_level ctxt tx_rollup level last_level_to_finalize
          >>=? fun (ctxt, finalized) ->
          match finalized with
          | `Retired -> (
              get_next_level ctxt tx_rollup level >>=? fun (ctxt, next_level) ->
              match next_level with
              | None -> return (ctxt, 0, None)
              | Some next_level ->
                  (finalize_level [@tailcall])
                    ctxt
                    next_level
                    top
                    (finalized_count + 1))
          | _ -> return (ctxt, finalized_count, Some level)
      in
      finalize_level ctxt first_unfinalized_level last_level_to_finalize 0
      >>=? fun (ctxt, finalized_count, first_unfinalized_level) ->
      let new_state =
        Tx_rollup_state_repr.update_after_finalize
          state
          first_unfinalized_level
          finalized_count
      in
      Storage.Tx_rollup.State.add ctxt tx_rollup new_state
      >>=? fun (ctxt, _, _) -> return ctxt
