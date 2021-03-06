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

(** Returns the proposal submitted by the most bakers.
    Returns None in case of a tie, if proposal quorum is below required
    minimum or if there are no proposals. *)
let select_winning_proposal ctxt =
  Vote.get_proposals ctxt
  >>=? fun proposals ->
  let merge proposal vote winners =
    match winners with
    | None ->
        Some ([proposal], vote)
    | Some (winners, winners_vote) as previous ->
        if Compare.Int32.(vote = winners_vote) then
          Some (proposal :: winners, winners_vote)
        else if Compare.Int32.(vote > winners_vote) then Some ([proposal], vote)
        else previous
  in
  match Protocol_hash.Map.fold merge proposals None with
  | Some ([proposal], vote) ->
      Vote.listing_size ctxt
      >>=? fun max_vote ->
      let min_proposal_quorum = Constants.min_proposal_quorum ctxt in
      let min_vote_to_pass =
        Int32.div (Int32.mul min_proposal_quorum max_vote) 100_00l
      in
      if Compare.Int32.(vote >= min_vote_to_pass) then return_some proposal
      else return_none
  | _ ->
      return_none

(* in case of a tie, let's do nothing. *)

(** A proposal is approved if it has supermajority and the participation reaches
    the current quorum.
    Supermajority means the yays are more 8/10 of casted votes.
    The participation is the ratio of all received votes, including passes, with
    respect to the number of possible votes.
    The participation EMA (exponential moving average) uses the last
    participation EMA and the current participation./
    The expected quorum is calculated using the last participation EMA, capped
    by the min/max quorum protocol constants. *)
let check_approval_and_update_participation_ema ctxt =
  Vote.get_ballots ctxt
  >>=? fun ballots ->
  Vote.listing_size ctxt
  >>=? fun rolls ->
  (* Multiply the total number of rolls by votes_per_roll *)
  return Int32.(mul rolls (of_int Constants.fixed.votes_per_roll))
  >>=? fun maximum_vote ->
  Vote.get_participation_ema ctxt
  >>=? fun participation_ema ->
  Vote.get_current_quorum ctxt
  >>=? fun expected_quorum ->
  (* Note overflows: considering a maximum of 8e8 tokens, with roll size as
     small as 1e3, there is a maximum of 8e5 rolls and thus votes.
     In 'participation' an Int64 is used because in the worst case 'all_votes is
     8e5 and after the multiplication is 8e9, making it potentially overflow a
     signed Int32 which is 2e9. *)
  let casted_votes = Int32.add ballots.yay ballots.nay in
  let all_votes = Int32.add casted_votes ballots.pass in
  let supermajority = Int32.(div (mul 8l casted_votes) 10l) in
  let participation =
    (* in centile of percentage *)
    Int64.(
      to_int32 (div (mul (of_int32 all_votes) 100_00L) (of_int32 maximum_vote)))
  in
  let outcome =
    Compare.Int32.(
      participation >= expected_quorum && ballots.yay >= supermajority)
  in
  let new_participation_ema =
    Int32.(div (add (mul 8l participation_ema) (mul 2l participation)) 10l)
  in
  Vote.set_participation_ema ctxt new_participation_ema
  >|=? fun ctxt -> (ctxt, outcome)

(** Implements the state machine of the amendment procedure.
    Note that [update_listings], that computes the vote weight of each baker,
    is run at the beginning of each voting period.
*)
let start_new_voting_period ctxt =
  Vote.get_current_period_kind ctxt
  >>=? fun kind ->
  ( match kind with
  | Proposal -> (
      select_winning_proposal ctxt
      >>=? fun proposal ->
      Vote.clear_proposals ctxt
      >>= fun ctxt ->
      match proposal with
      | None ->
          return ctxt
      | Some proposal ->
          Vote.init_current_proposal ctxt proposal
          >>=? fun ctxt -> Vote.set_current_period_kind ctxt Testing_vote )
  | Testing_vote ->
      check_approval_and_update_participation_ema ctxt
      >>=? fun (ctxt, approved) ->
      Vote.clear_ballots ctxt
      >>= fun ctxt ->
      if approved then
        let expiration =
          Time.add
            (Timestamp.current ctxt)
            (Constants.test_chain_duration ctxt)
        in
        Vote.get_current_proposal ctxt
        >>=? fun proposal ->
        fork_test_chain ctxt proposal expiration
        >>= fun ctxt -> Vote.set_current_period_kind ctxt Testing
      else
        Vote.clear_current_proposal ctxt
        >>=? fun ctxt -> Vote.set_current_period_kind ctxt Proposal
  | Testing ->
      Vote.set_current_period_kind ctxt Promotion_vote
  | Promotion_vote ->
      check_approval_and_update_participation_ema ctxt
      >>=? fun (ctxt, approved) ->
      ( if approved then Vote.set_current_period_kind ctxt Adoption
      else
        Vote.clear_current_proposal ctxt
        >>=? fun ctxt -> Vote.set_current_period_kind ctxt Proposal )
      >>=? fun ctxt -> Vote.clear_ballots ctxt >|= ok
  | Adoption ->
      Vote.get_current_proposal ctxt
      >>=? fun proposal ->
      activate ctxt proposal
      >>= fun ctxt ->
      Vote.clear_current_proposal ctxt
      >>=? fun ctxt -> Vote.set_current_period_kind ctxt Proposal )
  >>=? fun ctxt -> Vote.update_listings ctxt

type error +=
  | (* `Branch *)
      Invalid_proposal
  | Unexpected_proposal
  | Unauthorized_proposal
  | Too_many_proposals
  | Empty_proposal
  | Unexpected_ballot
  | Unauthorized_ballot

let () =
  let open Data_encoding in
  (* Invalid proposal *)
  register_error_kind
    `Branch
    ~id:"invalid_proposal"
    ~title:"Invalid proposal"
    ~description:"Ballot provided for a proposal that is not the current one."
    ~pp:(fun ppf () -> Format.fprintf ppf "Invalid proposal")
    empty
    (function Invalid_proposal -> Some () | _ -> None)
    (fun () -> Invalid_proposal) ;
  (* Unexpected proposal *)
  register_error_kind
    `Branch
    ~id:"unexpected_proposal"
    ~title:"Unexpected proposal"
    ~description:"Proposal recorded outside of a proposal period."
    ~pp:(fun ppf () -> Format.fprintf ppf "Unexpected proposal")
    empty
    (function Unexpected_proposal -> Some () | _ -> None)
    (fun () -> Unexpected_proposal) ;
  (* Unauthorized proposal *)
  register_error_kind
    `Branch
    ~id:"unauthorized_proposal"
    ~title:"Unauthorized proposal"
    ~description:
      "The baker provided for the proposal is not in the voting listings."
    ~pp:(fun ppf () -> Format.fprintf ppf "Unauthorized proposal")
    empty
    (function Unauthorized_proposal -> Some () | _ -> None)
    (fun () -> Unauthorized_proposal) ;
  (* Unexpected ballot *)
  register_error_kind
    `Branch
    ~id:"unexpected_ballot"
    ~title:"Unexpected ballot"
    ~description:"Ballot recorded outside of a voting period."
    ~pp:(fun ppf () -> Format.fprintf ppf "Unexpected ballot")
    empty
    (function Unexpected_ballot -> Some () | _ -> None)
    (fun () -> Unexpected_ballot) ;
  (* Unauthorized ballot *)
  register_error_kind
    `Branch
    ~id:"unauthorized_ballot"
    ~title:"Unauthorized ballot"
    ~description:
      "The baker provided for the ballot is not in the voting listings."
    ~pp:(fun ppf () -> Format.fprintf ppf "Unauthorized ballot")
    empty
    (function Unauthorized_ballot -> Some () | _ -> None)
    (fun () -> Unauthorized_ballot) ;
  (* Too many proposals *)
  register_error_kind
    `Branch
    ~id:"too_many_proposals"
    ~title:"Too many proposals"
    ~description:"The baker reached the maximum number of allowed proposals."
    ~pp:(fun ppf () -> Format.fprintf ppf "Too many proposals")
    empty
    (function Too_many_proposals -> Some () | _ -> None)
    (fun () -> Too_many_proposals) ;
  (* Empty proposal *)
  register_error_kind
    `Branch
    ~id:"empty_proposal"
    ~title:"Empty proposal"
    ~description:"Proposal lists cannot be empty."
    ~pp:(fun ppf () -> Format.fprintf ppf "Empty proposal")
    empty
    (function Empty_proposal -> Some () | _ -> None)
    (fun () -> Empty_proposal)

(* @return [true] if [List.length l] > [n] w/o computing length *)
let rec longer_than l n =
  if Compare.Int.(n < 0) then assert false
  else
    match l with
    | [] ->
        false
    | _ :: rest ->
        if Compare.Int.(n = 0) then true
        else (* n > 0 *)
          longer_than rest (n - 1)

let record_proposals ctxt baker_hash proposals =
  (match proposals with [] -> error Empty_proposal | _ :: _ -> ok_unit)
  >>?= fun () ->
  Vote.get_current_period_kind ctxt
  >>=? function
  | Proposal ->
      let baker = Contract.baker_contract baker_hash in
      Vote.in_listings ctxt baker
      >>= fun in_listings ->
      if in_listings then
        Vote.recorded_proposal_count_for_baker ctxt baker_hash
        >>=? fun count ->
        error_when
          (longer_than proposals (Constants.max_proposals_per_delegate - count))
          Too_many_proposals
        >>?= fun () ->
        fold_left_s
          (fun ctxt proposal -> Vote.record_proposal ctxt proposal baker_hash)
          ctxt
          proposals
      else fail Unauthorized_proposal
  | Testing_vote | Testing | Promotion_vote | Adoption ->
      fail Unexpected_proposal

let record_ballot ctxt contract proposal ballot =
  Vote.get_current_period_kind ctxt
  >>=? function
  | Testing_vote | Promotion_vote ->
      Vote.get_current_proposal ctxt
      >>=? fun current_proposal ->
      error_unless
        (Protocol_hash.equal proposal current_proposal)
        Invalid_proposal
      >>?= fun () ->
      Vote.has_recorded_ballot ctxt contract
      >>= fun has_ballot ->
      error_when has_ballot Unauthorized_ballot
      >>?= fun () -> Vote.record_ballot ctxt contract ballot
  | Testing | Proposal | Adoption ->
      fail Unexpected_ballot

let last_of_a_voting_period ctxt l =
  Compare.Int32.(
    Int32.succ l.Level.voting_period_position
    = Constants.blocks_per_voting_period ctxt)

let may_start_new_voting_period ctxt =
  let level = Level.current ctxt in
  if last_of_a_voting_period ctxt level then start_new_voting_period ctxt
  else return ctxt
