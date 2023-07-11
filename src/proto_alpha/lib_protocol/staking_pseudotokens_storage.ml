(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** This module is responsible for maintaining the
    {!Storage.Contract.Frozen_deposits_pseudotokens} and
    {!Storage.Contract.Costaking_pseudotokens} tables.


    Pseudo-tokens

    These tables are used to keep track of the distribution of frozen
    deposits between a delegate and its costakers. The amounts stored
    in these tables don't have a fixed value in tez, they represent
    shares of the frozen deposits called pseudotokens. Pseudotokens
    are minted when the delegate or a costaker increases its share
    using the stake pseudo-operation; they are burnt when the delegate
    or a costaker decreases its share using the request-unstake
    pseudo-operation. Events which modify uniformly the stake of all
    costakers (reward distribution and slashing) don't lead to minting
    nor burning any pseudotokens; that's the main motivation for using
    these pseudotokens: thanks to them we never need to iterate over
    the costakers (whose number is unbounded).


    Conversion rate:

    The conversion rate between pseudotokens and mutez (the value in
    mutez of a pseudotoken) should be given by the ratio between the
    delegate's current frozen deposits and the total number of
    pseudotokens of the delegate; it's actually the case when this
    total number of pseudotokens is positive. When the total number of
    pseudotokens of a delegate is null, the conversion rate could
    theoretically have any value but extreme values are dangerous
    because of overflows and loss of precision; for these reasons, we
    use one as the conversion rate when the total number of
    pseudotokens is null, which can happen in two situations:

    - the first time a baker modifies its staking balance since the
    migration which created the pseudotoken tables, and

    - when a baker empties its frozen deposits and later receives
    rewards.


    Implementation:

    The {!Storage.Contract.Costaking_pseudotokens} table stores for
    each staker (delegate or costaker) its /staking balance
    pseudotokens/ which is the number of pseudotokens owned by the
    staker.

    The {!Storage.Contract.Frozen_deposits_pseudotokens} table stores
    for each delegate the /frozen deposits pseudotokens/ of the
    delegate which is defined as the sum of all the staking balance
    pseudotokens of the delegate and its costakers.

    For both tables, pseudotokens are represented using the
    [Pseudotoken_repr.t] type which is, like [Tez_repr.t], stored on
    non-negative signed int64.


    Invariants:

    Invariant 1: frozen deposits pseudotokens initialization

      For {!Storage.Contract.Frozen_deposits_pseudotokens}, a missing
      key is equivalent to a value of [0]. This case means that there are
      no pseudotokens, the delegate has no costaker, the conversion rate is [1].

      This state is equivalent to having as many pseudotokens as the tez frozen
      deposits of the delegate, all owned by the delegate.


    Invariant 2: staking balance pseudotokens initialization

      For {!Storage.Contract.Costaking_pseudotokens}, a missing key is
      equivalent to a value of [0].

    Invariant 3: relationship between frozen deposits and staking
    balance pseudotokens

      For a given delegate, their frozen deposits pseudotokens equal
      the sum of all costaking pseudotokens of their delegators
      (including the delegate itself).


    Ensuring invariants

    Invariant 1:
     This is ensured by:
       - checking that the result of
         {!Storage.Contract.Frozen_deposits_pseudotokens.find} is always matched
         with [Some v when Staking_pseudotoken_repr.(v <> zero)];
       - and that there is no call to
         {!Storage.Contract.Frozen_deposits_pseudotokens.get}.

    Invariant 3:
     It is ensured by:
       - {credit_costaking_pseudotokens} always called with (the pseudotokens
         result of) {credit_frozen_deposits_pseudotokens_for_tez_amount} in
         {stake};
       - {debit_costaking_pseudotokens} always called with (the same value as)
         {debit_frozen_deposits_pseudotokens} in {request_unstake}.
*)

type error += Cannot_stake_on_fully_slashed_delegate

(** Tez -> pseudotokens conversion *)
let pseudotokens_of ~frozen_deposits_pseudotokens ~frozen_deposits_tez
    ~tez_amount =
  assert (Staking_pseudotoken_repr.(frozen_deposits_pseudotokens <> zero)) ;
  assert (Tez_repr.(frozen_deposits_tez <> zero)) ;
  assert (Tez_repr.(tez_amount <> zero)) ;
  let frozen_deposits_tez_z =
    Z.of_int64 (Tez_repr.to_mutez frozen_deposits_tez)
  in
  let frozen_deposits_pseudotokens_z =
    Z.of_int64 (Staking_pseudotoken_repr.to_int64 frozen_deposits_pseudotokens)
  in
  let tez_amount_z = Z.of_int64 (Tez_repr.to_mutez tez_amount) in
  let res_z =
    Z.div
      (Z.mul tez_amount_z frozen_deposits_pseudotokens_z)
      frozen_deposits_tez_z
  in
  Staking_pseudotoken_repr.of_int64_exn (Z.to_int64 res_z)

let tez_of ~frozen_deposits_pseudotokens ~frozen_deposits_tez
    ~pseudotoken_amount =
  if Staking_pseudotoken_repr.(frozen_deposits_pseudotokens = zero) then (
    (* When there are no frozen deposits, starts with 1 mutez = 1 pseudotoken. *)
    assert (Tez_repr.(frozen_deposits_tez = zero)) ;
    Tez_repr.of_mutez_exn (Staking_pseudotoken_repr.to_int64 pseudotoken_amount))
  else
    let frozen_deposits_tez_z =
      Z.of_int64 (Tez_repr.to_mutez frozen_deposits_tez)
    in
    let frozen_deposits_pseudotokens_z =
      Z.of_int64
        (Staking_pseudotoken_repr.to_int64 frozen_deposits_pseudotokens)
    in
    let pseudotoken_amount_z =
      Z.of_int64 (Staking_pseudotoken_repr.to_int64 pseudotoken_amount)
    in
    let res_z =
      Z.div
        (Z.mul frozen_deposits_tez_z pseudotoken_amount_z)
        frozen_deposits_pseudotokens_z
    in
    Tez_repr.of_mutez_exn (Z.to_int64 res_z)

(** [credit_frozen_deposits_pseudotokens_for_tez_amount ctxt delegate tez_amount]
  increases [delegate]'s stake pseudotokens by an amount [pa] corresponding to
  [tez_amount] multiplied by the current rate of the delegate's frozen
  deposits pseudotokens per tez, as
  [frozen_deposits_pseudotokens_for_tez_amount] would return.
  The function also returns [pa].

  This function must be called on "stake" before transferring tez to
  [delegate]'s frozen deposits. *)
let credit_frozen_deposits_pseudotokens_for_tez_amount ctxt delegate tez_amount
    =
  let open Lwt_result_syntax in
  if Tez_repr.(tez_amount = zero) then
    return (ctxt, Staking_pseudotoken_repr.zero)
  else
    let contract = Contract_repr.Implicit delegate in
    let* {current_amount = frozen_deposits_tez; initial_amount = _} =
      Frozen_deposits_storage.get ctxt contract
    in
    let* frozen_deposits_pseudotokens_opt =
      Storage.Contract.Frozen_deposits_pseudotokens.find ctxt contract
    in
    let* ctxt, frozen_deposits_pseudotokens, pseudotokens_to_add =
      match frozen_deposits_pseudotokens_opt with
      | Some frozen_deposits_pseudotokens
        when Staking_pseudotoken_repr.(frozen_deposits_pseudotokens <> zero) ->
          if Tez_repr.(frozen_deposits_tez = zero) then
            tzfail Cannot_stake_on_fully_slashed_delegate
          else
            let pseudotokens_to_add =
              pseudotokens_of
                ~frozen_deposits_pseudotokens
                ~frozen_deposits_tez
                ~tez_amount
            in
            return (ctxt, frozen_deposits_pseudotokens, pseudotokens_to_add)
      | _ ->
          let init_frozen_deposits_pseudotokens =
            Staking_pseudotoken_repr.of_int64_exn
              (Tez_repr.to_mutez frozen_deposits_tez)
          in
          let*! ctxt =
            Storage.Contract.Costaking_pseudotokens.add
              ctxt
              contract
              init_frozen_deposits_pseudotokens
          in
          let pseudotokens_to_add =
            Staking_pseudotoken_repr.of_int64_exn (Tez_repr.to_mutez tez_amount)
          in
          return (ctxt, init_frozen_deposits_pseudotokens, pseudotokens_to_add)
    in
    let*? new_frozen_deposits_pseudotokens =
      Staking_pseudotoken_repr.(
        pseudotokens_to_add +? frozen_deposits_pseudotokens)
    in
    let*! ctxt =
      Storage.Contract.Frozen_deposits_pseudotokens.add
        ctxt
        contract
        new_frozen_deposits_pseudotokens
    in
    return (ctxt, pseudotokens_to_add)

(** [debit_frozen_deposits_pseudotokens ctxt delegate p_amount] decreases
    [delegate]'s stake pseudotokens by [p_amount].
    The function also returns the amount of tez [p_amount] current worth.
*)
let debit_frozen_deposits_pseudotokens ctxt delegate pseudotoken_amount =
  let open Lwt_result_syntax in
  if Staking_pseudotoken_repr.(pseudotoken_amount = zero) then
    return (ctxt, Tez_repr.zero)
  else
    let contract = Contract_repr.Implicit delegate in
    let* {current_amount = frozen_deposits_tez; initial_amount = _} =
      Frozen_deposits_storage.get ctxt contract
    in
    let* frozen_deposits_pseudotokens_opt =
      Storage.Contract.Frozen_deposits_pseudotokens.find ctxt contract
    in
    let frozen_deposits_pseudotokens =
      match frozen_deposits_pseudotokens_opt with
      | Some frozen_deposits_pseudotokens
        when Staking_pseudotoken_repr.(frozen_deposits_pseudotokens <> zero) ->
          frozen_deposits_pseudotokens
      | _ ->
          Staking_pseudotoken_repr.of_int64_exn
            (Tez_repr.to_mutez frozen_deposits_tez)
    in
    let*? new_frozen_deposits_pseudotokens =
      Staking_pseudotoken_repr.(
        frozen_deposits_pseudotokens -? pseudotoken_amount)
    in
    let tez_amount =
      tez_of
        ~frozen_deposits_pseudotokens
        ~frozen_deposits_tez
        ~pseudotoken_amount
    in
    let*! ctxt =
      Storage.Contract.Frozen_deposits_pseudotokens.add
        ctxt
        contract
        new_frozen_deposits_pseudotokens
    in
    return (ctxt, tez_amount)

(** [costaking_pseudotokens_balance ctxt contract] returns [contract]'s
    current costaking balance. *)
let costaking_pseudotokens_balance ctxt contract =
  let open Lwt_result_syntax in
  let+ costaking_pseudotokens_opt =
    Storage.Contract.Costaking_pseudotokens.find ctxt contract
  in
  Option.value ~default:Staking_pseudotoken_repr.zero costaking_pseudotokens_opt

let costaking_balance_as_tez ctxt ~contract ~delegate =
  let open Lwt_result_syntax in
  let delegate_contract = Contract_repr.Implicit delegate in
  let* pseudotoken_amount = costaking_pseudotokens_balance ctxt contract in
  let* frozen_deposits_pseudotokens_opt =
    Storage.Contract.Frozen_deposits_pseudotokens.find ctxt delegate_contract
  in
  match frozen_deposits_pseudotokens_opt with
  | Some frozen_deposits_pseudotokens
    when Staking_pseudotoken_repr.(frozen_deposits_pseudotokens <> zero) ->
      let+ {current_amount = frozen_deposits_tez; initial_amount = _} =
        Frozen_deposits_storage.get ctxt delegate_contract
      in
      tez_of
        ~frozen_deposits_pseudotokens
        ~frozen_deposits_tez
        ~pseudotoken_amount
  | _ ->
      assert (Staking_pseudotoken_repr.(pseudotoken_amount = zero)) ;
      if Contract_repr.(contract = delegate_contract) then
        let+ {current_amount = frozen_deposits_tez; initial_amount = _} =
          Frozen_deposits_storage.get ctxt delegate_contract
        in
        frozen_deposits_tez
      else return Tez_repr.zero

let update_costaking_pseudotokens ~f ctxt contract =
  let open Lwt_result_syntax in
  let* costaking_pseudotokens = costaking_pseudotokens_balance ctxt contract in
  let*? new_costaking_pseudotokens = f costaking_pseudotokens in
  let*! ctxt =
    Storage.Contract.Costaking_pseudotokens.add
      ctxt
      contract
      new_costaking_pseudotokens
  in
  return ctxt

(** [credit_costaking_pseudotokens ctxt contract p_amount] increases
    [contract]'s costaking pseudotokens balance by [p_amount]. *)
let credit_costaking_pseudotokens ctxt contract pseudotokens_to_add =
  let f current_pseudotokens_balance =
    Staking_pseudotoken_repr.(
      current_pseudotokens_balance +? pseudotokens_to_add)
  in
  update_costaking_pseudotokens ~f ctxt contract

(** [debit_costaking_pseudotokens ctxt contract p_amount] decreases
    [contract]'s costaking pseudotokens balance by [p_amount]. *)
let debit_costaking_pseudotokens ctxt contract pseudotokens_to_subtract =
  let f current_pseudotokens_balance =
    Staking_pseudotoken_repr.(
      current_pseudotokens_balance -? pseudotokens_to_subtract)
  in
  update_costaking_pseudotokens ~f ctxt contract

let stake ctxt ~contract ~delegate amount =
  let open Lwt_result_syntax in
  let* ctxt, new_pseudotokens =
    credit_frozen_deposits_pseudotokens_for_tez_amount ctxt delegate amount
  in
  credit_costaking_pseudotokens ctxt contract new_pseudotokens

let request_unstake ctxt ~contract ~delegate requested_amount =
  let open Lwt_result_syntax in
  if Tez_repr.(requested_amount = zero) then return (ctxt, Tez_repr.zero)
  else
    let delegate_contract = Contract_repr.Implicit delegate in
    let* {current_amount = frozen_deposits_tez; initial_amount = _} =
      Frozen_deposits_storage.get ctxt delegate_contract
    in
    if Tez_repr.(frozen_deposits_tez = zero) then return (ctxt, Tez_repr.zero)
    else
      let* frozen_deposits_pseudotokens_opt =
        Storage.Contract.Frozen_deposits_pseudotokens.find
          ctxt
          delegate_contract
      in
      let* available_pseudotokens =
        costaking_pseudotokens_balance ctxt contract
      in
      match frozen_deposits_pseudotokens_opt with
      | Some frozen_deposits_pseudotokens
        when Staking_pseudotoken_repr.(frozen_deposits_pseudotokens <> zero) ->
          if Staking_pseudotoken_repr.(available_pseudotokens = zero) then
            return (ctxt, Tez_repr.zero)
          else
            let requested_pseudotokens =
              pseudotokens_of
                ~frozen_deposits_pseudotokens
                ~frozen_deposits_tez
                ~tez_amount:requested_amount
            in
            let pseudotokens_to_unstake =
              Staking_pseudotoken_repr.min
                requested_pseudotokens
                available_pseudotokens
            in
            assert (Staking_pseudotoken_repr.(pseudotokens_to_unstake <> zero)) ;
            let* ctxt, tez_to_unstake =
              debit_frozen_deposits_pseudotokens
                ctxt
                delegate
                pseudotokens_to_unstake
            in
            let+ ctxt =
              debit_costaking_pseudotokens ctxt contract pseudotokens_to_unstake
            in
            (ctxt, tez_to_unstake)
      | _ ->
          (* [delegate] must be non-costaked and have their pseudotokens
             non-initialized.
             Either the request is from a delegator with zero costake (hence
             nothing to unstake) or from the delegate themself and there is no
             need to initialize their pseudotokens. *)
          assert (Staking_pseudotoken_repr.(available_pseudotokens = zero)) ;
          if Contract_repr.(contract = delegate_contract) then
            return (ctxt, Tez_repr.min frozen_deposits_tez requested_amount)
          else return (ctxt, Tez_repr.zero)
