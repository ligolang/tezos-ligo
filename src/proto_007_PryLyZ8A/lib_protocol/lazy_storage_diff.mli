(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining 'a   *)
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

module KId : sig
  type t = E : ('id, _, _) Lazy_storage_kind.t * 'id -> t

  module Comparable : Compare.COMPARABLE with type t = t
end

type ('id, 'alloc) init = Existing | Copy of {src : 'id} | Alloc of 'alloc

type ('id, 'alloc, 'updates) diff =
  | Remove
  | Update of {init : ('id, 'alloc) init; updates : 'updates}

type diffs_item = private
  | E : ('i, 'a, 'u) Lazy_storage_kind.t * 'i * ('i, 'a, 'u) diff -> diffs_item

val make :
  ('i, 'a, 'u) Lazy_storage_kind.t -> 'i -> ('i, 'a, 'u) diff -> diffs_item

val make_remove : KId.t -> diffs_item

type diffs = diffs_item list

val encoding : diffs Data_encoding.t

(**
  The returned [Z.t] is the size added by the application of the diffs.
*)
val apply : Raw_context.t -> diffs -> (Raw_context.t * Z.t) tzresult Lwt.t

val fresh :
  ('id, _, _) Lazy_storage_kind.t ->
  temporary:bool ->
  Raw_context.t ->
  (Raw_context.t * 'id) tzresult Lwt.t

val init : Raw_context.t -> Raw_context.t tzresult Lwt.t

val cleanup_temporaries : Raw_context.t -> Raw_context.t Lwt.t
