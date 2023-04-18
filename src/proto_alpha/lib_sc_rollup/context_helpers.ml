(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

module In_memory = struct
  open Tezos_context_memory

  module Tree = struct
    include Context_binary.Tree

    type tree = Context_binary.tree

    type t = Context_binary.t

    type key = string list

    type value = bytes
  end

  type tree = Tree.tree

  type proof = Context.Proof.tree Context.Proof.t

  let hash_tree _ = assert false

  let verify_proof p f =
    Lwt.map Result.to_option (Context_binary.verify_tree_proof p f)

  let produce_proof context state step =
    let open Lwt_syntax in
    let* context = Context_binary.add_tree context [] state in
    let* h = Context_binary.commit ~time:Time.Protocol.epoch context in
    let index = Context_binary.index context in
    let* context = Context_binary.checkout_exn index h in
    match Tree.kinded_key state with
    | Some k ->
        let index = Context_binary.index context in
        let* p = Context_binary.produce_tree_proof index k step in
        return (Some p)
    | None -> return None

  let kinded_hash_to_state_hash = function
    | `Value hash | `Node hash ->
        Protocol.Alpha_context.Sc_rollup.State_hash.context_hash_to_state_hash
          hash

  let proof_before proof = kinded_hash_to_state_hash proof.Context.Proof.before

  let proof_after proof = kinded_hash_to_state_hash proof.Context.Proof.after

  let proof_encoding =
    tc_merkle_proof_enc.V2.Tree2
    .tree_proof_encoding

  (* TODO: https://gitlab.com/tezos/tezos/-/issues/4386
     Extracted and adapted from {!Tezos_context_memory}. *)
  let make_empty_context ?(root = "/tmp") () =
    let open Lwt_syntax in
    let context_promise =
      let+ index = Tezos_context_memory.Context_binary.init root in
      Tezos_context_memory.Context_binary.empty index
    in
    match Lwt.state context_promise with
    | Lwt.Return result -> result
    | Lwt.Fail exn -> raise exn
    | Lwt.Sleep ->
        (* The in-memory context should never block *)
        assert false
end
