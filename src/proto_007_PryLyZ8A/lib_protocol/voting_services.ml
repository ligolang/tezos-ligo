(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

module S = struct
  let path = RPC_path.(open_root / "votes")

  let ballots =
    RPC_service.get_service
      ~description:"Sum of ballots casted so far during a voting period."
      ~query:RPC_query.empty
      ~output:Vote.ballots_encoding
      RPC_path.(path / "ballots")

  let ballot_list =
    RPC_service.get_service
      ~description:"Ballots casted so far during a voting period."
      ~query:RPC_query.empty
      ~output:
        Data_encoding.(
          list
            (obj2
               (req "voter" Contract.encoding)
               (req "ballot" Vote.ballot_encoding)))
      RPC_path.(path / "ballot_list")

  let current_period_kind =
    RPC_service.get_service
      ~description:"Current period kind."
      ~query:RPC_query.empty
      ~output:Voting_period.kind_encoding
      RPC_path.(path / "current_period_kind")

  let current_quorum =
    RPC_service.get_service
      ~description:"Current expected quorum."
      ~query:RPC_query.empty
      ~output:Data_encoding.int32
      RPC_path.(path / "current_quorum")

  let listings =
    RPC_service.get_service
      ~description:
        "List of bakers with their voting weight, in number of rolls."
      ~query:RPC_query.empty
      ~output:Vote.listings_encoding
      RPC_path.(path / "listings")

  let proposals =
    RPC_service.get_service
      ~description:"List of proposals with number of supporters."
      ~query:RPC_query.empty
      ~output:(Protocol_hash.Map.encoding Data_encoding.int32)
      RPC_path.(path / "proposals")

  let current_proposal =
    RPC_service.get_service
      ~description:"Current proposal under evaluation."
      ~query:RPC_query.empty
      ~output:(Data_encoding.option Protocol_hash.encoding)
      RPC_path.(path / "current_proposal")

  let total_voting_power =
    RPC_service.get_service
      ~description:
        "Total number of rolls for the delegates in the voting listings."
      ~query:RPC_query.empty
      ~output:Data_encoding.int32
      RPC_path.(path / "total_voting_power")
end

let register () =
  let open Services_registration in
  register0 S.ballots (fun ctxt () () -> Vote.get_ballots ctxt) ;
  register0 S.ballot_list (fun ctxt () () -> Vote.get_ballot_list ctxt >|= ok) ;
  register0 S.current_period_kind (fun ctxt () () ->
      Vote.get_current_period_kind ctxt) ;
  register0 S.current_quorum (fun ctxt () () -> Vote.get_current_quorum ctxt) ;
  register0 S.proposals (fun ctxt () () -> Vote.get_proposals ctxt) ;
  register0 S.listings (fun ctxt () () -> Vote.get_listings ctxt >|= ok) ;
  register0 S.current_proposal (fun ctxt () () ->
      (* this would be better implemented using get_option in get_current_proposal *)
      Vote.get_current_proposal ctxt
      >|= function
      | Ok p ->
          ok_some p
      | Error (Raw_context.Storage_error (Missing_key _) :: _) ->
          ok_none
      | Error _ as e ->
          e) ;
  register0 S.total_voting_power (fun ctxt () () ->
      Vote.get_total_voting_power_free ctxt)

let ballots ctxt block = RPC_context.make_call0 S.ballots ctxt block () ()

let ballot_list ctxt block =
  RPC_context.make_call0 S.ballot_list ctxt block () ()

let current_period_kind ctxt block =
  RPC_context.make_call0 S.current_period_kind ctxt block () ()

let current_quorum ctxt block =
  RPC_context.make_call0 S.current_quorum ctxt block () ()

let listings ctxt block = RPC_context.make_call0 S.listings ctxt block () ()

let proposals ctxt block = RPC_context.make_call0 S.proposals ctxt block () ()

let current_proposal ctxt block =
  RPC_context.make_call0 S.current_proposal ctxt block () ()

let total_voting_power ctxt block =
  RPC_context.make_call0 S.total_voting_power ctxt block () ()
