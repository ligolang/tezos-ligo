(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2022-2023 TriliTech <contact@trili.tech>                    *)
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

(** Helpers built upon the Sc_rollup_node and Sc_rollup_client *)

(*
  SC tests may contain arbitrary/generated bytes in external messages,
  and captured deposits/withdrawals contain byte sequences that change
  for both proofs and contract addresses.
 *)
let replace_variables string =
  string
  |> replace_string ~all:true (rex "0x01\\w{40}00") ~by:"[MICHELINE_KT1_BYTES]"
  |> replace_string ~all:true (rex "0x.*") ~by:"[SMART_ROLLUP_BYTES]"
  |> replace_string
       ~all:true
       (rex "hex\\:\\[\".*?\"\\]")
       ~by:"[SMART_ROLLUP_EXTERNAL_MESSAGES]"
  |> Tezos_regression.replace_variables

let hooks = Tezos_regression.hooks_custom ~replace_variables ()

let hex_encode (input : string) : string =
  match Hex.of_string input with `Hex s -> s

let load_kernel_file
    ?(base = "src/proto_alpha/lib_protocol/test/integration/wasm_kernel") name :
    string =
  let open Tezt.Base in
  let kernel_file = project_root // base // name in
  read_file kernel_file

(* [read_kernel filename] reads binary encoded WebAssembly module (e.g. `foo.wasm`)
   and returns a hex-encoded Wasm PVM boot sector, suitable for passing to
   [originate_sc_rollup].
*)
let read_kernel ?base name : string =
  hex_encode (load_kernel_file ?base (name ^ ".wasm"))

(* Testing the installation of a larger kernel, with e2e messages.

   When a kernel is too large to be originated directly, we can install
   it by using the 'reveal_installer' kernel. This leverages the reveal
   preimage+DAC mechanism to install the tx kernel.
*)
let prepare_installer_kernel ?runner
    ?(base_installee =
      "src/proto_alpha/lib_protocol/test/integration/wasm_kernel")
    ~preimages_dir installee =
  let open Tezt.Base in
  let open Lwt.Syntax in
  let installer = installee ^ "-installer.hex" in
  let output = Temp.file installer in
  let installee = (project_root // base_installee // installee) ^ ".wasm" in
  let process =
    Process.spawn
      ?runner
      ~name:installer
      (project_root // "smart-rollup-installer")
      [
        "get-reveal-installer";
        "--upgrade-to";
        installee;
        "--output";
        output;
        "--preimages-dir";
        preimages_dir;
      ]
  in
  let+ _ = Runnable.run @@ Runnable.{value = process; run = Process.check} in
  read_file output

let default_boot_sector_of ~kind =
  match kind with
  | "arith" -> ""
  | "wasm_2_0_0" -> Constant.wasm_echo_kernel_boot_sector
  | kind -> raise (Invalid_argument kind)

let make_parameter name = function
  | None -> []
  | Some value -> [([name], `Int value)]

let setup_l1 ?commitment_period ?challenge_window ?timeout protocol =
  let parameters =
    make_parameter "smart_rollup_commitment_period_in_blocks" commitment_period
    @ make_parameter "smart_rollup_challenge_window_in_blocks" challenge_window
    @ make_parameter "smart_rollup_timeout_period_in_blocks" timeout
    @ [(["smart_rollup_arith_pvm_enable"], `Bool true)]
  in
  let base = Either.right (protocol, None) in
  let* parameter_file = Protocol.write_parameter_file ~base parameters in
  let nodes_args =
    Node.[Synchronisation_threshold 0; History_mode Archive; No_bootstrap_peers]
  in
  Client.init_with_protocol ~parameter_file `Client ~protocol ~nodes_args ()

(** This helper injects an SC rollup origination via octez-client. Then it
    bakes to include the origination in a block. It returns the address of the
    originated rollup *)
let originate_sc_rollup ?hooks ?(burn_cap = Tez.(of_int 9999999))
    ?(src = Constant.bootstrap1.alias) ~kind ?(parameters_ty = "string")
    ?(boot_sector = default_boot_sector_of ~kind) client =
  let* sc_rollup =
    Client.Sc_rollup.(
      originate ?hooks ~burn_cap ~src ~kind ~parameters_ty ~boot_sector client)
  in
  let* () = Client.bake_for_and_wait client in
  return sc_rollup
