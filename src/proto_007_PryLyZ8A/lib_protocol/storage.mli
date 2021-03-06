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

(** Tezos Protocol Implementation - Typed storage

    This module hides the hierarchical (key x value) database under
    pre-allocated typed accessors for all persistent entities of the
    tezos context.

    This interface enforces no invariant on the contents of the
    database. Its goal is to centralize all accessors in order to have
    a complete view over the database contents and avoid key
    collisions. *)

open Storage_sigs

module Block_priority : sig
  val get : Raw_context.t -> int tzresult Lwt.t

  val set : Raw_context.t -> int -> Raw_context.t tzresult Lwt.t

  val init : Raw_context.t -> int -> Raw_context.t tzresult Lwt.t
end

module Roll : sig
  (** Storage from this submodule must only be accessed through the
      module `Roll`. *)

  module Owner :
    Indexed_data_snapshotable_storage
      with type key = Roll_repr.t
       and type snapshot = Cycle_repr.t * int
       and type value = Baker_hash.t
       and type t := Raw_context.t

  module Owner_006 :
    Indexed_data_snapshotable_storage
      with type key = Roll_repr.t
       and type snapshot = Cycle_repr.t * int
       and type value = Signature.Public_key.t
       and type t := Raw_context.t

  val clear : Raw_context.t -> Raw_context.t Lwt.t

  (** The next roll to be allocated. *)
  module Next :
    Single_data_storage
      with type value = Roll_repr.t
       and type t := Raw_context.t

  (** Rolls linked lists represent both account owned and free rolls.
      All rolls belongs either to the limbo list or to an owned list. *)

  (** Head of the linked list of rolls in limbo *)
  module Limbo :
    Single_data_storage
      with type value = Roll_repr.t
       and type t := Raw_context.t

  (** Rolls associated to bakers, a linked list per baker *)
  module Baker_roll_list :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = Roll_repr.t
       and type t := Raw_context.t

  (** Rolls associated to contracts, a linked list per contract *)
  module Delegate_roll_list_006 :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Roll_repr.t
       and type t := Raw_context.t

  (** Use this to iter on a linked list of rolls *)
  module Successor :
    Indexed_data_storage
      with type key = Roll_repr.t
       and type value = Roll_repr.t
       and type t := Raw_context.t

  (** The tez of a baker that are not assigned to rolls *)
  module Baker_change :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = Tez_repr.t
       and type t := Raw_context.t

  (** The tez of a contract that are not assigned to rolls *)
  module Delegate_change_006 :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Tez_repr.t
       and type t := Raw_context.t

  (** Index of the randomly selected roll snapshot of a given cycle. *)
  module Snapshot_for_cycle :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = int
       and type t := Raw_context.t

  (** Last roll in the snapshoted roll allocation of a given cycle. *)
  module Last_for_snapshot :
    Indexed_data_storage
      with type key = int
       and type value = Roll_repr.t
       and type t = Raw_context.t * Cycle_repr.t
end

module Contract : sig
  (** Storage from this submodule must only be accessed through the
      module `Contract`. *)

  module Global_counter : sig
    val get : Raw_context.t -> Z.t tzresult Lwt.t

    val set : Raw_context.t -> Z.t -> Raw_context.t tzresult Lwt.t

    val init : Raw_context.t -> Z.t -> Raw_context.t tzresult Lwt.t
  end

  (** The domain of alive contracts *)
  val fold :
    Raw_context.t ->
    init:'a ->
    f:(Contract_repr.t -> 'a -> 'a Lwt.t) ->
    'a Lwt.t

  val list : Raw_context.t -> Contract_repr.t list Lwt.t

  (** All the tez possessed by a contract, including rolls and change *)
  module Balance :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Tez_repr.t
       and type t := Raw_context.t

  (** Frozen balance, see 'delegate_storage.mli' for more explanation.
      Always update `Delegates_with_frozen_balance` accordingly. *)
  module Frozen_deposits_006 :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Contract_repr.t

  module Frozen_fees_006 :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Contract_repr.t

  module Frozen_rewards_006 :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Contract_repr.t

  (** The manager of a contract *)
  module Manager :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Manager_repr.t
       and type t := Raw_context.t

  (** The delegate of a contract, if any. *)
  module Delegate :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Baker_hash.t
       and type t := Raw_context.t

  module Delegate_006 :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Signature.Public_key_hash.t
       and type t := Raw_context.t

  (** All contracts (implicit and originated) that are delegated, if any  *)
  module Delegated_006 :
    Data_set_storage
      with type elt = Contract_repr.t
       and type t = Raw_context.t * Contract_repr.t

  module Inactive_delegate_006 :
    Data_set_storage with type elt = Contract_repr.t and type t = Raw_context.t

  module Delegate_desactivation_006 :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Cycle_repr.t
       and type t := Raw_context.t

  module Counter :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Z.t
       and type t := Raw_context.t

  module Code : sig
    include
      Non_iterable_indexed_carbonated_data_storage
        with type key = Contract_repr.t
         and type value = Script_repr.lazy_expr
         and type t := Raw_context.t

    (** Only used for 007 migration to avoid gas cost.
        Updates the content of a bucket ; returns A {!Storage_Error
        Missing_key} if the value does not exists. *)
    val set_free :
      Raw_context.t ->
      Contract_repr.t ->
      Script_repr.lazy_expr ->
      (Raw_context.t * int) tzresult Lwt.t
  end

  module Storage :
    Non_iterable_indexed_carbonated_data_storage
      with type key = Contract_repr.t
       and type value = Script_repr.lazy_expr
       and type t := Raw_context.t

  (** Current storage space in bytes.
      Includes code, global storage and big map elements. *)
  module Used_storage_space :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Z.t
       and type t := Raw_context.t

  (** Maximal space available without needing to burn new fees. *)
  module Paid_storage_space :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Z.t
       and type t := Raw_context.t
end

module Big_map : sig
  type id = Lazy_storage_kind.Big_map.Id.t

  module Next : sig
    val incr : Raw_context.t -> (Raw_context.t * id) tzresult Lwt.t

    val init : Raw_context.t -> Raw_context.t tzresult Lwt.t
  end

  (** The domain of alive big maps *)
  val fold : Raw_context.t -> init:'a -> f:(id -> 'a -> 'a Lwt.t) -> 'a Lwt.t

  val list : Raw_context.t -> id list Lwt.t

  val remove_rec : Raw_context.t -> id -> Raw_context.t Lwt.t

  val copy : Raw_context.t -> from:id -> to_:id -> Raw_context.t tzresult Lwt.t

  type key = Raw_context.t * id

  val rpc_arg : id RPC_arg.t

  module Contents :
    Non_iterable_indexed_carbonated_data_storage
      with type key = Script_expr_hash.t
       and type value = Script_repr.expr
       and type t := key

  module Total_bytes :
    Indexed_data_storage
      with type key = id
       and type value = Z.t
       and type t := Raw_context.t

  module Key_type :
    Indexed_data_storage
      with type key = id
       and type value = Script_repr.expr
       and type t := Raw_context.t

  module Value_type :
    Indexed_data_storage
      with type key = id
       and type value = Script_repr.expr
       and type t := Raw_context.t
end

module Sapling : sig
  type id = Lazy_storage_kind.Sapling_state.Id.t

  val rpc_arg : id RPC_arg.t

  module Next : sig
    val incr : Raw_context.t -> (Raw_context.t * id) tzresult Lwt.t

    val init : Raw_context.t -> Raw_context.t tzresult Lwt.t
  end

  val remove_rec : Raw_context.t -> id -> Raw_context.t Lwt.t

  val copy : Raw_context.t -> from:id -> to_:id -> Raw_context.t tzresult Lwt.t

  module Total_bytes :
    Indexed_data_storage
      with type key = id
       and type value = Z.t
       and type t := Raw_context.t

  (* Used by both Commitments and Ciphertexts *)
  module Commitments_size :
    Single_data_storage
      with type t := Raw_context.t * id
       and type value = int64

  module Memo_size :
    Single_data_storage with type t := Raw_context.t * id and type value = int

  module Commitments :
    Non_iterable_indexed_carbonated_data_storage
      with type t := Raw_context.t * id
       and type key = int64
       and type value = Sapling.Hash.t

  val commitments_init : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Ciphertexts :
    Non_iterable_indexed_carbonated_data_storage
      with type t := Raw_context.t * id
       and type key = int64
       and type value = Sapling.Ciphertext.t

  val ciphertexts_init : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Nullifiers_size :
    Single_data_storage
      with type t := Raw_context.t * id
       and type value = int64

  module Nullifiers_ordered :
    Non_iterable_indexed_data_storage
      with type t := Raw_context.t * id
       and type key = int64
       and type value = Sapling.Nullifier.t

  module Nullifiers_hashed :
    Carbonated_data_set_storage
      with type t := Raw_context.t * id
       and type elt = Sapling.Nullifier.t

  val nullifiers_init : Raw_context.t -> id -> Raw_context.t Lwt.t

  module Roots :
    Non_iterable_indexed_data_storage
      with type t := Raw_context.t * id
       and type key = int32
       and type value = Sapling.Hash.t

  module Roots_pos :
    Single_data_storage
      with type t := Raw_context.t * id
       and type value = int32

  module Roots_level :
    Single_data_storage
      with type t := Raw_context.t * id
       and type value = Raw_level_repr.t
end

(** Map of baker accounts migrated from implicit contracts to baker contracts.
    Only used during migration, then cleared-up. *)
module Delegates_006 :
  Data_set_storage
    with type t := Raw_context.t
     and type elt = Signature.Public_key_hash.t

module Active_delegates_with_rolls_006 :
  Data_set_storage
    with type t := Raw_context.t
     and type elt = Signature.Public_key_hash.t

module Delegates_with_frozen_balance_006 :
  Data_set_storage
    with type t = Raw_context.t * Cycle_repr.t
     and type elt = Signature.Public_key_hash.t

module Baker : sig
  (** Set of all registered bakers. *)
  module Registered :
    Data_set_storage with type t := Raw_context.t and type elt = Baker_hash.t

  (** All contracts that are delegated to a given baker, if any. *)
  module Delegators :
    Data_set_storage
      with type elt = Contract_repr.t
       and type t = Raw_context.t * Baker_hash.t

  (** Set of all active bakers with rolls. *)
  module Active_with_rolls :
    Data_set_storage with type t := Raw_context.t and type elt = Baker_hash.t

  (** Set of all the bakers with frozen rewards/bonds/fees for a given cycle. *)
  module With_frozen_balance :
    Data_set_storage
      with type t = Raw_context.t * Cycle_repr.t
       and type elt = Baker_hash.t

  (** Inactive bakers **)
  module Inactive :
    Data_set_storage with type elt = Baker_hash.t and type t = Raw_context.t

  (** Bakers that decline any new delegation **)
  module Delegation_decliners :
    Data_set_storage with type elt = Baker_hash.t and type t = Raw_context.t

  (** The cycle where the baker should be deactivated. *)
  module Deactivation :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = Cycle_repr.t
       and type t := Raw_context.t

  (** Frozen balance, see 'baker_storage.mli' for more explanation.
      Always update `Bakers_with_frozen_balance` accordingly. *)
  module Frozen_deposits :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Baker_hash.t

  module Frozen_fees :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Baker_hash.t

  module Frozen_rewards :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t
       and type t = Raw_context.t * Baker_hash.t

  (** All evidence that as been used against a delegate, if any *)
  module Proof_level :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = Raw_level_repr.LSet.t
       and type t := Raw_context.t

  (** Baker's possible pending consensus key and its activation cycle.
      The pending key will become active on the start of activation cycle *)
  module Pending_consensus_key :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = Signature.Public_key.t * Cycle_repr.t
       and type t := Raw_context.t

  (** Consensus key is authorized to transfer directly from a baker account,
      participate in consensus and governance. *)
  module Consensus_key :
    Indexed_data_snapshotable_storage
      with type key = Baker_hash.t
       and type snapshot = Cycle_repr.t
       and type value = Signature.Public_key.t
       and type t := Raw_context.t

  (** Consensus key to a baker for reverse lookup. Deliberately redundant, it
      contains the same bindings as [Consensus_key.Snapshot] storage for
      the current cycle, alas the keys and values are flipped and the consensus
      key is stored as a hash of public key instead of public key itself. *)
  module Consensus_key_rev :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Baker_hash.t
       and type t := Raw_context.t

  module Pvss_key :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = Pvss_secp256k1.Public_key.t
       and type t := Raw_context.t
end

(** Votes *)

module Vote : sig
  module Current_period_kind :
    Single_data_storage
      with type value = Voting_period_repr.kind
       and type t := Raw_context.t

  (** Participation exponential moving average, in centile of percentage *)
  module Participation_ema :
    Single_data_storage with type value = int32 and type t := Raw_context.t

  module Current_proposal :
    Single_data_storage
      with type value = Protocol_hash.t
       and type t := Raw_context.t

  (** Sum of all rolls of all delegates. *)
  module Listings_size :
    Single_data_storage with type value = int32 and type t := Raw_context.t

  (** Contains all delegates with their assigned number of rolls. *)
  module Listings :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = int32
       and type t := Raw_context.t

  module Listings_006 :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = int32
       and type t := Raw_context.t

  (** Set of protocol proposal with corresponding proposer delegate *)
  module Proposals :
    Data_set_storage
      with type elt = Protocol_hash.t * Baker_hash.t
       and type t := Raw_context.t

  module Proposals_006 :
    Data_set_storage
      with type elt = Protocol_hash.t * Signature.Public_key_hash.t
       and type t := Raw_context.t

  (** Keeps for each delegate the number of proposed protocols *)
  module Proposals_count :
    Indexed_data_storage
      with type key = Baker_hash.t
       and type value = int
       and type t := Raw_context.t

  module Proposals_count_006 :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = int
       and type t := Raw_context.t

  (** Contains for each delegate its ballot *)
  module Ballots :
    Indexed_data_storage
      with type key = Contract_repr.t
       and type value = Vote_repr.ballot
       and type t := Raw_context.t

  module Ballots_006 :
    Indexed_data_storage
      with type key = Signature.Public_key_hash.t
       and type value = Vote_repr.ballot
       and type t := Raw_context.t
end

(** Seed *)

module Seed : sig
  (** Storage from this submodule must only be accessed through the
      module `Seed`. *)

  type unrevealed_nonce = {
    nonce_hash : Nonce_hash.t;
    baker : Baker_hash.t;
    rewards : Tez_repr.t;
    fees : Tez_repr.t;
  }

  type nonce_status =
    | Unrevealed of unrevealed_nonce
    | Revealed of Seed_repr.nonce

  module Nonce :
    Non_iterable_indexed_data_storage
      with type key := Level_repr.t
       and type value := nonce_status
       and type t := Raw_context.t

  module For_cycle : sig
    val init :
      Raw_context.t ->
      Cycle_repr.t ->
      Seed_repr.seed ->
      Raw_context.t tzresult Lwt.t

    val get : Raw_context.t -> Cycle_repr.t -> Seed_repr.seed tzresult Lwt.t

    val delete : Raw_context.t -> Cycle_repr.t -> Raw_context.t tzresult Lwt.t
  end
end

(** Commitments *)

module Commitments :
  Indexed_data_storage
    with type key = Blinded_public_key_hash.t
     and type value = Tez_repr.t
     and type t := Raw_context.t

(** Ramp up security deposits... *)

module Ramp_up : sig
  module Rewards :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value := Tez_repr.t list * Tez_repr.t list
      (* baking rewards per endorsement * endorsement rewards *)
       and type t := Raw_context.t

  module Security_deposits :
    Indexed_data_storage
      with type key = Cycle_repr.t
       and type value = Tez_repr.t * Tez_repr.t
      (* baking * endorsement *)
       and type t := Raw_context.t
end

module Pending_migration_balance_updates :
  Single_data_storage
    with type value = Receipt_repr.balance_updates
     and type t := Raw_context.t

(* only exposed for 007 migration *)
module Cycle : sig
  type unrevealed_nonce = {
    nonce_hash : Nonce_hash.t;
    baker : Baker_hash.t;
    rewards : Tez_repr.t;
    fees : Tez_repr.t;
  }

  type nonce_status =
    | Unrevealed of unrevealed_nonce
    | Revealed of Seed_repr.nonce

  module Nonce :
    Indexed_data_storage
      with type key := Raw_level_repr.t
       and type value := nonce_status
       and type t := Raw_context.t * Cycle_repr.t
end

module Cycle_006 : sig
  type unrevealed_nonce = {
    nonce_hash : Nonce_hash.t;
    delegate : Signature.Public_key_hash.t;
    rewards : Tez_repr.t;
    fees : Tez_repr.t;
  }

  type nonce_status =
    | Unrevealed of unrevealed_nonce
    | Revealed of Seed_repr.nonce

  module Nonce :
    Indexed_data_storage
      with type key := Raw_level_repr.t
       and type value := nonce_status
       and type t := Raw_context.t * Cycle_repr.t
end
