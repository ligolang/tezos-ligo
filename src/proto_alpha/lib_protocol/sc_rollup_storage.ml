(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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

type error +=
  | (* `Temporary *) Sc_rollup_already_staked
  | (* `Temporary *) Sc_rollup_disputed
  | (* `Temporary *) Sc_rollup_does_not_exist of Sc_rollup_repr.t
  | (* `Temporary *) Sc_rollup_no_conflict
  | (* `Temporary *) Sc_rollup_no_stakers
  | (* `Temporary *) Sc_rollup_not_staked
  | (* `Temporary *) Sc_rollup_not_staked_on_final
  | (* `Temporary *) Sc_rollup_parent_not_final
  | (* `Temporary *) Sc_rollup_remove_final
  | (* `Temporary *) Sc_rollup_staker_backtracked
  | (* `Temporary *) Sc_rollup_too_recent
  | (* `Temporary *)
      Sc_rollup_unknown_commitment of
      Sc_rollup_repr.Commitment_hash.t

let () =
  let description = "Already staked." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_already_staked"
    ~title:"Already staked"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_already_staked -> Some () | _ -> None)
    (fun () -> Sc_rollup_already_staked) ;
  let description = "Attempted to finalize a disputed commitment." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_disputed"
    ~title:"Commitment disputed"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_disputed -> Some () | _ -> None)
    (fun () -> Sc_rollup_disputed) ;
  let description = "Attempted to use a rollup that has not been originated." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_does_not_exist"
    ~title:"Rollup does not exist"
    ~description
    ~pp:(fun ppf x ->
      Format.fprintf ppf "Rollup %a does not exist" Sc_rollup_repr.pp x)
    Data_encoding.(obj1 (req "rollup" Sc_rollup_repr.encoding))
    (function Sc_rollup_does_not_exist x -> Some x | _ -> None)
    (fun x -> Sc_rollup_does_not_exist x) ;
  let description = "No conflict." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_no_conflict"
    ~title:"No conflict"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_no_conflict -> Some () | _ -> None)
    (fun () -> Sc_rollup_no_conflict) ;
  let description = "No stakers." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_no_stakers"
    ~title:"No stakers"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_no_stakers -> Some () | _ -> None)
    (fun () -> Sc_rollup_no_stakers) ;
  (* Sc_rollup_not_staked *)
  let description = "Unknown staker." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_not_staked"
    ~title:"Unknown staker"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_not_staked -> Some () | _ -> None)
    (fun () -> Sc_rollup_not_staked) ;
  let description = "Attempted to withdraw while not staked on a final node." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_not_staked_on_final"
    ~title:"Rollup not staked on final"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_not_staked_on_final -> Some () | _ -> None)
    (fun () -> Sc_rollup_not_staked_on_final) ;
  let description = "Parent not final." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_parent_not_final"
    ~title:"Parent not final"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_parent_not_final -> Some () | _ -> None)
    (fun () -> Sc_rollup_parent_not_final) ;
  let description = "Can not remove a final commitment." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_remove_final"
    ~title:"Can not remove final"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_remove_final -> Some () | _ -> None)
    (fun () -> Sc_rollup_remove_final) ;
  let description = "Staker backtracked." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_staker_backtracked"
    ~title:"Staker backtracked"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_staker_backtracked -> Some () | _ -> None)
    (fun () -> Sc_rollup_staker_backtracked) ;
  let description =
    "Attempted to finalize a commitment before its refutation deadline."
  in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_too_recent"
    ~title:"Commitment too recent"
    ~description
    ~pp:(fun ppf () -> Format.fprintf ppf "%s" description)
    Data_encoding.empty
    (function Sc_rollup_too_recent -> Some () | _ -> None)
    (fun () -> Sc_rollup_too_recent) ;
  let description = "Unknown commitment." in
  register_error_kind
    `Temporary
    ~id:"Sc_rollup_unknown_commitment"
    ~title:"Rollup does not exist"
    ~description
    ~pp:(fun ppf x ->
      Format.fprintf
        ppf
        "Commitment %a does not exist"
        Sc_rollup_repr.Commitment_hash.pp
        x)
    Data_encoding.(
      obj1 (req "commitment" Sc_rollup_repr.Commitment_hash.encoding))
    (function Sc_rollup_unknown_commitment x -> Some x | _ -> None)
    (fun x -> Sc_rollup_unknown_commitment x) ;
  ()

(* Note: this should be replaced with Lwt_tzresult_syntax once it is available *)
let ( let* ) = ( >>=? )

module Store = Storage.Sc_rollup
module Commitment = Sc_rollup_repr.Commitment
module Commitment_hash = Sc_rollup_repr.Commitment_hash

let originate ctxt ~kind ~boot_sector =
  Raw_context.increment_origination_nonce ctxt >>?= fun (ctxt, nonce) ->
  Sc_rollup_repr.Address.from_nonce nonce >>?= fun address ->
  Storage.Sc_rollup.PVM_kind.add ctxt address kind >>= fun ctxt ->
  Storage.Sc_rollup.Boot_sector.add ctxt address boot_sector >>= fun ctxt ->
  Storage.Sc_rollup.Inbox.init ctxt address Sc_rollup_inbox.empty
  >>=? fun (ctxt, size_diff) ->
  let* (ctxt, _size) =
    Store.Last_final_commitment.init ctxt address Commitment_hash.zero
  in
  let* (ctxt, _size) = Store.Stakers_size.init ctxt address 0l in
  let addresses_size = 2 * Sc_rollup_repr.Address.size in
  let stored_kind_size = 2 (* because tag_size of kind encoding is 16bits. *) in
  let boot_sector_size =
    Data_encoding.Binary.length
      Sc_rollup_repr.PVM.boot_sector_encoding
      boot_sector
  in
  let origination_size = Constants_storage.sc_rollup_origination_size ctxt in
  let size =
    Z.of_int
      (origination_size + stored_kind_size + boot_sector_size + addresses_size
     + size_diff)
  in
  return (address, size, ctxt)

let kind ctxt address = Storage.Sc_rollup.PVM_kind.find ctxt address

let add_messages ctxt rollup messages =
  Storage.Sc_rollup.Inbox.get ctxt rollup >>=? fun (ctxt, inbox) ->
  let {Level_repr.level; _} = Raw_context.current_level ctxt in
  let inbox = Sc_rollup_inbox.add_messages messages level inbox in
  Storage.Sc_rollup.Inbox.update ctxt rollup inbox >>=? fun (ctxt, size) ->
  return (inbox, Z.of_int size, ctxt)

(** Try to consume n messages.

    Returns [Some new_inbox] if successful.
    Returns [None] if there are strictly less than [n] message available
    in the inbox. *)
let consume_n_messages ctxt rollup n =
  let* (ctxt, inbox) = Storage.Sc_rollup.Inbox.get ctxt rollup in
  match Sc_rollup_inbox.consume_n_messages n inbox with
  | None -> return (inbox, ctxt)
  | Some inbox ->
      let* (ctxt, _size) = Storage.Sc_rollup.Inbox.update ctxt rollup inbox in
      return (inbox, ctxt)

let inbox ctxt rollup =
  let* (ctxt, res) = Storage.Sc_rollup.Inbox.get ctxt rollup in
  return (res, ctxt)

let last_final_commitment ctxt rollup =
  let* (ctxt, res) = Store.Last_final_commitment.find ctxt rollup in
  match res with
  | None -> fail (Sc_rollup_does_not_exist rollup)
  | Some lfc -> return (lfc, ctxt)

let get_commitment ctxt rollup commitment =
  let* (ctxt, res) = Store.Commitments.find (ctxt, rollup) commitment in
  match res with
  | None -> fail (Sc_rollup_unknown_commitment commitment)
  | Some commitment -> return (commitment, ctxt)

let get_predecessor ctxt rollup node =
  let* (commitment, ctxt) = get_commitment ctxt rollup node in
  return (commitment.predecessor, ctxt)

let find_staker ctxt rollup staker =
  let* (ctxt, res) = Store.Stakers.find (ctxt, rollup) staker in
  match res with
  | None -> fail Sc_rollup_not_staked
  | Some branch -> return (branch, ctxt)

let modify_staker_size ctxt rollup f =
  let* (ctxt, maybe_count) = Store.Stakers_size.find ctxt rollup in
  let count = Option.value ~default:0l maybe_count in
  let* (ctxt, _, _) = Store.Stakers_size.add ctxt rollup (f count) in
  return ctxt

let get_commitment_stake_count ctxt rollup node =
  let* (ctxt, maybe_staked_on_commitment) =
    Store.Commitment_stake_count.find (ctxt, rollup) node
  in
  return (Option.value ~default:0l maybe_staked_on_commitment, ctxt)

let modify_stake_count ctxt rollup node f =
  let* (count, ctxt) = get_commitment_stake_count ctxt rollup node in
  let new_count = f count in
  let* (ctxt, _, _) =
    Store.Commitment_stake_count.add (ctxt, rollup) node new_count
  in
  return (new_count, ctxt)

let set_commitment_added ctxt rollup node new_value =
  let* (ctxt, res) = Store.Commitment_added.find (ctxt, rollup) node in
  let new_value =
    match res with
    | None -> new_value
    | Some old_value -> Raw_level_repr.min old_value new_value
  in
  let* (ctxt, _, _) =
    Store.Commitment_added.add (ctxt, rollup) node new_value
  in
  return ctxt

let deallocate (ctxt : Raw_context.t) (rollup : Sc_rollup_repr.t)
    (node : Commitment_hash.t) : Raw_context.t tzresult Lwt.t =
  if Commitment_hash.(node = zero) then return ctxt
  else
    let* (ctxt, _) = Store.Commitments.remove_existing (ctxt, rollup) node in
    let* (ctxt, _) =
      Store.Commitment_added.remove_existing (ctxt, rollup) node
    in
    let* (ctxt, _) =
      Store.Commitment_stake_count.remove_existing (ctxt, rollup) node
    in
    return ctxt

let increase_stake_count ctxt rollup node =
  let* (_, ctxt) = modify_stake_count ctxt rollup node Int32.succ in
  return ctxt

let decrease_stake_count ctxt rollup node =
  let* (new_count, ctxt) = modify_stake_count ctxt rollup node Int32.pred in
  if Compare.Int32.(new_count <= 0l) then deallocate ctxt rollup node
  else return ctxt

let deposit_stake ctxt rollup staker =
  let* (lfc, ctxt) = last_final_commitment ctxt rollup in
  let* (ctxt, res) = Store.Stakers.find (ctxt, rollup) staker in
  match res with
  | None ->
      (* TODO: https://gitlab.com/tezos/tezos/-/issues/2449
         We should lock stake here, and fail if there aren't enough funds.
      *)
      let* (ctxt, _) = Store.Stakers.init (ctxt, rollup) staker lfc in
      let* ctxt = modify_staker_size ctxt rollup Int32.succ in
      return ((), ctxt)
  | Some _ -> fail Sc_rollup_already_staked

let withdraw_stake ctxt rollup staker =
  let* (lfc, ctxt) = last_final_commitment ctxt rollup in
  let* (ctxt, res) = Store.Stakers.find (ctxt, rollup) staker in
  match res with
  | None -> fail Sc_rollup_not_staked
  | Some staked_on_commitment ->
      if Sc_rollup_repr.Commitment_hash.(staked_on_commitment = lfc) then
        (* TODO: https://gitlab.com/tezos/tezos/-/issues/2449
           We should refund stake here.
        *)
        let* (ctxt, _) = Store.Stakers.remove_existing (ctxt, rollup) staker in
        let* ctxt = modify_staker_size ctxt rollup Int32.pred in
        return ((), ctxt)
      else fail Sc_rollup_not_staked_on_final

let refine_stake ctxt rollup level staker commitment =
  let* (lfc, ctxt) = last_final_commitment ctxt rollup in
  let* (staked_on, ctxt) = find_staker ctxt rollup staker in
  let new_hash = Commitment.hash commitment in
  let traverse =
    let rec go (node : Commitment_hash.t) (ctxt : Raw_context.t) =
      (* WARNING: Do NOT reorder this sequence of ifs.
         we must check for staked_on before LFC, since refining
         from the LFC to another commit is a valid operation. *)
      if Commitment_hash.(node = staked_on) then
        (* Previously staked commit found:
           Insert new commitment if not existing *)
        let* (ctxt, _, _) =
          Store.Commitments.add (ctxt, rollup) new_hash commitment
        in
        let* ctxt = set_commitment_added ctxt rollup new_hash level in
        let* (ctxt, _) = Store.Stakers.update (ctxt, rollup) staker new_hash in
        let* ctxt = increase_stake_count ctxt rollup new_hash in
        return (new_hash, ctxt) (* See WARNING above. *)
      else if Commitment_hash.(node = lfc) then
        (* We reached the LFC, but [staker] is not staked directly on it.
           Thus, we backtracked. Note that everyone is staked in indirectly on
           the LFC. *)
        fail Sc_rollup_staker_backtracked
      else
        let* (pred, ctxt) = get_predecessor ctxt rollup node in
        let* ctxt = increase_stake_count ctxt rollup node in
        (go [@ocaml.tailcall]) pred ctxt
    in
    go Sc_rollup_repr.Commitment.(commitment.predecessor) ctxt
  in
  traverse

let finalize_commitment ctxt rollup level new_lfc =
  let refutation_deadline_blocks =
    Constants_storage.sc_rollup_challenge_window ctxt
  in
  let* (old_lfc, ctxt) = last_final_commitment ctxt rollup in
  let* (new_lfc_commitment, ctxt) = get_commitment ctxt rollup new_lfc in
  let* (ctxt, new_lfc_added) =
    Store.Commitment_added.get (ctxt, rollup) new_lfc
  in
  if Commitment_hash.(new_lfc_commitment.predecessor <> old_lfc) then
    fail Sc_rollup_parent_not_final
  else
    (* get is safe, as Stakers_size is initialized on origination *)
    let* (ctxt, total_staker_count) = Store.Stakers_size.get ctxt rollup in
    if Compare.Int32.(total_staker_count <= 0l) then fail Sc_rollup_no_stakers
    else
      let* (new_lfc_stake_count, ctxt) =
        get_commitment_stake_count ctxt rollup new_lfc
      in
      if Compare.Int32.(total_staker_count <> new_lfc_stake_count) then
        fail Sc_rollup_disputed
      else if
        Raw_level_repr.(level < add new_lfc_added refutation_deadline_blocks)
      then fail Sc_rollup_too_recent
      else
        (* update LFC *)
        let* (ctxt, _) =
          Store.Last_final_commitment.update ctxt rollup new_lfc
        in
        (* At this point we know all stakers are implicitly staked
           on the new LFC, and noone is directly staked on the old LFC. We
           can safely deallocate the old LFC.
        *)
        let* ctxt = deallocate ctxt rollup old_lfc in
        let* (_inbox_res, ctxt) =
          consume_n_messages
            ctxt
            rollup
            (Int32.to_int
            @@ Sc_rollup_repr.Number_of_messages.to_int32
                 new_lfc_commitment.number_of_messages)
        in
        let* (ctxt, _size) =
          Store.Commitments.remove_existing (ctxt, rollup) new_lfc
        in
        return ((), ctxt)

module Successor_map = Map.Make (Sc_rollup_repr.Commitment_hash)

type conflict_point =
  Sc_rollup_repr.Commitment_hash.t * Sc_rollup_repr.Commitment_hash.t

type successor_map = Sc_rollup_repr.Commitment_hash.t Successor_map.t

let get_conflict_point ctxt rollup staker1 staker2 =
  let* (lfc, ctxt) = last_final_commitment ctxt rollup in
  let* (staker1_branch, ctxt) = find_staker ctxt rollup staker1 in
  let* (staker2_branch, ctxt) = find_staker ctxt rollup staker2 in
  (* Build a map from commitments on the staker1 branch to their direct
     successor on this branch. *)
  (* let rec staker1_commitments map commitment_hash *)
  let traverse_staker1 =
    let rec go (node : Commitment_hash.t) (prev_map : successor_map)
        (ctxt : Raw_context.t) =
      if Commitment_hash.(node = lfc) then return (prev_map, ctxt)
      else
        let* (pred, ctxt) = get_predecessor ctxt rollup node in
        let new_map = Successor_map.add pred node prev_map in
        (go [@ocaml.tailcall]) pred new_map ctxt
    in
    go staker1_branch Successor_map.empty ctxt
  in
  let* (staker1_succ_map, ctxt) = traverse_staker1 in
  (* Traverse from staker2.

     Assuming invariants hold, we have 3 possible outcomes:
       * _staker2_branch tup is member of staker1_successor_comp, so
         staker1 is strictly ahead of staker2
       * During traversal from staker2 we encounter _staker1_branch_tup, so
         staker2 is strictly ahead of staker1.
       * During traversal from staker2 we encounter the conflict point, which
         may be the LFC.
  *)
  if Successor_map.mem staker2_branch staker1_succ_map then
    (* staker2 is a predecessor of staker1 *)
    fail Sc_rollup_no_conflict
  else
    let traverse_staker2 =
      let rec go (node : Commitment_hash.t) (ctxt : Raw_context.t) =
        if Commitment_hash.(node = staker1_branch) then
          (* staker1 is a predecessor of staker2 *)
          fail Sc_rollup_no_conflict
        else
          let right = node in
          let* (pred, ctxt) = get_predecessor ctxt rollup node in
          match Successor_map.find pred staker1_succ_map with
          | None -> (go [@ocaml.tailcall]) pred ctxt
          | Some left -> return ((left, right), ctxt)
      in
      go staker2_branch ctxt
    in
    traverse_staker2

let remove_staker ctxt rollup staker =
  let* (lfc, ctxt) = last_final_commitment ctxt rollup in
  let* (ctxt, res) = Store.Stakers.find (ctxt, rollup) staker in
  match res with
  | None -> fail Sc_rollup_not_staked
  | Some staked_on ->
      if Commitment_hash.(staked_on = lfc) then fail Sc_rollup_remove_final
      else
        let* (ctxt, _) = Store.Stakers.remove_existing (ctxt, rollup) staker in
        let* ctxt = modify_staker_size ctxt rollup Int32.pred in
        let traverse =
          let rec go (node : Commitment_hash.t) (ctxt : Raw_context.t) =
            if Commitment_hash.(node = lfc) then return ((), ctxt)
            else
              let* (pred, ctxt) = get_predecessor ctxt rollup node in
              let* ctxt = decrease_stake_count ctxt rollup node in
              (go [@ocaml.tailcall]) pred ctxt
          in
          go staked_on ctxt
        in
        traverse
