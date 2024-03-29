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

open Protocol
open Alpha_context

(* missing stuff in Vote *)
let ballots_zero = Vote.{yay = 0l; nay = 0l; pass = 0l}

let ballots_equal b1 b2 =
  Vote.(b1.yay = b2.yay && b1.nay = b2.nay && b1.pass = b2.pass)

let ballots_pp ppf v =
  Vote.(
    Format.fprintf
      ppf
      "{ yay = %ld ; nay = %ld ; pass = %ld }"
      v.yay
      v.nay
      v.pass)

(* constants and ratios used in voting:
   percent_mul denotes the percent multiplier
   initial_participation is 7000 that is, 7/10 * percent_mul
   the participation EMA ratio pr_ema_weight / den = 7 / 10
   the participation ratio pr_num / den = 2 / 10
   note: we use the same denominator for both participation EMA and participation rate.
   supermajority rate is s_num / s_den = 8 / 10 *)
let percent_mul = 100_00

let den = 10

let initial_participation_num = 7

let initial_participation = initial_participation_num * percent_mul / den

let pr_ema_weight = 8

let pr_num = den - pr_ema_weight

let s_num = 8

let s_den = 10

let qr_min_num = 2

let qr_max_num = 7

let expected_qr_num participation_ema =
  let participation_ema = Int32.to_int participation_ema in
  let participation_ema = participation_ema * den / percent_mul in
  Float.(
    of_int qr_min_num
    +. of_int participation_ema
       *. (of_int qr_max_num -. of_int qr_min_num)
       /. of_int den)

(* Protocol_hash.zero is "PrihK96nBAFSxVL1GLJTVhu9YnzkMFiBeuJRPA8NwuZVZCE1L6i" *)
let protos =
  Array.map
    (fun s -> Protocol_hash.of_b58check_exn s)
    [| "ProtoALphaALphaALphaALphaALphaALphaALpha61322gcLUGH";
       "ProtoALphaALphaALphaALphaALphaALphaALphabc2a7ebx6WB";
       "ProtoALphaALphaALphaALphaALphaALphaALpha84efbeiF6cm";
       "ProtoALphaALphaALphaALphaALphaALphaALpha91249Z65tWS";
       "ProtoALphaALphaALphaALphaALphaALphaALpha537f5h25LnN";
       "ProtoALphaALphaALphaALphaALphaALphaALpha5c8fefgDYkr";
       "ProtoALphaALphaALphaALphaALphaALphaALpha3f31feSSarC";
       "ProtoALphaALphaALphaALphaALphaALphaALphabe31ahnkxSC";
       "ProtoALphaALphaALphaALphaALphaALphaALphabab3bgRb7zQ";
       "ProtoALphaALphaALphaALphaALphaALphaALphaf8d39cctbpk";
       "ProtoALphaALphaALphaALphaALphaALphaALpha3b981byuYxD";
       "ProtoALphaALphaALphaALphaALphaALphaALphaa116bccYowi";
       "ProtoALphaALphaALphaALphaALphaALphaALphacce68eHqboj";
       "ProtoALphaALphaALphaALphaALphaALphaALpha225c7YrWwR7";
       "ProtoALphaALphaALphaALphaALphaALphaALpha58743cJL6FG";
       "ProtoALphaALphaALphaALphaALphaALphaALphac91bcdvmJFR";
       "ProtoALphaALphaALphaALphaALphaALphaALpha1faaadhV7oW";
       "ProtoALphaALphaALphaALphaALphaALphaALpha98232gD94QJ";
       "ProtoALphaALphaALphaALphaALphaALphaALpha9d1d8cijvAh";
       "ProtoALphaALphaALphaALphaALphaALphaALphaeec52dKF6Gx";
       "ProtoALphaALphaALphaALphaALphaALphaALpha841f2cQqajX" |]

(** helper functions *)
let period_kind_to_string kind =
  Data_encoding.Json.construct Alpha_context.Voting_period.kind_encoding kind
  |> Data_encoding.Json.to_string

let assert_period_kind expected b loc =
  Context.Vote.get_current_period_kind (B b)
  >>=? fun kind ->
  if Stdlib.(expected = kind) then return_unit
  else
    failwith
      "%s - Unexpected period kind - expected %s, got %s"
      loc
      (period_kind_to_string expected)
      (period_kind_to_string kind)

let mk_contracts_from_pkh pkh_list =
  List.map Alpha_context.Contract.implicit_contract pkh_list

let filter_bakers_from_listings =
  List.filter_map (fun (voter, rolls) ->
      Contract.is_baker voter
      |> Option.map (fun baker_hash -> (baker_hash, rolls)))

(* get the list of delegates and the list of their rolls from listings *)
let get_bakers_and_rolls_from_listings b =
  Context.Vote.get_listings (B b)
  >|=? filter_bakers_from_listings
  >|=? fun l -> (List.map fst l, List.map snd l)

(* compute the rolls of each baker *)
let get_rolls b bakers loc =
  Context.Vote.get_listings (B b)
  >|=? filter_bakers_from_listings
  >>=? fun l ->
  map_s
    (fun baker ->
      match List.find_opt (fun (b, _) -> b = baker) l with
      | None ->
          failwith "%s - Missing baker" loc
      | Some (_, rolls) ->
          return rolls)
    bakers

(* Checks that the listings are populated *)
let assert_listings_not_empty b ~loc =
  Context.Vote.get_listings (B b)
  >>=? function
  | [] -> failwith "Unexpected empty listings (%s)" loc | _ -> return_unit

let test_successful_vote num_bakers () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / num_bakers)) in
  Context.init ~min_proposal_quorum num_bakers
  >>=? fun (b, contracts, _) ->
  let bootstrap = List.hd contracts in
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; _}; _} ->
  (* no ballots in proposal period *)
  Context.Vote.get_ballots (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    ballots_equal
    "Unexpected ballots"
    ballots_pp
    v
    ballots_zero
  >>=? fun () ->
  (* no ballots in proposal period *)
  Context.Vote.get_ballot_list (B b)
  >>=? (function
         | [] ->
             return_unit
         | _ ->
             failwith "%s - Unexpected ballot list" __LOC__)
  >>=? fun () ->
  (* period 0 *)
  Context.Vote.get_voting_period (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    Voting_period.equal
    "Unexpected period"
    Voting_period.pp
    v
    Voting_period.(root)
  >>=? fun () ->
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* participation EMA starts at initial_participation *)
  Context.Vote.get_participation_ema b
  >>=? fun v ->
  Assert.equal_int ~loc:__LOC__ initial_participation (Int32.to_int v)
  >>=? fun () ->
  (* listings must be populated in proposal period *)
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* beginning of proposal, denoted by _p1;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p1, rolls_p1) ->
  (* no proposals at the beginning of proposal period *)
  Context.Vote.get_proposals (B b)
  >>=? fun ps ->
  ( if Environment.Protocol_hash.Map.is_empty ps then return_unit
  else failwith "%s - Unexpected proposals" __LOC__ )
  >>=? fun () ->
  (* no current proposal during proposal period *)
  Context.Vote.get_current_proposal (B b)
  >>=? (function
         | None ->
             return_unit
         | Some _ ->
             failwith "%s - Unexpected proposal" __LOC__)
  >>=? fun () ->
  let bak1 = List.nth bakers_p1 0 in
  let bak2 = List.nth bakers_p1 1 in
  let props =
    List.map (fun i -> protos.(i)) (2 -- Constants.max_proposals_per_delegate)
  in
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals (Protocol_hash.zero :: props))
    bootstrap
    bak1
  >>=? fun op1 ->
  Op.baker_action
    (B b)
    ~counter:(Z.of_int 1)
    ~action:(Client_proto_baker.Submit_proposals [Protocol_hash.zero])
    bootstrap
    bak2
  >>=? fun op2 ->
  Block.bake ~operations:[op1; op2] b
  >>=? fun b ->
  (* proposals are now populated *)
  Context.Vote.get_proposals (B b)
  >>=? fun ps ->
  (* correctly count the double proposal for zero *)
  (let weight = Int32.add (List.nth rolls_p1 0) (List.nth rolls_p1 1) in
   match Environment.Protocol_hash.(Map.find_opt zero ps) with
   | Some v ->
       if v = weight then return_unit
       else failwith "%s - Wrong count %ld is not %ld" __LOC__ v weight
   | None ->
       failwith "%s - Missing proposal" __LOC__)
  >>=? fun () ->
  (* proposing more than maximum_proposals fails *)
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals (Protocol_hash.zero :: props))
    bootstrap
    bak1
  >>=? fun op ->
  Block.bake ~operation:op b
  >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Amendment.Too_many_proposals ->
          true
      | _ ->
          false)
  >>=? fun () ->
  (* proposing less than one proposal fails *)
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [])
    bootstrap
    bak1
  >>=? fun ops ->
  Block.bake ~operations:[ops] b
  >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Amendment.Empty_proposal ->
          true
      | _ ->
          false)
  >>=? fun () ->
  (* skip to testing_vote period
     -1 because we already baked one block with the proposal *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 2) b
  >>=? fun b ->
  (* we moved to a testing_vote period with one proposal *)
  assert_period_kind Testing_vote b __LOC__
  >>=? fun () ->
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* period 1 *)
  Context.Vote.get_voting_period (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    Voting_period.equal
    "Unexpected period"
    Voting_period.pp
    v
    Voting_period.(succ root)
  >>=? fun () ->
  (* listings must be populated in proposal period before moving to testing_vote period *)
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* beginning of testing_vote period, denoted by _p2;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p2, rolls_p2) ->
  (* no proposals during testing_vote period *)
  Context.Vote.get_proposals (B b)
  >>=? fun ps ->
  ( if Environment.Protocol_hash.Map.is_empty ps then return_unit
  else failwith "%s - Unexpected proposals" __LOC__ )
  >>=? fun () ->
  (* current proposal must be set during testing_vote period *)
  Context.Vote.get_current_proposal (B b)
  >>=? (function
         | Some v ->
             if Protocol_hash.(equal zero v) then return_unit
             else failwith "%s - Wrong proposal" __LOC__
         | None ->
             failwith "%s - Missing proposal" __LOC__)
  >>=? fun () ->
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  (* unanimous vote: all bakers --active when p2 started-- vote *)
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (Protocol_hash.zero, vote))
        bootstrap
        bak)
    bakers_p2
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  let vote =
    Vote.
      {
        yays_per_roll = 0;
        nays_per_roll = Constants.fixed.votes_per_roll;
        passes_per_roll = 0;
      }
  in
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_ballot (Protocol_hash.zero, vote))
    bootstrap
    bak1
  >>=? fun op ->
  Block.bake ~operations:[op] b
  >>= fun res ->
  Assert.proto_error ~loc:__LOC__ res (function
      | Amendment.Unauthorized_ballot ->
          true
      | _ ->
          false)
  >>=? fun () ->
  (* Allocate votes from weight (rolls) of active bakers *)
  List.fold_left (fun acc v -> Int32.(add v acc)) 0l rolls_p2
  |> fun rolls_sum ->
  (* # of Yay rolls in ballots matches votes of the bakers *)
  Context.Vote.get_ballots (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    ballots_equal
    "Unexpected ballots"
    ballots_pp
    v
    Vote.
      {
        yay = Int32.(mul (of_int Constants.fixed.votes_per_roll) rolls_sum);
        nay = 0l;
        pass = 0l;
      }
  >>=? fun () ->
  (* One Yay ballot per baker *)
  Context.Vote.get_ballot_list (B b)
  >>=? (function
         | [] ->
             failwith "%s - Unexpected empty ballot list" __LOC__
         | l ->
             iter_s
               (fun baker_hash ->
                 let baker = Contract.baker_contract baker_hash in
                 match List.find_opt (fun (b, _) -> b = baker) l with
                 | None ->
                     failwith "%s - Missing baker" __LOC__
                 | Some (_, ballot) ->
                     if
                       ballot.yays_per_roll = Constants.fixed.votes_per_roll
                       && ballot.nays_per_roll = 0
                       && ballot.passes_per_roll = 0
                     then return_unit
                     else failwith "%s - Wrong ballot" __LOC__)
               bakers_p2)
  >>=? fun () ->
  (* skip to testing period
     -1 because we already baked one block with the ballot *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  assert_period_kind Testing b __LOC__
  >>=? fun () ->
  (* period 2 *)
  Context.Vote.get_voting_period (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    Voting_period.equal
    "Unexpected period"
    Voting_period.pp
    v
    Voting_period.(succ (succ root))
  >>=? fun () ->
  (* no ballots in testing period *)
  Context.Vote.get_ballots (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    ballots_equal
    "Unexpected ballots"
    ballots_pp
    v
    ballots_zero
  >>=? fun () ->
  (* listings must be populated in testing period before moving to promotion_vote period *)
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* skip to promotion_vote period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period) b
  >>=? fun b ->
  assert_period_kind Promotion_vote b __LOC__
  >>=? fun () ->
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* period 3 *)
  Context.Vote.get_voting_period (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    Voting_period.equal
    "Unexpected period"
    Voting_period.pp
    v
    Voting_period.(succ (succ (succ root)))
  >>=? fun () ->
  (* listings must be populated in promotion_vote period *)
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* beginning of promotion_vote period, denoted by _p4;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p4, rolls_p4) ->
  (* no proposals during promotion_vote period *)
  Context.Vote.get_proposals (B b)
  >>=? fun ps ->
  ( if Environment.Protocol_hash.Map.is_empty ps then return_unit
  else failwith "%s - Unexpected proposals" __LOC__ )
  >>=? fun () ->
  (* current proposal must be set during promotion_vote period *)
  Context.Vote.get_current_proposal (B b)
  >>=? (function
         | Some v ->
             if Protocol_hash.(equal zero v) then return_unit
             else failwith "%s - Wrong proposal" __LOC__
         | None ->
             failwith "%s - Missing proposal" __LOC__)
  >>=? fun () ->
  (* unanimous vote: all bakers --active when p4 started-- vote *)
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (Protocol_hash.zero, vote))
        bootstrap
        bak)
    bakers_p2
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  List.fold_left (fun acc v -> Int32.(add v acc)) 0l rolls_p4
  |> fun rolls_sum ->
  (* # of Yays in ballots matches rolls of the baker *)
  Context.Vote.get_ballots (B b)
  >>=? fun v ->
  Assert.equal
    ~loc:__LOC__
    ballots_equal
    "Unexpected ballots"
    ballots_pp
    v
    Vote.
      {
        yay = Int32.(mul (of_int Constants.fixed.votes_per_roll) rolls_sum);
        nay = 0l;
        pass = 0l;
      }
  >>=? fun () ->
  (* One Yay ballot per baker *)
  Context.Vote.get_ballot_list (B b)
  >>=? (function
         | [] ->
             failwith "%s - Unexpected empty ballot list" __LOC__
         | l ->
             iter_s
               (fun baker_hash ->
                 let baker = Contract.baker_contract baker_hash in
                 match List.find_opt (fun (b, _) -> b = baker) l with
                 | None ->
                     failwith "%s - Missing baker" __LOC__
                 | Some (_, ballot) ->
                     if
                       ballot.yays_per_roll = Constants.fixed.votes_per_roll
                       && ballot.nays_per_roll = 0
                       && ballot.passes_per_roll = 0
                     then return_unit
                     else failwith "%s - Wrong ballot" __LOC__)
               bakers_p4)
  >>=? fun () ->
  (* skip to Adoption period *)
  Block.bake_n Int32.(to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  assert_period_kind Adoption b __LOC__
  >>=? fun () ->
  (* skip to end of Adoption period to activate *)
  Block.bake_n Int32.(to_int blocks_per_voting_period) b
  >>=? fun b ->
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  assert_listings_not_empty b ~loc:__LOC__
  >>=? fun () ->
  (* zero is the new protocol (before the vote this value is unset) *)
  Context.Vote.get_protocol b
  >>= fun p ->
  Assert.equal
    ~loc:__LOC__
    Protocol_hash.equal
    "Unexpected proposal"
    Protocol_hash.pp
    p
    Protocol_hash.zero
  >>=? fun () -> return_unit

(* given a list of active bakers,
   return the first k active bakers with which one can have quorum, that is:
   their roll sum divided by the total roll sum is bigger than pr_ema_weight/den *)
let get_smallest_prefix_voters_for_quorum active_bakers active_rolls
    participation_ema =
  let expected_quorum = expected_qr_num participation_ema in
  List.fold_left (fun acc v -> Int32.(add v acc)) 0l active_rolls
  |> fun active_rolls_sum ->
  let rec loop bakers rolls sum selected =
    match (bakers, rolls) with
    | ([], []) ->
        selected
    | (bak :: bakers, bak_rolls :: rolls) ->
        if
          den * sum
          < Float.to_int (expected_quorum *. Int32.to_float active_rolls_sum)
        then loop bakers rolls (sum + Int32.to_int bak_rolls) (bak :: selected)
        else selected
    | (_, _) ->
        []
  in
  loop active_bakers active_rolls 0 []

let get_expected_participation_ema rolls voter_rolls old_participation_ema =
  (* formula to compute the updated participation_ema *)
  let get_updated_participation_ema old_participation_ema participation =
    ( (pr_ema_weight * Int32.to_int old_participation_ema)
    + (pr_num * participation) )
    / den
  in
  List.fold_left (fun acc v -> Int32.(add v acc)) 0l rolls
  |> fun rolls_sum ->
  List.fold_left (fun acc v -> Int32.(add v acc)) 0l voter_rolls
  |> fun voter_rolls_sum ->
  let participation =
    Int32.to_int voter_rolls_sum * percent_mul / Int32.to_int rolls_sum
  in
  get_updated_participation_ema old_participation_ema participation

(* if not enough quorum -- get_updated_participation_ema < pr_ema_weight/den -- in testing vote,
   go back to proposal period *)
let test_not_enough_quorum_in_testing_vote num_bakers () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / num_bakers)) in
  Context.init ~min_proposal_quorum num_bakers
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  let bootstrap_baker = List.hd bakers in
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; _}; _} ->
  (* proposal period *)
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  let proposer = bootstrap_baker in
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [Protocol_hash.zero])
    bootstrap
    proposer
  >>=? fun ops ->
  Block.bake ~operations:[ops] b
  >>=? fun b ->
  (* skip to vote_testing period
     -1 because we already baked one block with the proposal *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 2) b
  >>=? fun b ->
  (* we moved to a testing_vote period with one proposal *)
  assert_period_kind Testing_vote b __LOC__
  >>=? fun () ->
  Context.Vote.get_participation_ema b
  >>=? fun initial_participation_ema ->
  (* beginning of testing_vote period, denoted by _p2;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p2, rolls_p2) ->
  Context.Vote.get_participation_ema b
  >>=? fun participation_ema ->
  get_smallest_prefix_voters_for_quorum bakers_p2 rolls_p2 participation_ema
  |> fun voters ->
  (* take the first two voters out so there cannot be quorum *)
  let voters_without_quorum = List.tl voters in
  get_rolls b voters_without_quorum __LOC__
  >>=? fun voters_rolls_in_testing_vote ->
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  (* all voters_without_quorum vote, for yays;
     no nays, so supermajority is satisfied *)
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (Protocol_hash.zero, vote))
        bootstrap
        bak)
    voters_without_quorum
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  (* skip to testing period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* we move back to the proposal period because not enough quorum *)
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  (* check participation_ema update *)
  get_expected_participation_ema
    rolls_p2
    voters_rolls_in_testing_vote
    initial_participation_ema
  |> fun expected_participation_ema ->
  Context.Vote.get_participation_ema b
  >>=? fun new_participation_ema ->
  (* assert the formula to calculate participation_ema is correct *)
  Assert.equal_int
    ~loc:__LOC__
    expected_participation_ema
    (Int32.to_int new_participation_ema)
  >>=? fun () -> return_unit

(* if not enough quorum -- get_updated_participation_ema < pr_ema_weight/den -- in promotion vote,
   go back to proposal period *)
let test_not_enough_quorum_in_promotion_vote num_bakers () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / num_bakers)) in
  Context.init ~min_proposal_quorum num_bakers
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  let proposer = List.hd bakers in
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; _}; _} ->
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [Protocol_hash.zero])
    bootstrap
    proposer
  >>=? fun ops ->
  Block.bake ~operations:[ops] b
  >>=? fun b ->
  (* skip to vote_testing period
     -1 because we already baked one block with the proposal *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 2) b
  >>=? fun b ->
  (* we moved to a testing_vote period with one proposal *)
  assert_period_kind Testing_vote b __LOC__
  >>=? fun () ->
  (* beginning of testing_vote period, denoted by _p2;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p2, rolls_p2) ->
  Context.Vote.get_participation_ema b
  >>=? fun participation_ema ->
  get_smallest_prefix_voters_for_quorum bakers_p2 rolls_p2 participation_ema
  |> fun voters ->
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  (* all voters vote, for yays;
       no nays, so supermajority is satisfied *)
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (Protocol_hash.zero, vote))
        bootstrap
        bak)
    voters
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  (* skip to testing period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* we move to testing because we have supermajority and enough quorum *)
  assert_period_kind Testing b __LOC__
  >>=? fun () ->
  (* skip to promotion_vote period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period) b
  >>=? fun b ->
  assert_period_kind Promotion_vote b __LOC__
  >>=? fun () ->
  Context.Vote.get_participation_ema b
  >>=? fun initial_participation_ema ->
  (* beginning of promotion period, denoted by _p4;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p4, rolls_p4) ->
  Context.Vote.get_participation_ema b
  >>=? fun participation_ema ->
  get_smallest_prefix_voters_for_quorum bakers_p4 rolls_p4 participation_ema
  |> fun voters ->
  (* take the first voter out so there cannot be quorum *)
  let voters_without_quorum = List.tl voters in
  get_rolls b voters_without_quorum __LOC__
  >>=? fun voter_rolls ->
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  (* all voters_without_quorum vote, for yays;
     no nays, so supermajority is satisfied *)
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (Protocol_hash.zero, vote))
        bootstrap
        bak)
    voters_without_quorum
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  (* skip to end of promotion_vote period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  get_expected_participation_ema rolls_p4 voter_rolls initial_participation_ema
  |> fun expected_participation_ema ->
  Context.Vote.get_participation_ema b
  >>=? fun new_participation_ema ->
  (* assert the formula to calculate participation_ema is correct *)
  Assert.equal_int
    ~loc:__LOC__
    expected_participation_ema
    (Int32.to_int new_participation_ema)
  >>=? fun () ->
  (* we move back to the proposal period because not enough quorum *)
  assert_period_kind Proposal b __LOC__ >>=? fun () -> return_unit

let test_multiple_identical_proposals_count_as_one () =
  Context.init 1
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  let proposer = List.hd bakers in
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  Op.baker_action
    (B b)
    ~action:
      (Client_proto_baker.Submit_proposals
         [Protocol_hash.zero; Protocol_hash.zero])
    bootstrap
    proposer
  >>=? fun ops ->
  Block.bake ~operations:[ops] b
  >>=? fun b ->
  (* compute the weight of proposals *)
  Context.Vote.get_proposals (B b)
  >>=? fun ps ->
  (* compute the rolls of proposer *)
  Context.Vote.get_listings (B b)
  >|=? filter_bakers_from_listings
  >>=? fun l ->
  ( match List.find_opt (fun (b, _) -> b = proposer) l with
  | None ->
      failwith "%s - Missing baker" __LOC__
  | Some (_, proposer_rolls) ->
      return proposer_rolls )
  >>=? fun proposer_rolls ->
  (* correctly count the double proposal for zero as one proposal *)
  let expected_weight_proposer = proposer_rolls in
  match Environment.Protocol_hash.(Map.find_opt zero ps) with
  | Some v ->
      if v = expected_weight_proposer then return_unit
      else
        failwith
          "%s - Wrong count %ld is not %ld; identical proposals count as one"
          __LOC__
          v
          expected_weight_proposer
  | None ->
      failwith "%s - Missing proposal" __LOC__

let test_supermajority_in_proposal there_is_a_winner () =
  let min_proposal_quorum = 0l in
  (* initialize context just to get the protocol constants *)
  Context.init 1
  >>=? fun (b, _, _) ->
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; tokens_per_roll; _}; _} ->
  let bal1and2 = Tez.to_mutez tokens_per_roll in
  ( if there_is_a_winner then Test_tez.Tez.( *? ) tokens_per_roll 3L
  else Test_tez.Tez.( *? ) tokens_per_roll 2L )
  >>?= fun bal3 ->
  let bal3 = Tez.to_mutez bal3 in
  (* re-initialize with the right balances *)
  Context.init
    ~min_proposal_quorum
    ~initial_baker_balances:[bal1and2; bal1and2; bal3]
    10
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  let bak1 = List.nth bakers 0 in
  let bak2 = List.nth bakers 1 in
  let bak3 = List.nth bakers 2 in
  let policy = Block.Excluding [bak1; bak2; bak3] in
  (* make the proposals *)
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [protos.(0)])
    bootstrap
    bak1
  >>=? fun ops1 ->
  Op.baker_action
    (B b)
    ~counter:(Z.of_int 1)
    ~action:(Client_proto_baker.Submit_proposals [protos.(0)])
    bootstrap
    bak2
  >>=? fun ops2 ->
  Op.baker_action
    (B b)
    ~counter:(Z.of_int 2)
    ~action:(Client_proto_baker.Submit_proposals [protos.(1)])
    bootstrap
    bak3
  >>=? fun ops3 ->
  Block.bake ~policy ~operations:[ops1; ops2; ops3] b
  >>=? fun b ->
  Block.bake_n ~policy (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* we remain in the proposal period when there is no winner,
     otherwise we move to the testing vote period *)
  ( if there_is_a_winner then assert_period_kind Testing_vote b __LOC__
  else assert_period_kind Proposal b __LOC__ )
  >>=? fun () -> return_unit

let test_quorum_in_proposal has_quorum () =
  (* initialize context just to get the protocol constants *)
  Context.init 1
  >>=? fun (b, _, _) ->
  Context.get_constants (B b)
  >>=? fun { parametric =
               { blocks_per_voting_period;
                 min_proposal_quorum;
                 tokens_per_roll;
                 _ };
             _ } ->
  let total_tokens = 32_000_000_000_000L in
  let tokens_for_quorum =
    Int64.(div (mul total_tokens (Int64.of_int32 min_proposal_quorum)) 100_00L)
  in
  let proposer_balance =
    if has_quorum then tokens_for_quorum
    else
      (* subtract a roll worth of ꜩ to lose quorum *)
      Int64.(sub tokens_for_quorum (Tez.to_mutez tokens_per_roll))
  in
  let rest = Int64.sub total_tokens proposer_balance in
  (* re-initialize with the right balances *)
  Context.init ~initial_baker_balances:[proposer_balance; rest] 2
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  let bak1 = List.nth bakers 0 in
  let policy = Block.Excluding [bak1] in
  (* make the proposal *)
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [protos.(0)])
    bootstrap
    bak1
  >>=? fun ops ->
  Block.bake ~policy ~operations:[ops] b
  >>=? fun b ->
  Block.bake_n ~policy (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* we remain in the proposal period when there is no quorum,
     otherwise we move to the testing vote period *)
  ( if has_quorum then assert_period_kind Testing_vote b __LOC__
  else assert_period_kind Proposal b __LOC__ )
  >>=? fun () -> return_unit

let test_supermajority_in_testing_vote supermajority () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / 100)) in
  Context.init ~min_proposal_quorum 100
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; _}; _} ->
  let proposal = protos.(0) in
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [proposal])
    bootstrap
    (List.hd bakers)
  >>=? fun ops1 ->
  Block.bake ~operations:[ops1] b
  >>=? fun b ->
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* move to testing_vote *)
  assert_period_kind Testing_vote b __LOC__
  >>=? fun () ->
  (* assert our proposal won *)
  Context.Vote.get_current_proposal (B b)
  >>=? (function
         | Some v ->
             if Protocol_hash.(equal proposal v) then return_unit
             else failwith "%s - Wrong proposal" __LOC__
         | None ->
             failwith "%s - Missing proposal" __LOC__)
  >>=? fun () ->
  (* beginning of testing_vote period, denoted by _p2;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p2, _olls_p2) ->
  (* supermajority means [num_yays / (num_yays + num_nays) >= s_num / s_den],
     which is equivalent with [num_yays >= num_nays * s_num / (s_den - s_num)] *)
  let num_bakers = List.length bakers_p2 in
  let num_nays = num_bakers / 5 in
  (* any smaller number will do as well *)
  let num_yays = num_nays * s_num / (s_den - s_num) in
  (* majority/minority vote depending on the [supermajority] parameter *)
  let num_yays = if supermajority then num_yays else num_yays - 1 in
  let (nays_bakers, rest) = List.split_n num_nays bakers_p2 in
  let (yays_bakers, _) = List.split_n num_yays rest in
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (proposal, vote))
        bootstrap
        bak)
    yays_bakers
  >>=? fun operations_yays ->
  Block.bake ~operations:operations_yays b
  >>=? fun b ->
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  let vote =
    Vote.
      {
        yays_per_roll = 0;
        nays_per_roll = Constants.fixed.votes_per_roll;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (proposal, vote))
        bootstrap
        bak)
    nays_bakers
  >>=? fun operations_nays ->
  Block.bake ~operations:operations_nays b
  >>=? fun b ->
  Block.bake_n (Int32.to_int blocks_per_voting_period - 2) b
  >>=? fun b ->
  ( if supermajority then assert_period_kind Testing b __LOC__
  else assert_period_kind Proposal b __LOC__ )
  >>=? fun () -> return_unit

(* test also how the selection scales: all bakers propose max proposals *)
let test_no_winning_proposal num_bakers () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / num_bakers)) in
  Context.init ~min_proposal_quorum num_bakers
  >>=? fun (b, contracts, _) ->
  let bootstrap = List.hd contracts in
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; _}; _} ->
  (* beginning of proposal, denoted by _p1;
     take a snapshot of the active bakers and their rolls from listings *)
  get_bakers_and_rolls_from_listings b
  >>=? fun (bakers_p1, _rolls_p1) ->
  let props =
    List.map (fun i -> protos.(i)) (1 -- Constants.max_proposals_per_delegate)
  in
  (* all bakers active in p1 propose the same proposals *)
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_proposals props)
        bootstrap
        bak)
    bakers_p1
  >>=? fun ops_list ->
  Block.bake ~operations:ops_list b
  >>=? fun b ->
  (* skip to testing_vote period
     -1 because we already baked one block with the proposal *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 2) b
  >>=? fun b ->
  (* we stay in the same proposal period because no winning proposal *)
  assert_period_kind Proposal b __LOC__ >>=? fun () -> return_unit

(** Test that for the vote to pass with maximum possible participation_ema
    (100%), it is sufficient for the vote quorum to be equal or greater than
    the maximum quorum cap. *)
let test_quorum_capped_maximum num_bakers () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / num_bakers)) in
  Context.init ~min_proposal_quorum num_bakers
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  (* set the participation EMA to 100% *)
  Context.Vote.set_participation_ema b 100_00l
  >>= fun b ->
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; quorum_max; _}; _} ->
  (* proposal period *)
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  (* propose a new protocol *)
  let protocol = Protocol_hash.zero in
  let proposer = List.hd bakers in
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [protocol])
    bootstrap
    proposer
  >>=? fun ops ->
  Block.bake ~operations:[ops] b
  >>=? fun b ->
  (* skip to vote_testing period
     -1 because we already baked one block with the proposal *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* we moved to a testing_vote period with one proposal *)
  assert_period_kind Testing_vote b __LOC__
  >>=? fun () ->
  (* take percentage of the bakers equal or greater than quorum_max *)
  let minimum_to_pass =
    Float.of_int (List.length contracts)
    *. Int32.(to_float quorum_max)
    /. 100_00.
    |> Float.ceil |> Float.to_int
  in
  let voters = List.take_n minimum_to_pass bakers in
  (* all voters vote for yays; no nays, so supermajority is satisfied *)
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (protocol, vote))
        bootstrap
        bak)
    voters
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  (* skip to next period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* expect to move to testing because we have supermajority and enough quorum *)
  assert_period_kind Testing b __LOC__

(** Test that for the vote to pass with minimum possible participation_ema
    (0%), it is sufficient for the vote quorum to be equal or greater than
    the minimum quorum cap. *)
let test_quorum_capped_minimum num_bakers () =
  let min_proposal_quorum = Int32.(of_int @@ (100_00 / num_bakers)) in
  Context.init ~min_proposal_quorum num_bakers
  >>=? fun (b, contracts, bakers) ->
  let bootstrap = List.hd contracts in
  (* set the participation EMA to 0% *)
  Context.Vote.set_participation_ema b 0l
  >>= fun b ->
  Context.get_constants (B b)
  >>=? fun {parametric = {blocks_per_voting_period; quorum_min; _}; _} ->
  (* proposal period *)
  assert_period_kind Proposal b __LOC__
  >>=? fun () ->
  (* propose a new protocol *)
  let protocol = Protocol_hash.zero in
  let proposer = List.hd bakers in
  Op.baker_action
    (B b)
    ~action:(Client_proto_baker.Submit_proposals [protocol])
    bootstrap
    proposer
  >>=? fun ops ->
  Block.bake ~operations:[ops] b
  >>=? fun b ->
  (* skip to vote_testing period
     -1 because we already baked one block with the proposal *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* we moved to a testing_vote period with one proposal *)
  assert_period_kind Testing_vote b __LOC__
  >>=? fun () ->
  (* take percentage of the bakers equal or greater than quorum_min *)
  let minimum_to_pass =
    Float.of_int (List.length bakers) *. Int32.(to_float quorum_min) /. 100_00.
    |> Float.ceil |> Float.to_int
  in
  let voters = List.take_n minimum_to_pass bakers in
  (* all voters vote for yays; no nays, so supermajority is satisfied *)
  Context.Contract.counter (B b) bootstrap
  >>=? fun counter ->
  let vote =
    Vote.
      {
        yays_per_roll = Constants.fixed.votes_per_roll;
        nays_per_roll = 0;
        passes_per_roll = 0;
      }
  in
  mapi_s
    (fun i bak ->
      Op.baker_action
        (B b)
        ~counter:Z.(add counter (of_int i))
        ~action:(Client_proto_baker.Submit_ballot (protocol, vote))
        bootstrap
        bak)
    voters
  >>=? fun operations ->
  Block.bake ~operations b
  >>=? fun b ->
  (* skip to next period *)
  Block.bake_n (Int32.to_int blocks_per_voting_period - 1) b
  >>=? fun b ->
  (* expect to move to testing because we have supermajority and enough quorum *)
  assert_period_kind Testing b __LOC__

(* gets the voting power *)
let get_voting_power block pkhash =
  let ctxt = Context.B block in
  Context.get_voting_power ctxt pkhash

(** Test that the voting power changes if the balance between bakers changes
    and the blockchain moves to the next voting period. It also checks that
    the total voting power coincides with the addition of the voting powers
    of bakers *)
let test_voting_power_updated_each_voting_period () =
  let open Test_tez.Tez in
  (* Create three accounts with different amounts *)
  Context.init
    ~initial_baker_balances:
      [80_000_000_000L; 48_000_000_000L; 4_000_000_000_000L]
    3
  >>=? fun (block, _contracts, bakers) ->
  let baker1 = List.hd bakers in
  let baker2 = List.nth bakers 1 in
  let baker3 = List.nth bakers 2 in
  let con1 = Contract.baker_contract baker1 in
  let con2 = Contract.baker_contract baker2 in
  let con3 = Contract.baker_contract baker3 in
  (* Retrieve balance of con1 *)
  Context.Contract.balance (B block) con1
  >>=? fun balance1 ->
  Assert.equal_tez ~loc:__LOC__ balance1 (of_mutez_exn 80_000_000_000L)
  >>=? fun _ ->
  (* Retrieve balance of con2 *)
  Context.Contract.balance (B block) con2
  >>=? fun balance2 ->
  Assert.equal_tez ~loc:__LOC__ balance2 (of_mutez_exn 48_000_000_000L)
  >>=? fun _ ->
  (* Retrieve balance of con3 *)
  Context.Contract.balance (B block) con3
  >>=? fun balance3 ->
  (* Retrieve constants blocks_per_voting_period and tokens_per_roll *)
  Context.get_constants (B block)
  >>=? fun {parametric = {blocks_per_voting_period; tokens_per_roll; _}; _} ->
  (* Auxiliary assert_voting_power *)
  let assert_voting_power ~loc n block baker =
    get_voting_power block baker
    >>=? fun voting_power ->
    Assert.equal_int ~loc n (Int32.to_int voting_power)
  in
  (* Auxiliary assert_total_voting_power *)
  let assert_total_voting_power ~loc n block =
    Context.get_total_voting_power (B block)
    >>=? fun total_voting_power ->
    Assert.equal_int ~loc n (Int32.to_int total_voting_power)
  in
  (* Assert voting power is equal to the balance divided by tokens_per_roll *)
  let expected_power_of_baker_1 =
    Int64.(to_int (div (to_mutez balance1) (to_mutez tokens_per_roll)))
  in
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_1 block baker1
  >>=? fun _ ->
  (* Assert voting power is equal to the balance divided by tokens_per_roll *)
  let expected_power_of_baker_2 =
    Int64.(to_int (div (to_mutez balance2) (to_mutez tokens_per_roll)))
  in
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_2 block baker2
  >>=? fun _ ->
  (* Assert total voting power *)
  let expected_power_of_baker_3 =
    Int64.(to_int (div (to_mutez balance3) (to_mutez tokens_per_roll)))
  in
  assert_total_voting_power
    ~loc:__LOC__
    Int.(
      add
        (add expected_power_of_baker_1 expected_power_of_baker_2)
        expected_power_of_baker_3)
    block
  >>=? fun _ ->
  (* Create policy that excludes baker1 and baker2 from baking *)
  let policy = Block.Excluding [baker1; baker2] in
  (* Transfer tokens_per_roll * num_rolls from baker1 to baker2 *)
  let num_rolls = 5L in
  tokens_per_roll *? num_rolls
  >>?= fun amount ->
  Op.transaction (B block) con1 con2 amount
  >>=? fun _op ->
  (* Bake the block containing the transaction *)
  Block.bake ~policy ~operations:[_op] block
  >>=? fun block ->
  (* Retrieve balance of con1 *)
  Context.Contract.balance (B block) con1
  >>=? fun balance1 ->
  (* Assert balance has changed by tokens_per_roll * num_rolls *)
  tokens_per_roll *? num_rolls
  >>?= fun rolls ->
  of_mutez_exn 80_000_000_000L -? rolls
  >>?= Assert.equal_tez ~loc:__LOC__ balance1
  >>=? fun _ ->
  (* Retrieve balance of con2 *)
  Context.Contract.balance (B block) con2
  >>=? fun balance2 ->
  (* Assert balance has changed by tokens_per_roll * num_rolls *)
  tokens_per_roll *? num_rolls
  >>?= fun rolls ->
  of_mutez_exn 48_000_000_000L +? rolls
  >>?= Assert.equal_tez ~loc:__LOC__ balance2
  >>=? fun _ ->
  (* Bake blocks_per_voting_period - 3, i.e., right before next voting period,
     since 2 blocks have been baked already *)
  Block.bake_n ~policy Int32.(to_int (sub blocks_per_voting_period 3l)) block
  >>=? fun block ->
  (* Assert voting power (and total) remains the same before next voting period *)
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_1 block baker1
  >>=? fun _ ->
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_2 block baker2
  >>=? fun _ ->
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_3 block baker3
  >>=? fun _ ->
  assert_total_voting_power
    ~loc:__LOC__
    Int.(
      add
        (add expected_power_of_baker_1 expected_power_of_baker_2)
        expected_power_of_baker_3)
    block
  >>=? fun _ ->
  (* Bake one more block to move to next voting period *)
  Block.bake ~policy block
  >>=? fun block ->
  (* Assert voting power of baker1 has decreased by num_rolls *)
  let expected_power_of_baker_1 =
    Int.sub expected_power_of_baker_1 (Int64.to_int num_rolls)
  in
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_1 block baker1
  >>=? fun _ ->
  (* Assert voting power of baker2 has increased by num_rolls *)
  let expected_power_of_baker_2 =
    Int.add expected_power_of_baker_2 (Int64.to_int num_rolls)
  in
  assert_voting_power ~loc:__LOC__ expected_power_of_baker_2 block baker2
  >>=? fun _ ->
  (* Retrieve voting power of baker3 *)
  get_voting_power block baker3
  >>=? fun power ->
  let power_of_baker_3 = Int32.to_int power in
  (* Assert total voting power *)
  assert_total_voting_power
    ~loc:__LOC__
    Int.(
      add
        (add expected_power_of_baker_1 expected_power_of_baker_2)
        power_of_baker_3)
    block

let tests =
  [ (* [ Test.tztest "voting successful_vote" `Quick (test_successful_vote 137);
     *   Test.tztest
     *     "voting testing vote, not enough quorum"
     *     `Quick
     *     (test_not_enough_quorum_in_testing_vote 245);
     *   Test.tztest
     *     "voting promotion vote, not enough quorum"
     *     `Quick
     *     (test_not_enough_quorum_in_promotion_vote 232);
     *   Test.tztest
     *     "voting counting double proposal"
     *     `Quick
     *     test_multiple_identical_proposals_count_as_one;
     *   Test.tztest
     *     "voting proposal, with supermajority"
     *     `Quick
     *     (test_supermajority_in_proposal true);
     *   Test.tztest
     *     "voting proposal, without supermajority"
     *     `Quick
     *     (test_supermajority_in_proposal false);
     *   Test.tztest
     *     "voting proposal, with quorum"
     *     `Quick
     *     (test_quorum_in_proposal true);
     *   Test.tztest
     *     "voting proposal, without quorum"
     *     `Quick
     *     (test_quorum_in_proposal false);
     *   Test.tztest
     *     "voting testing vote, with supermajority"
     *     `Quick
     *     (test_supermajority_in_testing_vote true);
     *   Test.tztest
     *     "voting testing vote, without supermajority"
     *     `Quick
     *     (test_supermajority_in_testing_vote false);
     *   Test.tztest
     *     "voting proposal, no winning proposal"
     *     `Quick
     *     (test_no_winning_proposal 300);
     *   Test.tztest
     *     "voting quorum, quorum capped maximum"
     *     `Quick
     *     (test_quorum_capped_maximum 200);
     *   Test.tztest
     *     "voting quorum, quorum capped minimum"
     *     `Quick
     *     (test_quorum_capped_minimum 200); *)
    Test.tztest
      "voting power updated in each voting period"
      `Quick
      test_voting_power_updated_each_voting_period ]
