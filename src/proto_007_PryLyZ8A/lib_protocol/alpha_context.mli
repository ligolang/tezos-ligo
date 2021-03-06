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

module type BASIC_DATA = sig
  type t

  include Compare.S with type t := t

  val encoding : t Data_encoding.t

  val pp : Format.formatter -> t -> unit
end

type t

type context = t

type public_key = Signature.Public_key.t

type public_key_hash = Signature.Public_key_hash.t

type signature = Signature.t

type baker_hash = Baker_hash.t

module Tez : sig
  include BASIC_DATA

  type tez = t

  val zero : tez

  val one_mutez : tez

  val one_cent : tez

  val fifty_cents : tez

  val one : tez

  val ( -? ) : tez -> tez -> tez tzresult

  val ( +? ) : tez -> tez -> tez tzresult

  val ( *? ) : tez -> int64 -> tez tzresult

  val ( /? ) : tez -> int64 -> tez tzresult

  val of_string : string -> tez option

  val to_string : tez -> string

  val of_mutez : int64 -> tez option

  val to_mutez : tez -> int64
end

module Period : sig
  include BASIC_DATA

  type period = t

  val rpc_arg : period RPC_arg.arg

  val of_seconds : int64 -> period tzresult

  val to_seconds : period -> int64

  val mult : int32 -> period -> period tzresult

  val zero : period

  val one_second : period

  val one_minute : period

  val one_hour : period
end

module Timestamp : sig
  include BASIC_DATA with type t = Time.t

  type time = t

  val ( +? ) : time -> Period.t -> time tzresult

  val ( -? ) : time -> time -> Period.t tzresult

  val of_notation : string -> time option

  val to_notation : time -> string

  val of_seconds_string : string -> time option

  val to_seconds_string : time -> string

  val current : context -> time
end

module Raw_level : sig
  include BASIC_DATA

  type raw_level = t

  val rpc_arg : raw_level RPC_arg.arg

  val diff : raw_level -> raw_level -> int32

  val root : raw_level

  val succ : raw_level -> raw_level

  val pred : raw_level -> raw_level option

  val to_int32 : raw_level -> int32

  val of_int32 : int32 -> raw_level tzresult

  module LSet : sig
    include S.SET with type elt = raw_level

    val encoding : t Data_encoding.t
  end
end

module Cycle : sig
  include BASIC_DATA

  type cycle = t

  val rpc_arg : cycle RPC_arg.arg

  val root : cycle

  val succ : cycle -> cycle

  val pred : cycle -> cycle option

  val add : cycle -> int -> cycle

  val sub : cycle -> int -> cycle option

  val to_int32 : cycle -> int32

  module Map : S.MAP with type key = cycle
end

module Gas : sig
  type t = private Unaccounted | Limited of {remaining : Z.t}

  val encoding : t Data_encoding.encoding

  val pp : Format.formatter -> t -> unit

  type cost

  val cost_encoding : cost Data_encoding.encoding

  val pp_cost : Format.formatter -> cost -> unit

  type error += Block_quota_exceeded (* `Temporary *)

  type error += Operation_quota_exceeded (* `Temporary *)

  type error += Gas_limit_too_high (* `Permanent *)

  val free : cost

  val atomic_step_cost : int -> cost

  val step_cost : int -> cost

  val alloc_cost : int -> cost

  val alloc_bytes_cost : int -> cost

  val alloc_mbytes_cost : int -> cost

  val alloc_bits_cost : int -> cost

  val read_bytes_cost : Z.t -> cost

  val write_bytes_cost : Z.t -> cost

  val ( *@ ) : int -> cost -> cost

  val ( +@ ) : cost -> cost -> cost

  val check_limit : context -> Z.t -> unit tzresult

  val set_limit : context -> Z.t -> context

  val set_unlimited : context -> context

  val consume : context -> cost -> context tzresult

  val check_enough : context -> cost -> unit tzresult

  val level : context -> t

  val consumed : since:context -> until:context -> Z.t

  val block_level : context -> Z.t
end

module Script_int : module type of Script_int_repr

module Script_timestamp : sig
  open Script_int

  type t

  val compare : t -> t -> int

  val to_string : t -> string

  val to_notation : t -> string option

  val to_num_str : t -> string

  val of_string : string -> t option

  val diff : t -> t -> z num

  val add_delta : t -> z num -> t

  val sub_delta : t -> z num -> t

  val now : context -> t

  val to_zint : t -> Z.t

  val of_zint : Z.t -> t
end

module Script : sig
  type prim = Michelson_v1_primitives.prim =
    | K_parameter
    | K_storage
    | K_code
    | D_False
    | D_Elt
    | D_Left
    | D_None
    | D_Pair
    | D_Right
    | D_Some
    | D_True
    | D_Unit
    | I_PACK
    | I_UNPACK
    | I_BLAKE2B
    | I_SHA256
    | I_SHA512
    | I_ABS
    | I_ADD
    | I_AMOUNT
    | I_AND
    | I_BALANCE
    | I_CAR
    | I_CDR
    | I_CHAIN_ID
    | I_CHECK_SIGNATURE
    | I_COMPARE
    | I_CONCAT
    | I_CONS
    | I_CREATE_ACCOUNT
    | I_CREATE_CONTRACT
    | I_IMPLICIT_ACCOUNT
    | I_DIP
    | I_DROP
    | I_DUP
    | I_EDIV
    | I_EMPTY_BIG_MAP
    | I_EMPTY_MAP
    | I_EMPTY_SET
    | I_EQ
    | I_EXEC
    | I_APPLY
    | I_FAILWITH
    | I_GE
    | I_GET
    | I_GT
    | I_HASH_KEY
    | I_IF
    | I_IF_CONS
    | I_IF_LEFT
    | I_IF_NONE
    | I_INT
    | I_LAMBDA
    | I_LE
    | I_LEFT
    | I_LEVEL
    | I_LOOP
    | I_LSL
    | I_LSR
    | I_LT
    | I_MAP
    | I_MEM
    | I_MUL
    | I_NEG
    | I_NEQ
    | I_NIL
    | I_NONE
    | I_NOT
    | I_NOW
    | I_OR
    | I_PAIR
    | I_UNPAIR
    | I_PUSH
    | I_RIGHT
    | I_SIZE
    | I_SOME
    | I_SOURCE
    | I_SENDER
    | I_SELF
    | I_SELF_ADDRESS
    | I_SLICE
    | I_STEPS_TO_QUOTA
    | I_SUB
    | I_SWAP
    | I_TRANSFER_TOKENS
    | I_SET_DELEGATE
    | I_UNIT
    | I_UPDATE
    | I_XOR
    | I_ITER
    | I_LOOP_LEFT
    | I_ADDRESS
    | I_CONTRACT
    | I_ISNAT
    | I_CAST
    | I_RENAME
    | I_SAPLING_EMPTY_STATE
    | I_SAPLING_VERIFY_UPDATE
    | I_DIG
    | I_DUG
    | I_NEVER
    | I_VOTING_POWER
    | I_TOTAL_VOTING_POWER
    | I_KECCAK
    | I_SHA3
    | I_PAIRING_CHECK
    | I_SUBMIT_PROPOSALS
    | I_SUBMIT_BALLOT
    | I_SET_BAKER_ACTIVE
    | I_TOGGLE_BAKER_DELEGATIONS
    | I_SET_BAKER_CONSENSUS_KEY
    | I_SET_BAKER_PVSS_KEY
    | T_bool
    | T_contract
    | T_int
    | T_key
    | T_key_hash
    | T_lambda
    | T_list
    | T_map
    | T_big_map
    | T_nat
    | T_option
    | T_or
    | T_pair
    | T_set
    | T_signature
    | T_string
    | T_bytes
    | T_mutez
    | T_timestamp
    | T_unit
    | T_operation
    | T_address
    | T_sapling_transaction
    | T_sapling_state
    | T_chain_id
    | T_never
    | T_bls12_381_g1
    | T_bls12_381_g2
    | T_bls12_381_fr
    | T_baker_hash
    | T_baker_operation
    | T_pvss_key

  type location = Micheline.canonical_location

  type annot = Micheline.annot

  type expr = prim Micheline.canonical

  type lazy_expr = expr Data_encoding.lazy_t

  val lazy_expr : expr -> lazy_expr

  type node = (location, prim) Micheline.node

  type t = {code : lazy_expr; storage : lazy_expr}

  val location_encoding : location Data_encoding.t

  val expr_encoding : expr Data_encoding.t

  val prim_encoding : prim Data_encoding.t

  val encoding : t Data_encoding.t

  val lazy_expr_encoding : lazy_expr Data_encoding.t

  val deserialized_cost : expr -> Gas.cost

  val serialized_cost : bytes -> Gas.cost

  val traversal_cost : node -> Gas.cost

  val node_cost : node -> Gas.cost

  val int_node_cost : Z.t -> Gas.cost

  val int_node_cost_of_numbits : int -> Gas.cost

  val string_node_cost : string -> Gas.cost

  val string_node_cost_of_length : int -> Gas.cost

  val bytes_node_cost : bytes -> Gas.cost

  val bytes_node_cost_of_length : int -> Gas.cost

  val prim_node_cost_nonrec : expr list -> annot -> Gas.cost

  val prim_node_cost_nonrec_of_length : int -> annot -> Gas.cost

  val seq_node_cost_nonrec : expr list -> Gas.cost

  val seq_node_cost_nonrec_of_length : int -> Gas.cost

  val minimal_deserialize_cost : lazy_expr -> Gas.cost

  val force_decode_in_context :
    context -> lazy_expr -> (expr * context) tzresult

  val force_bytes_in_context :
    context -> lazy_expr -> (bytes * context) tzresult

  val unit_parameter : lazy_expr
end

module Constants : sig
  (** Fixed constants *)
  type fixed = {
    proof_of_work_nonce_size : int;
    nonce_length : int;
    max_anon_ops_per_block : int;
    max_operation_data_length : int;
    max_proposals_per_delegate : int;
    votes_per_roll : int;
  }

  val fixed_encoding : fixed Data_encoding.t

  val fixed : fixed

  val proof_of_work_nonce_size : int

  val nonce_length : int

  val max_anon_ops_per_block : int

  val max_operation_data_length : int

  val max_proposals_per_delegate : int

  (** Constants parameterized by context *)
  type parametric = {
    preserved_cycles : int;
    blocks_per_cycle : int32;
    blocks_per_commitment : int32;
    blocks_per_roll_snapshot : int32;
    blocks_per_voting_period : int32;
    time_between_blocks : Period.t list;
    endorsers_per_block : int;
    hard_gas_limit_per_operation : Z.t;
    hard_gas_limit_per_block : Z.t;
    proof_of_work_threshold : int64;
    tokens_per_roll : Tez.t;
    michelson_maximum_type_size : int;
    seed_nonce_revelation_tip : Tez.t;
    origination_size : int;
    block_security_deposit : Tez.t;
    endorsement_security_deposit : Tez.t;
    baking_reward_per_endorsement : Tez.t list;
    endorsement_reward : Tez.t list;
    cost_per_byte : Tez.t;
    hard_storage_limit_per_operation : Z.t;
    test_chain_duration : int64;
    quorum_min : int32;
    quorum_max : int32;
    min_proposal_quorum : int32;
    initial_endorsers : int;
    delay_per_missing_endorsement : Period.t;
  }

  val parametric_encoding : parametric Data_encoding.t

  val parametric : context -> parametric

  val preserved_cycles : context -> int

  val blocks_per_cycle : context -> int32

  val blocks_per_commitment : context -> int32

  val blocks_per_roll_snapshot : context -> int32

  val blocks_per_voting_period : context -> int32

  val time_between_blocks : context -> Period.t list

  val endorsers_per_block : context -> int

  val initial_endorsers : context -> int

  val delay_per_missing_endorsement : context -> Period.t

  val hard_gas_limit_per_operation : context -> Z.t

  val hard_gas_limit_per_block : context -> Z.t

  val cost_per_byte : context -> Tez.t

  val hard_storage_limit_per_operation : context -> Z.t

  val proof_of_work_threshold : context -> int64

  val tokens_per_roll : context -> Tez.t

  val michelson_maximum_type_size : context -> int

  val baking_reward_per_endorsement : context -> Tez.t list

  val endorsement_reward : context -> Tez.t list

  val seed_nonce_revelation_tip : context -> Tez.t

  val origination_size : context -> int

  val block_security_deposit : context -> Tez.t

  val endorsement_security_deposit : context -> Tez.t

  val test_chain_duration : context -> int64

  val quorum_min : context -> int32

  val quorum_max : context -> int32

  val min_proposal_quorum : context -> int32

  (** All constants: fixed and parametric *)
  type t = {fixed : fixed; parametric : parametric}

  val encoding : t Data_encoding.t
end

module Voting_period : sig
  include BASIC_DATA

  type voting_period = t

  val rpc_arg : voting_period RPC_arg.arg

  val root : voting_period

  val succ : voting_period -> voting_period

  type kind = Proposal | Testing_vote | Testing | Promotion_vote | Adoption

  val kind_encoding : kind Data_encoding.encoding

  val to_int32 : voting_period -> int32
end

module Level : sig
  type t = private {
    level : Raw_level.t;
    level_position : int32;
    cycle : Cycle.t;
    cycle_position : int32;
    voting_period : Voting_period.t;
    voting_period_position : int32;
    expected_commitment : bool;
  }

  include BASIC_DATA with type t := t

  val pp_full : Format.formatter -> t -> unit

  type level = t

  val root : context -> level

  val succ : context -> level -> level

  val pred : context -> level -> level option

  val from_raw : context -> ?offset:int32 -> Raw_level.t -> level

  val diff : level -> level -> int32

  val current : context -> level

  val last_level_in_cycle : context -> Cycle.t -> level

  val levels_in_cycle : context -> Cycle.t -> level list

  val levels_in_current_cycle : context -> ?offset:int32 -> unit -> level list

  val last_allowed_fork_level : context -> Raw_level.t
end

module Fitness : sig
  include module type of Fitness

  type fitness = t

  val increase : ?gap:int -> context -> context

  val current : context -> int64

  val to_int64 : fitness -> int64 tzresult
end

module Nonce : sig
  type t

  type nonce = t

  val encoding : nonce Data_encoding.t

  type unrevealed = {
    nonce_hash : Nonce_hash.t;
    baker : baker_hash;
    rewards : Tez.t;
    fees : Tez.t;
  }

  val record_hash : context -> unrevealed -> context tzresult Lwt.t

  val reveal : context -> Level.t -> nonce -> context tzresult Lwt.t

  type status = Unrevealed of unrevealed | Revealed of nonce

  val get : context -> Level.t -> status tzresult Lwt.t

  val of_bytes : bytes -> nonce tzresult

  val hash : nonce -> Nonce_hash.t

  val check_hash : nonce -> Nonce_hash.t -> bool
end

module Seed : sig
  type seed

  type error +=
    | Unknown of {oldest : Cycle.t; cycle : Cycle.t; latest : Cycle.t}

  val for_cycle : context -> Cycle.t -> seed tzresult Lwt.t

  val cycle_end :
    context -> Cycle.t -> (context * Nonce.unrevealed list) tzresult Lwt.t

  val seed_encoding : seed Data_encoding.t
end

module Big_map : sig
  module Id : sig
    type t

    val encoding : t Data_encoding.t

    val rpc_arg : t RPC_arg.arg

    (** In the protocol, to be used in parse_data only *)
    val parse_z : Z.t -> t

    (** In the protocol, to be used in unparse_data only *)
    val unparse_to_z : t -> Z.t
  end

  val fresh : temporary:bool -> context -> (context * Id.t) tzresult Lwt.t

  val mem :
    context -> Id.t -> Script_expr_hash.t -> (context * bool) tzresult Lwt.t

  val get_opt :
    context ->
    Id.t ->
    Script_expr_hash.t ->
    (context * Script.expr option) tzresult Lwt.t

  val exists :
    context ->
    Id.t ->
    (context * (Script.expr * Script.expr) option) tzresult Lwt.t

  type update = {
    key : Script_repr.expr;
    key_hash : Script_expr_hash.t;
    value : Script_repr.expr option;
  }

  type updates = update list

  type alloc = {key_type : Script_repr.expr; value_type : Script_repr.expr}
end

module Sapling : sig
  module Id : sig
    type t

    val encoding : t Data_encoding.t

    val rpc_arg : t RPC_arg.arg

    val parse_z : Z.t -> t (* To be used in parse_data only *)

    val unparse_to_z : t -> Z.t (* To be used in unparse_data only *)
  end

  val fresh : temporary:bool -> context -> (context * Id.t) tzresult Lwt.t

  type diff = private {
    commitments : Sapling.Commitment.t list;
    ciphertexts : Sapling.Ciphertext.t list;
    nullifiers : Sapling.Nullifier.t list;
  }

  val diff_encoding : diff Data_encoding.t

  val empty_diff : diff

  type state = private {id : Id.t option; diff : diff; memo_size : int}

  type memo_size = {memo_size : int}

  (**
    Returns a [state] with fields filled accordingly.
    [id] should only be used by [extract_lazy_storage_updates].
    [diff] should only be used by [unparse_data].
  *)
  val empty_state : ?id:Id.t -> ?diff:diff -> memo_size:int -> unit -> state

  type transaction = Sapling.UTXO.transaction

  val transaction_encoding : transaction Data_encoding.t

  (**
    Tries to fetch a state from the storage.
    [diff] should only be used by [unparse_data].
  *)
  val state_from_id :
    context -> ?diff:diff -> Id.t -> (state * context) tzresult Lwt.t

  val rpc_arg : Id.t RPC_arg.t

  type root = Sapling.Hash.t

  val root_encoding : root Data_encoding.t

  (* Function exposed as RPC. Returns the root and a diff of a state starting
     from an optional offset which is zero by default. *)
  val get_diff :
    context ->
    Id.t ->
    ?offset_commitment:Int64.t ->
    ?offset_nullifier:Int64.t ->
    unit ->
    (root * diff) tzresult Lwt.t

  val verify_update :
    context ->
    state ->
    transaction ->
    string ->
    (context * (Int64.t * state) option) tzresult Lwt.t

  type alloc = memo_size

  type updates = diff
end

module Lazy_storage : sig
  module Kind : sig
    type ('id, 'alloc, 'updates) t =
      | Big_map : (Big_map.Id.t, Big_map.alloc, Big_map.updates) t
      | Sapling_state : (Sapling.Id.t, Sapling.alloc, Sapling.updates) t
  end

  module KId : sig
    type t = E : ('id, _, _) Kind.t * 'id -> t

    module Comparable : Compare.COMPARABLE with type t = t
  end

  type ('id, 'alloc) init = Existing | Copy of {src : 'id} | Alloc of 'alloc

  type ('id, 'alloc, 'updates) diff =
    | Remove
    | Update of {init : ('id, 'alloc) init; updates : 'updates}

  type diffs_item

  val make : ('i, 'a, 'u) Kind.t -> 'i -> ('i, 'a, 'u) diff -> diffs_item

  val make_remove : KId.t -> diffs_item

  type diffs = diffs_item list

  val encoding : diffs Data_encoding.t

  val legacy_big_map_diff_encoding : diffs Data_encoding.t

  val cleanup_temporaries : context -> context Lwt.t

  val apply : t -> diffs -> (t * Z.t) tzresult Lwt.t
end

module Contract : sig
  include BASIC_DATA

  type contract = t

  val rpc_arg : contract RPC_arg.arg

  val to_b58check : contract -> string

  val of_b58check : string -> contract tzresult

  val implicit_contract : public_key_hash -> contract

  val baker_contract : baker_hash -> contract

  val is_implicit : contract -> public_key_hash option

  val is_baker : contract -> baker_hash option

  val exists : context -> contract -> bool tzresult Lwt.t

  val must_exist : context -> contract -> unit tzresult Lwt.t

  val allocated : context -> contract -> bool tzresult Lwt.t

  val must_be_allocated : context -> contract -> unit tzresult Lwt.t

  val list : context -> contract list Lwt.t

  val get_public_key : context -> contract -> public_key tzresult Lwt.t

  val is_public_key_revealed : context -> contract -> bool tzresult Lwt.t

  val reveal_public_key :
    context -> public_key_hash -> public_key -> context tzresult Lwt.t

  val get_script_code :
    context -> contract -> (context * Script.lazy_expr option) tzresult Lwt.t

  val get_script_code_cached : context -> contract -> Script.expr option

  val init_set_script_code_cached :
    context -> contract -> Script.expr -> context

  val clear_script_code_cached : context -> context

  val get_script :
    context -> contract -> (context * Script.t option) tzresult Lwt.t

  val get_storage :
    context -> contract -> (context * Script.expr option) tzresult Lwt.t

  val get_storage_cached : context -> contract -> Script.expr option

  val init_set_storage_cached : context -> contract -> Script.expr -> context

  val clear_storage_cached : context -> context

  val get_counter : context -> contract -> Z.t tzresult Lwt.t

  val get_global_counter : context -> Z.t tzresult Lwt.t

  val get_balance : context -> contract -> Tez.t tzresult Lwt.t

  val init_origination_nonce : context -> Operation_hash.t -> context

  val unset_origination_nonce : context -> context

  val fresh_contract_from_current_nonce : context -> (context * t) tzresult

  val originated_from_current_nonce :
    since:context -> until:context -> contract list tzresult Lwt.t

  module Legacy_big_map_diff : sig
    type item = private
      | Update of {
          big_map : Z.t;
          diff_key : Script.expr;
          diff_key_hash : Script_expr_hash.t;
          diff_value : Script.expr option;
        }
      | Clear of Z.t
      | Copy of {src : Z.t; dst : Z.t}
      | Alloc of {
          big_map : Z.t;
          key_type : Script.expr;
          value_type : Script.expr;
        }

    type t = private item list

    val of_lazy_storage_diff : Lazy_storage.diffs -> t
  end

  val originate :
    context ->
    contract ->
    balance:Tez.t ->
    script:Script.t * Lazy_storage.diffs option ->
    delegate:baker_hash option ->
    context tzresult Lwt.t

  type error += Balance_too_low of contract * Tez.t * Tez.t

  val spend : context -> contract -> Tez.t -> context tzresult Lwt.t

  val credit : context -> contract -> Tez.t -> context tzresult Lwt.t

  val update_script_storage :
    context ->
    contract ->
    Script.expr ->
    Lazy_storage.diffs option ->
    context tzresult Lwt.t

  val used_storage_space : context -> t -> Z.t tzresult Lwt.t

  val increment_counter : context -> contract -> context tzresult Lwt.t

  val check_counter_increment :
    context -> contract -> Z.t -> unit tzresult Lwt.t

  (**/**)

  (* Only for testing *)
  type origination_nonce

  val incr_origination_nonce : origination_nonce -> origination_nonce

  val initial_origination_nonce : Operation_hash.t -> origination_nonce

  val originated_contract : origination_nonce -> contract

  val baker_from_nonce : origination_nonce -> baker_hash
end

module Receipt : sig
  type balance =
    | Contract of Contract.t
    | Rewards of baker_hash * Cycle.t
    | Fees of baker_hash * Cycle.t
    | Deposits of baker_hash * Cycle.t

  type balance_update = Debited of Tez.t | Credited of Tez.t

  type balance_updates = (balance * balance_update) list

  val balance_updates_encoding : balance_updates Data_encoding.t

  val cleanup_balance_updates : balance_updates -> balance_updates
end

module Delegation : sig
  val get : context -> Contract.t -> baker_hash option tzresult Lwt.t

  val set :
    context -> Contract.t -> baker_hash option -> context tzresult Lwt.t
end

module Baker : sig
  val register :
    ?baker_hash:baker_hash ->
    ?prepaid_bootstrap_storage:bool ->
    context ->
    balance:Tez.t ->
    threshold:int ->
    owner_keys:public_key list ->
    consensus_key:public_key ->
    (context * baker_hash) tzresult Lwt.t

  val set_active : context -> baker_hash -> bool -> context tzresult Lwt.t

  val toggle_delegations :
    context -> baker_hash -> bool -> context tzresult Lwt.t

  val fold : context -> init:'a -> f:(baker_hash -> 'a -> 'a Lwt.t) -> 'a Lwt.t

  val list : context -> baker_hash list Lwt.t

  val freeze_deposit : context -> baker_hash -> Tez.t -> context tzresult Lwt.t

  val freeze_rewards : context -> baker_hash -> Tez.t -> context tzresult Lwt.t

  val freeze_fees : context -> baker_hash -> Tez.t -> context tzresult Lwt.t

  val cycle_end :
    context ->
    Cycle.t ->
    Nonce.unrevealed list ->
    (context * Receipt.balance_updates * baker_hash list) tzresult Lwt.t

  type frozen_balance = {deposit : Tez.t; fees : Tez.t; rewards : Tez.t}

  val punish :
    context ->
    baker_hash ->
    Cycle.t ->
    (context * frozen_balance) tzresult Lwt.t

  val full_balance : context -> baker_hash -> Tez.t tzresult Lwt.t

  val has_frozen_balance :
    context -> baker_hash -> Cycle.t -> bool tzresult Lwt.t

  val frozen_balance : context -> baker_hash -> Tez.t tzresult Lwt.t

  val frozen_balance_encoding : frozen_balance Data_encoding.t

  val frozen_balance_by_cycle_encoding :
    frozen_balance Cycle.Map.t Data_encoding.t

  val frozen_balance_by_cycle :
    context -> baker_hash -> frozen_balance Cycle.Map.t Lwt.t

  val staking_balance : context -> baker_hash -> Tez.t tzresult Lwt.t

  val delegated_contracts : context -> baker_hash -> Contract_repr.t list Lwt.t

  val delegated_balance : context -> baker_hash -> Tez.t tzresult Lwt.t

  val deactivated : context -> baker_hash -> bool tzresult Lwt.t

  val grace_period : context -> baker_hash -> Cycle.t tzresult Lwt.t

  module Proof : sig
    val mem : context -> baker_hash -> Raw_level.t -> bool tzresult Lwt.t

    val add : context -> baker_hash -> Raw_level.t -> context tzresult Lwt.t

    val cleanup : context -> context tzresult Lwt.t

    val all : context -> baker_hash -> Raw_level.LSet.t tzresult Lwt.t
  end

  val get_consensus_key :
    ?level:Raw_level.t ->
    ?offset:int32 ->
    context ->
    baker_hash ->
    public_key tzresult Lwt.t

  val set_consensus_key :
    context -> baker_hash -> public_key -> context tzresult Lwt.t

  val is_consensus_key :
    context -> public_key_hash -> baker_hash option tzresult Lwt.t

  val is_pending_consensus_key : context -> Contract.t -> bool tzresult Lwt.t

  val get_pvss_key :
    context -> baker_hash -> Pvss_secp256k1.Public_key.t option tzresult Lwt.t

  val init_set_pvss_key :
    context -> baker_hash -> Pvss_secp256k1.Public_key.t -> context Lwt.t
end

module Vote : sig
  type proposal = Protocol_hash.t

  val record_proposal :
    context -> Protocol_hash.t -> baker_hash -> context tzresult Lwt.t

  val get_proposals : context -> int32 Protocol_hash.Map.t tzresult Lwt.t

  val clear_proposals : context -> context Lwt.t

  val recorded_proposal_count_for_baker :
    context -> baker_hash -> int tzresult Lwt.t

  val listings_encoding : (Contract.t * int32) list Data_encoding.t

  val update_listings : context -> context tzresult Lwt.t

  val listing_size : context -> int32 tzresult Lwt.t

  val in_listings : context -> Contract.t -> bool Lwt.t

  val get_listings : context -> (Contract.t * int32) list Lwt.t

  type ballot = {
    yays_per_roll : int;
    nays_per_roll : int;
    passes_per_roll : int;
  }

  val get_voting_power_free : context -> baker_hash -> int32 tzresult Lwt.t

  val get_voting_power :
    context -> baker_hash -> (context * int32) tzresult Lwt.t

  val get_total_voting_power_free : context -> int32 tzresult Lwt.t

  val get_total_voting_power : context -> (context * int32) tzresult Lwt.t

  val ballot_encoding : ballot Data_encoding.t

  type ballots = {yay : int32; nay : int32; pass : int32}

  val zero_ballots : ballots

  val ballots_encoding : ballots Data_encoding.t

  val count : ballot -> int32 -> ballots -> ballots

  val get_ballots : context -> ballots tzresult Lwt.t

  val has_recorded_ballot : context -> Contract.t -> bool Lwt.t

  val record_ballot : context -> Contract.t -> ballot -> context tzresult Lwt.t

  val get_ballot_list : context -> (Contract.t * ballot) list Lwt.t

  val clear_ballots : context -> context Lwt.t

  val get_current_period_kind : context -> Voting_period.kind tzresult Lwt.t

  val set_current_period_kind :
    context -> Voting_period.kind -> context tzresult Lwt.t

  val get_current_quorum : context -> int32 tzresult Lwt.t

  val get_participation_ema : context -> int32 tzresult Lwt.t

  val set_participation_ema : context -> int32 -> context tzresult Lwt.t

  val get_current_proposal : context -> proposal tzresult Lwt.t

  val init_current_proposal : context -> proposal -> context tzresult Lwt.t

  val clear_current_proposal : context -> context tzresult Lwt.t
end

module Block_header : sig
  type contents = {
    priority : int;
    seed_nonce_hash : Nonce_hash.t option;
    proof_of_work_nonce : bytes;
  }

  type protocol_data = {contents : contents; signature : Signature.t}

  type t = {shell : Block_header.shell_header; protocol_data : protocol_data}

  type block_header = t

  type raw = Block_header.t

  type shell_header = Block_header.shell_header

  val raw : block_header -> raw

  val hash : block_header -> Block_hash.t

  val hash_raw : raw -> Block_hash.t

  val encoding : block_header Data_encoding.encoding

  val raw_encoding : raw Data_encoding.t

  val contents_encoding : contents Data_encoding.t

  val unsigned_encoding : (shell_header * contents) Data_encoding.t

  val protocol_data_encoding : protocol_data Data_encoding.encoding

  val shell_header_encoding : shell_header Data_encoding.encoding

  (** The maximum size of block headers in bytes *)
  val max_header_length : int
end

module Kind : sig
  type seed_nonce_revelation = Seed_nonce_revelation_kind

  type double_endorsement_evidence = Double_endorsement_evidence_kind

  type double_baking_evidence = Double_baking_evidence_kind

  type activate_account = Activate_account_kind

  type endorsement = Endorsement_kind

  type proposals = Proposals_kind

  type ballot = Ballot_kind

  type reveal = Reveal_kind

  type transaction = Transaction_kind

  type origination_legacy = Origination_legacy_kind

  type origination = Origination_kind

  type delegation_legacy = Delegation_legacy_kind

  type delegation = Delegation_kind

  type failing_noop = Failing_noop_kind

  type baker_registration = Baker_registration_kind

  type set_baker_active = Set_baker_active_kind

  type toggle_baker_delegations = Toggle_baker_delegations_kind

  type set_baker_consensus_key = Set_baker_consensus_key_kind

  type set_baker_pvss_key = Set_baker_pvss_key_kind

  type 'a manager =
    | Reveal_manager_kind : reveal manager
    | Transaction_manager_kind : transaction manager
    | Origination_legacy_manager_kind : origination_legacy manager
    | Origination_manager_kind : origination manager
    | Delegation_legacy_manager_kind : delegation_legacy manager
    | Delegation_manager_kind : delegation manager
    | Baker_registration_manager_kind : baker_registration manager
    | Ballot_manager_kind : ballot manager

  type 'a baker =
    | Baker_proposals_kind : proposals baker
    | Baker_ballot_kind : ballot baker
    | Set_baker_active_baker_kind : set_baker_active baker
    | Toggle_baker_delegations_baker_kind : toggle_baker_delegations baker
    | Set_baker_consensus_key_baker_kind : set_baker_consensus_key baker
    | Set_baker_pvss_key_baker_kind : set_baker_pvss_key baker
end

type 'kind operation = {
  shell : Operation.shell_header;
  protocol_data : 'kind protocol_data;
}

and 'kind protocol_data = {
  contents : 'kind contents_list;
  signature : Signature.t option;
}

and _ contents_list =
  | Single : 'kind contents -> 'kind contents_list
  | Cons :
      'kind Kind.manager contents * 'rest Kind.manager contents_list
      -> ('kind * 'rest) Kind.manager contents_list

and _ contents =
  | Endorsement : {level : Raw_level.t} -> Kind.endorsement contents
  | Seed_nonce_revelation : {
      level : Raw_level.t;
      nonce : Nonce.t;
    }
      -> Kind.seed_nonce_revelation contents
  | Double_endorsement_evidence : {
      op1 : Kind.endorsement operation;
      op2 : Kind.endorsement operation;
    }
      -> Kind.double_endorsement_evidence contents
  | Double_baking_evidence : {
      bh1 : Block_header.t;
      bh2 : Block_header.t;
    }
      -> Kind.double_baking_evidence contents
  | Activate_account : {
      id : Ed25519.Public_key_hash.t;
      activation_code : Blinded_public_key_hash.activation_code;
    }
      -> Kind.activate_account contents
  | Proposals : {
      source : public_key_hash;
      period : Voting_period.t;
      proposals : Protocol_hash.t list;
    }
      -> Kind.proposals contents
  | Ballot : {
      source : public_key_hash;
      period : Voting_period.t;
      proposal : Protocol_hash.t;
      ballot : Vote.ballot;
    }
      -> Kind.ballot contents
  | Failing_noop : string -> Kind.failing_noop contents
  | Manager_operation : {
      source : public_key_hash;
      fee : Tez.tez;
      counter : counter;
      operation : 'kind manager_operation;
      gas_limit : Z.t;
      storage_limit : Z.t;
    }
      -> 'kind Kind.manager contents

and _ manager_operation =
  | Reveal : Signature.Public_key.t -> Kind.reveal manager_operation
  | Transaction : {
      amount : Tez.tez;
      parameters : Script.lazy_expr;
      entrypoint : string;
      destination : Contract.contract;
    }
      -> Kind.transaction manager_operation
  | Origination_legacy : {
      delegate : public_key_hash option;
      script : Script.t;
      credit : Tez.tez;
      preorigination : Contract.t option;
    }
      -> Kind.origination_legacy manager_operation
  | Origination : {
      delegate : baker_hash option;
      script : Script.t;
      credit : Tez.tez;
      preorigination : Contract.t option;
    }
      -> Kind.origination manager_operation
  | Delegation_legacy :
      public_key_hash option
      -> Kind.delegation_legacy manager_operation
  | Delegation : baker_hash option -> Kind.delegation manager_operation
  | Baker_registration : {
      credit : Tez.tez;
      consensus_key : public_key;
      threshold : int;
      owner_keys : Signature.Public_key.t list;
    }
      -> Kind.baker_registration manager_operation
  | Ballot_override : {
      period : Voting_period.t;
      proposal : Protocol_hash.t;
      ballot : Vote.ballot;
    }
      -> Kind.ballot manager_operation

and _ baker_operation =
  | Baker_proposals : {
      period : Voting_period.t;
      proposals : string list;
    }
      -> Kind.proposals baker_operation
  | Baker_ballot : {
      period : Voting_period.t;
      proposal : string;
      ballot : Vote.ballot;
    }
      -> Kind.ballot baker_operation
  | Set_baker_active : bool -> Kind.set_baker_active baker_operation
  | Toggle_baker_delegations :
      bool
      -> Kind.toggle_baker_delegations baker_operation
  | Set_baker_consensus_key :
      public_key
      -> Kind.set_baker_consensus_key baker_operation
  | Set_baker_pvss_key :
      Pvss_secp256k1.Public_key.t
      -> Kind.set_baker_pvss_key baker_operation

and counter = Z.t

type 'kind internal_manager_operation = {
  source : Contract.contract;
  operation : 'kind manager_operation;
  nonce : int;
}

type 'kind internal_baker_operation = {
  baker : Baker_hash.t;
  operation : 'kind baker_operation;
  nonce : int;
}

type packed_manager_operation =
  | Manager : 'kind manager_operation -> packed_manager_operation

type packed_baker_operation =
  | Baker : 'kind baker_operation -> packed_baker_operation

type packed_contents = Contents : 'kind contents -> packed_contents

type packed_contents_list =
  | Contents_list : 'kind contents_list -> packed_contents_list

type packed_protocol_data =
  | Operation_data : 'kind protocol_data -> packed_protocol_data

type packed_operation = {
  shell : Operation.shell_header;
  protocol_data : packed_protocol_data;
}

type packed_internal_operation =
  | Internal_manager_operation :
      'kind internal_manager_operation
      -> packed_internal_operation
  | Internal_baker_operation :
      'kind internal_baker_operation
      -> packed_internal_operation

val manager_kind : 'kind manager_operation -> 'kind Kind.manager

val baker_kind : 'kind baker_operation -> 'kind Kind.baker

module Fees : sig
  val origination_burn : context -> (context * Tez.t) tzresult

  val record_paid_storage_space :
    context -> Contract.t -> (context * Z.t * Z.t * Tez.t) tzresult Lwt.t

  val start_counting_storage_fees : context -> context

  val burn_storage_fees :
    context -> storage_limit:Z.t -> payer:Contract.t -> context tzresult Lwt.t

  type error += Cannot_pay_storage_fee (* `Temporary *)

  type error += Operation_quota_exceeded (* `Temporary *)

  type error += Storage_limit_too_high (* `Permanent *)

  val check_storage_limit : context -> storage_limit:Z.t -> unit tzresult
end

module Operation : sig
  type nonrec 'kind contents = 'kind contents

  type nonrec packed_contents = packed_contents

  val contents_encoding : packed_contents Data_encoding.t

  type nonrec 'kind protocol_data = 'kind protocol_data

  type nonrec packed_protocol_data = packed_protocol_data

  val protocol_data_encoding : packed_protocol_data Data_encoding.t

  val unsigned_encoding :
    (Operation.shell_header * packed_contents_list) Data_encoding.t

  type raw = Operation.t = {shell : Operation.shell_header; proto : bytes}

  val raw_encoding : raw Data_encoding.t

  val contents_list_encoding : packed_contents_list Data_encoding.t

  type 'kind t = 'kind operation = {
    shell : Operation.shell_header;
    protocol_data : 'kind protocol_data;
  }

  type nonrec packed = packed_operation

  val encoding : packed Data_encoding.t

  val raw : _ operation -> raw

  val hash : _ operation -> Operation_hash.t

  val hash_raw : raw -> Operation_hash.t

  val hash_packed : packed_operation -> Operation_hash.t

  val acceptable_passes : packed_operation -> int list

  type error += Missing_signature (* `Permanent *)

  type error += Invalid_signature (* `Permanent *)

  val check_signature :
    public_key -> Chain_id.t -> _ operation -> unit tzresult

  val internal_operation_encoding : packed_internal_operation Data_encoding.t

  val pack : 'kind operation -> packed_operation

  type ('a, 'b) eq = Eq : ('a, 'a) eq

  val equal : 'a operation -> 'b operation -> ('a, 'b) eq option

  module Encoding : sig
    type 'b case =
      | Case : {
          tag : int;
          name : string;
          encoding : 'a Data_encoding.t;
          select : packed_contents -> 'b contents option;
          proj : 'b contents -> 'a;
          inj : 'a -> 'b contents;
        }
          -> 'b case

    val endorsement_case : Kind.endorsement case

    val seed_nonce_revelation_case : Kind.seed_nonce_revelation case

    val double_endorsement_evidence_case :
      Kind.double_endorsement_evidence case

    val double_baking_evidence_case : Kind.double_baking_evidence case

    val activate_account_case : Kind.activate_account case

    val proposals_case : Kind.proposals case

    val ballot_case : Kind.ballot case

    val failing_noop_case : Kind.failing_noop case

    val reveal_case : Kind.reveal Kind.manager case

    val transaction_case : Kind.transaction Kind.manager case

    val origination_legacy_case : Kind.origination_legacy Kind.manager case

    val origination_case : Kind.origination Kind.manager case

    val delegation_legacy_case : Kind.delegation_legacy Kind.manager case

    val delegation_case : Kind.delegation Kind.manager case

    val baker_registration_case : Kind.baker_registration Kind.manager case

    val ballot_override_case : Kind.ballot Kind.manager case

    module Manager_operations : sig
      type 'b case =
        | MCase : {
            tag : int;
            name : string;
            encoding : 'a Data_encoding.t;
            select :
              packed_manager_operation -> 'kind manager_operation option;
            proj : 'kind manager_operation -> 'a;
            inj : 'a -> 'kind manager_operation;
          }
            -> 'kind case

      val reveal_case : Kind.reveal case

      val transaction_case : Kind.transaction case

      val origination_legacy_case : Kind.origination_legacy case

      val origination_case : Kind.origination case

      val delegation_legacy_case : Kind.delegation_legacy case

      val delegation_case : Kind.delegation case

      val baker_registration_case : Kind.baker_registration case

      val ballot_override_case : Kind.ballot case
    end

    module Baker_operations : sig
      type 'b case =
        | BCase : {
            tag : int;
            name : string;
            encoding : 'a Data_encoding.t;
            select : packed_baker_operation -> 'kind baker_operation option;
            proj : 'kind baker_operation -> 'a;
            inj : 'a -> 'kind baker_operation;
          }
            -> 'kind case

      val baker_proposals_case : Kind.proposals case

      val baker_ballot_case : Kind.ballot case

      val set_baker_active_case : Kind.set_baker_active case

      val toggle_baker_delegations_case : Kind.toggle_baker_delegations case

      val set_baker_consensus_key_case : Kind.set_baker_consensus_key case

      val set_baker_pvss_key_case : Kind.set_baker_pvss_key case
    end
  end

  val of_list : packed_contents list -> packed_contents_list

  val to_list : packed_contents_list -> packed_contents list
end

module Roll : sig
  type t = private int32

  type roll = t

  val encoding : roll Data_encoding.t

  val snapshot_rolls : context -> context tzresult Lwt.t

  val cycle_end : context -> Cycle.t -> context tzresult Lwt.t

  val baking_rights_owner :
    context -> Level.t -> priority:int -> baker_hash tzresult Lwt.t

  val endorsement_rights_owner :
    context -> Level.t -> slot:int -> baker_hash tzresult Lwt.t

  val get_rolls : context -> baker_hash -> roll list tzresult Lwt.t

  val get_change : context -> baker_hash -> Tez.t tzresult Lwt.t
end

module Commitment : sig
  type t = {
    blinded_public_key_hash : Blinded_public_key_hash.t;
    amount : Tez.tez;
  }

  val get_opt :
    context -> Blinded_public_key_hash.t -> Tez.t option tzresult Lwt.t

  val delete : context -> Blinded_public_key_hash.t -> context tzresult Lwt.t
end

module Bootstrap : sig
  val cycle_end : context -> Cycle.t -> context tzresult Lwt.t
end

module Global : sig
  val get_block_priority : context -> int tzresult Lwt.t

  val set_block_priority : context -> int -> context tzresult Lwt.t
end

val prepare_first_block :
  Context.t ->
  typecheck:(context ->
            Script.t ->
            ((Script.t * Lazy_storage.diffs option) * context) tzresult Lwt.t) ->
  level:Int32.t ->
  timestamp:Time.t ->
  fitness:Fitness.t ->
  context tzresult Lwt.t

val prepare :
  Context.t ->
  level:Int32.t ->
  predecessor_timestamp:Time.t ->
  timestamp:Time.t ->
  fitness:Fitness.t ->
  (context * Receipt.balance_updates) tzresult Lwt.t

val finalize : ?commit_message:string -> context -> Updater.validation_result

val activate : context -> Protocol_hash.t -> context Lwt.t

val fork_test_chain : context -> Protocol_hash.t -> Time.t -> context Lwt.t

val record_endorsement : context -> Baker_hash.t -> context

val allowed_endorsements : context -> (int list * bool) Baker_hash.Map.t

val init_endorsements :
  context -> (int list * bool) Baker_hash.Map.t -> context

val included_endorsements : context -> int

val reset_internal_nonce : context -> context

val fresh_internal_nonce : context -> (context * int) tzresult

val record_internal_nonce : context -> int -> context

val internal_nonce_already_recorded : context -> int -> bool

val add_fees : context -> Tez.t -> context tzresult

val add_rewards : context -> Tez.t -> context tzresult

val add_deposit : context -> baker_hash -> Tez.t -> context tzresult

val get_fees : context -> Tez.t

val get_rewards : context -> Tez.t

val get_deposits : context -> Tez.t Baker_hash.Map.t

val description : context Storage_description.t
