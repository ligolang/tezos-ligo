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

(** Testing
    -------
    Component:    Protocol Library
    Invocation:   dune exec \
                  src/proto_alpha/lib_protocol/test/pbt/refutation_game_pbt.exe
    Subject:      SCORU refutation game
*)
open Protocol

open Game_repr

exception TickNotFound of Tick_repr.t

open Lib_test.Qcheck_helpers

(**
Helpers
*)
let option_get = function
  | Some a -> a
  | None -> raise (Invalid_argument "option is None")

module type TestPVM = sig
  include Sc_rollup_PVM_sem.S

  module Internal_for_tests : sig
    val initial_state : state

    val random_state : int -> state -> state
  end
end

(** this is avery simple PVM whose state is an integer and who can count up to a certin target.*)
module MakeCountingPVM (P : sig
  val target : int
end) : TestPVM with type state = int = struct
  type state = int

  let compress x = x

  module Internal_for_tests = struct
    let initial_state = 0

    let random_state _ _ = Random.bits ()
  end

  let equal_states = ( = )

  let pp ppf = Format.fprintf ppf "%d"

  let encoding = Data_encoding.int16

  let eval state = if state >= P.target then Some state else Some (state + 1)
end

let operation state number =
  Digest.bytes @@ Bytes.of_string @@ state ^ string_of_int number

(** this is a simple  "random PVM" its state is a pair (state, prog) whee state is a string and 
prog is a list of integers representing the a program. evaluation just consumes the head of program 
and modifies state by concatenating the head of the program to the existing state and hashing the result.
It is initiated with an initialprgram that creates the initial state. *)
module MakeRandomPVM (P : sig
  val initial_prog : int list
end) : TestPVM with type state = string * int list = struct
  type state = string * int list

  let compress x = x

  module Internal_for_tests = struct
    let initial_state = ("hello", P.initial_prog)

    let random_state length ((_, program) : state) =
      let remaining_program = TzList.drop_n length program in
      let (stop_state : state) =
        (operation "" (Random.bits ()), remaining_program)
      in
      stop_state
  end

  let equal_states = ( = )

  let pp ppf (st, li) =
    Format.fprintf ppf "%s@ %a" st (Format.pp_print_list Format.pp_print_int) li
  (*
     type history = {
       states :  state Tick_repr.Map.t;
       tick : Tick_repr.t;
     } *)

  let encoding =
    let open Data_encoding in
    conv
      (fun (value, list) -> (value, list))
      (fun (value, list) -> (value, list))
      (tup2 string (list int16))

  (* let remember history tick state =
     Tick_repr.Map.add tick state history *)

  let eval (hash, continuation) =
    match continuation with [] -> None | h :: tl -> Some (operation hash h, tl)
end

(* (** This is a mor ecomplicated PVM introducing a subset of 
Michelson instructions. the eval functions pretty much like the 
evaluation of a smart contract.*)
module MerkelizedMichelson = struct
  (**

     We assume the existence of some cryptographic hashing
     function. Notice that such function is relatively slow.
     Therefore, the interpreter should compute hashes only when
     strictly required.

   *)
  module Hash : sig
    type t

    (** This function will more likely be of type [Bytes.t -> t]. *)
    val hash : 'a -> t

    (** [combine hs] returns a hash for hash list [hs].  *)
    val combine : t list -> t

    (** The size in bytes of the serialization of an hash. *)
    val size : int

    val to_string : t -> string
  end = struct
    type t = Digest.t

    let hash x = Digest.bytes (Marshal.to_bytes x [])

    let to_string x = String.sub (Digest.to_hex x) 0 8

    let rec combine = function
      | [] -> assert false
      | [h] -> h
      | h :: hs -> hash (h, combine hs)

    let size = 16
  end

  (**

     We need a notion of [Taint] to mark specific parts of values to
     understand if they have been useful for a given execution step.

  *)
  module Taint : sig
    type t

    val transparent : t

    val of_tick : Tick_repr.t -> t

    val fresh : unit -> t

    val to_string : t -> string
  end = struct
    type t = int

    let transparent = -1

    let fresh =
      let r = ref (-1) in
      fun () ->
        decr r ;
        !r

    let of_tick = Tick_repr.to_int

    let to_string = string_of_int
  end

  (**

     The following type constructor is used at each level of the
     values manipulated by the merkelizing interpreter.

     Hopefully, the introduction of such a type constructor will be
     the major change in the existing Michelson interpreter.

     Indeed, to recover the standard Michelson interpreter, one can
     simply use the type constructor ['a id = 'a] instead of ['a
     merkelized].

  *)
  type 'a merkelized = {
    value : 'a option;  (** A merkelized value can be absent. *)
    repr : 'a repr;  (** A dynamic representation of ['a]'s type. *)
    mutable hash : Hash.t option;
        (** A value of type ['a merkelized] is actually "premerkelized"
          as the hashes are only computed on demand by a (recursive)
          modification of the [hash] field. *)
    mutable mark : Taint.t;
        (** A [mark] represents a taintstamp with respect to the
         execution witnessing that the value has been observed at some
         point of the execution.

         We must maintain the invariant that the mark of subvalues are
         older than [mark]. *)
    size : int;
        (**

          We need to maintain the size of merkelized values because we
          must be able to transmit them in a layer-1 operation (which
          has a limited size).

          What we call "size" in this context is not the size of the
          complete merkelized value but simply the size of the serialization
          of the toplevel structure of the merkelized value.

          Typically, for an inhabitant of an algebraic data type,
          this size is typically the size of the data constructor plus
          the size of the hashes of its components.

          In the real implementation, we will probably need to transmit
          serialized values instead of hashes for small values.

        *)
  }

  and 'a v = 'a merkelized

  and ('a, 's) cell = 'a v * 's v

  and ('s, 'f) cont =
    | KHalt : ('f, 'f) cont
    | KCons : ('s, 't) instr v * ('t, 'f) cont v -> ('s, 'f) cont

  (**

      A small subset of Michelson.

  *)
  and ('s, 'u) instr =
    | Halt : ('f, 'f) instr
    | Push : 'a v * (('a, 's) cell, 'f) instr v -> ('s, 'f) instr
    | Succ : ((int, 's) cell, 'u) instr v -> ((int, 's) cell, 'u) instr
    | Mul :
        ((int, 's) cell, 'f) instr v
        -> ((int, (int, 's) cell) cell, 'f) instr
    | Dec : ((int, 's) cell, 'f) instr v -> ((int, 's) cell, 'f) instr
    | CmpNZ : ((bool, 's) cell, 'f) instr v -> ((int, 's) cell, 'f) instr
    | Loop :
        ('s, (bool, 's) cell) instr v * ('s, 'f) instr v
        -> ((bool, 's) cell, 'f) instr
    | Dup : (('a, ('a, 's) cell) cell, 'f) instr v -> (('a, 's) cell, 'f) instr
    | Swap :
        (('b, ('a, 's) cell) cell, 'f) instr v
        -> (('a, ('b, 's) cell) cell, 'f) instr
    | Drop : ('s, 'f) instr v -> (('a, 's) cell, 'f) instr
    | Dip :
        ('s, 't) instr v * (('a, 't) cell, 'f) instr v
        -> (('a, 's) cell, 'f) instr

  and _ repr =
    | Int : int repr
    | Bool : bool repr
    | Unit : unit repr
    | Cell : 'a repr * 'b repr -> ('a, 'b) cell repr
    | Instr : 'i repr * 'o repr -> ('i, 'o) instr repr
    | Cont : 'a repr * 'b repr -> ('a, 'b) cont repr

  (** To simplify testing, we assume that a program has no argument
      and always produces an integer. *)
  type program = (unit, (int, unit) cell) instr v

  let hash_of v = Option.value ~default:(Hash.hash "Empty_hash") v.hash

  let rec pp_of_repr : type a. Format.formatter -> a repr -> unit =
   fun ppf repr ->
    match repr with
    | Cell (ity, oty) ->
        Format.fprintf ppf "(%a, %a)" pp_of_repr ity pp_of_repr oty
    | Cont (ity, oty) ->
        Format.fprintf ppf "(%a ~> %a)" pp_of_repr ity pp_of_repr oty
    | Instr _ -> Format.pp_print_string ppf "instr"
    | Int -> Format.pp_print_string ppf "int"
    | Bool -> Format.pp_print_string ppf "bool"
    | Unit -> Format.pp_print_string ppf "unit"

  let rec pp_of_value : type a. Format.formatter -> a repr -> a -> unit =
   fun ppf repr x ->
    match repr with
    | Cell (_ity, _oty) ->
        Format.fprintf ppf "(%a, %a)" show (fst x) show (snd x)
    | Cont _ -> pp_of_cont ppf x
    | Instr _ -> pp_of_instr ppf x
    | Int -> Format.pp_print_int ppf x
    | Bool -> Format.pp_print_bool ppf x
    | Unit -> Format.pp_print_string ppf "()"

  and pp_of_instr : type a s. Format.formatter -> (a, s) instr -> unit =
   fun ppf instr ->
    match instr with
    | Halt -> Format.pp_print_string ppf "halt"
    | Push (x, i) -> Format.fprintf ppf "push %a ; %a" show x show i
    | Succ i -> Format.fprintf ppf "succ ; %a" show i
    | Mul i -> Format.fprintf ppf "mul ; %a" show i
    | Dec i -> Format.fprintf ppf "dec ; %a" show i
    | CmpNZ i -> Format.fprintf ppf "cmpnz ; %a" show i
    | Loop (body, the_exit) ->
        Format.fprintf ppf "loop { %a } ; %a" show body show the_exit
    | Dup i -> Format.fprintf ppf "dup ; %a" show i
    | Swap i -> Format.fprintf ppf "swap ; %a" show i
    | Drop i -> Format.fprintf ppf "drop ; %a" show i
    | Dip (body, and_then) ->
        Format.fprintf ppf "dip { %a } ; %a" show body show and_then

  and pp_of_cont : type s f. Format.formatter -> (s, f) cont -> unit =
   fun ppf s ->
    match s with
    | KHalt -> Format.pp_print_string ppf "khalt"
    | KCons (i, k) -> Format.fprintf ppf "%a : %a" show i show k

  and verbose = false

  and show : type a. Format.formatter -> a v -> unit =
   fun ppf v ->
    if verbose then
      Format.fprintf
        ppf
        "([%s | %s ]%a : %a)"
        (Taint.to_string v.mark)
        (Option.fold ~none:"?" ~some:Hash.to_string v.hash)
        (Format.pp_print_option
           ~none:(fun ppf _ -> Format.pp_print_string ppf "")
           (fun ppf x -> pp_of_value ppf v.repr x))
        v.value
        pp_of_repr
        v.repr
    else
      Format.fprintf
        ppf
        "([%a]%a)"
        (Format.pp_print_option
           ~none:(fun ppf _ -> Format.pp_print_string ppf "?")
           (fun ppf x -> Format.pp_print_string ppf (Hash.to_string x)))
        v.hash
        (Format.pp_print_option
           ~none:(fun ppf _ -> Format.pp_print_string ppf "")
           (fun ppf x -> pp_of_value ppf v.repr x))
        v.value

  let get ~taint left_space v =
    if taint <> Taint.transparent then v.mark <- taint ;
    left_space := !left_space - v.size ;
    if !left_space < 0 then
      raise (Invalid_argument "This operation consumes too much space") ;
    option_get v.value

  let merke ~taint repr value size =
    {hash = None; value = Some value; repr; size; mark = taint}

  let push ~taint x i =
    match i.repr with
    | Instr (Cell (_, s), f) ->
        merke ~taint (Instr (s, f)) (Push (x, i)) (24 + (2 * Hash.size))

  let halt ~taint f = merke ~taint (Instr (f, f)) Halt (8 + Hash.size)

  let succ ~taint i = merke ~taint i.repr (Succ i) (24 + Hash.size)

  let mul ~taint i =
    match i.repr with
    | Instr (s, f) ->
        merke ~taint (Instr (Cell (Int, s), f)) (Mul i) (24 + Hash.size)

  let dec ~taint i = merke ~taint i.repr (Dec i) (24 + i.size)

  let cmpnz ~taint i =
    match i.repr with
    | Instr (Cell (_, s), f) ->
        merke ~taint (Instr (Cell (Int, s), f)) (CmpNZ i) (24 + Hash.size)

  let dup ~taint i =
    match i.repr with
    | Instr (Cell (_, Cell (a, s)), f) ->
        merke ~taint (Instr (Cell (a, s), f)) (Dup i) (24 + Hash.size)

  let swap ~taint i =
    match i.repr with
    | Instr (Cell (b, Cell (a, s)), f) ->
        merke ~taint (Instr (Cell (a, Cell (b, s)), f)) (Swap i) (24 + Hash.size)

  let drop ~taint ty i =
    match i.repr with
    | Instr (s, f) ->
        merke ~taint (Instr (Cell (ty, s), f)) (Drop i) (24 + Hash.size)

  let loop ~taint body the_exit =
    match (body.repr, the_exit.repr) with
    | (Instr (_, i), Instr (_, f)) ->
        merke
          ~taint
          (Instr (i, f))
          (Loop (body, the_exit))
          (24 + (2 * Hash.size))

  let dip ~taint body and_then =
    match (and_then.repr, body.repr) with
    | (Instr (Cell (a, _), f), Instr (s', _)) ->
        merke
          ~taint
          (Instr (Cell (a, s'), f))
          (Dip (body, and_then))
          (24 + (2 * Hash.size))

  let lint ~taint x = merke ~taint Int x 8

  let lbool ~taint x = merke ~taint Bool x 8

  let khalt ~taint f = merke ~taint (Cont (f, f)) KHalt 8

  let kcons ~taint (type s t f) (i : (s, t) instr v) (cont : (t, f) cont v) :
      (s, f) cont v =
    match i.repr with
    | Instr (ity, _) -> (
        match cont.repr with
        | Cont (_, oty) ->
            merke
              ~taint
              (Cont (ity, oty))
              (KCons (i, cont))
              (i.size + cont.size + 24))

  let cell ~taint x v =
    merke ~taint (Cell (x.repr, v.repr)) (x, v) (x.size + v.size + 24)

  let empty_stack ~taint = merke ~taint Unit () 8

  (** [merkelize v] computes the hashes in [v]. *)
  let rec merkelize : type a. a v -> unit =
    let open Hash in
    fun v ->
      match v.hash with
      | Some _ -> ()
      | None ->
          let hash =
            match (v.repr, v.value) with
            | (Cell _, Some x) ->
                let (a, b) = x in
                merkelize a ;
                merkelize b ;
                assert (v.hash = None) ;
                (* No recursive values allowed. *)
                combine [hash_of a; hash_of b]
            | (Instr _, Some i) -> hash_instr i
            | (Cont _, Some k) -> hash_cont k
            | (Int, Some i) -> hash i
            | (Bool, Some i) -> hash i
            | (Unit, Some ()) -> hash ()
            | (_, None) -> assert false
          in
          v.hash <- Some hash

  and hash_cont : type s f. (s, f) cont -> Hash.t = function
    | KHalt -> Hash.hash "KHalt"
    | KCons (i, cont) ->
        merkelize i ;
        merkelize cont ;
        Hash.(combine [hash "KCons"; hash_of i; hash_of cont])

  and hash_instr : type s f. (s, f) instr -> Hash.t = function
    | Halt -> Hash.hash ["Halt"]
    | Push (x, i) ->
        merkelize x ;
        merkelize i ;
        Hash.(combine [hash "Push"; hash_of x; hash_of i])
    | Succ i ->
        merkelize i ;
        Hash.(combine [hash "Succ"; hash_of i])
    | Mul i ->
        merkelize i ;
        Hash.(combine [hash "Mul"; hash_of i])
    | Dec i ->
        merkelize i ;
        Hash.(combine [hash "Dec"; hash_of i])
    | CmpNZ i ->
        merkelize i ;
        Hash.(combine [hash "CmpNZ"; hash_of i])
    | Loop (body, the_exit) ->
        merkelize body ;
        merkelize the_exit ;
        Hash.(combine [hash "Loop"; hash_of body; hash_of the_exit])
    | Dup i ->
        merkelize i ;
        Hash.(combine [hash "Dup"; hash_of i])
    | Swap i ->
        merkelize i ;
        Hash.(combine [hash "Swap"; hash_of i])
    | Drop i ->
        merkelize i ;
        Hash.(combine [hash "Drop"; hash_of i])
    | Dip (body, and_then) ->
        merkelize body ;
        merkelize and_then ;
        Hash.(combine [hash "Dip"; hash_of body; hash_of and_then])

  (** [useful_part ~taint v] returns the (toplevel) parts of [v]
      that have been marked with [taint].

      We assume that the root of [v] has been marked with [taint].
      Otherwise, the result is undefined.
   *)
  let useful_part ~taint v =
    let rec aux : type a. a v -> a v =
     fun v ->
      if v.mark <> taint then {v with value = None}
      else
        match (v.repr, v.value) with
        | (Cell _, Some x) -> {v with value = Some (aux (fst x), aux (snd x))}
        | (Cont _, Some (KCons (i, k))) ->
            {v with value = Some (KCons (aux i, aux k))}
        | (Cont _, Some KHalt) -> v
        | (Instr _, Some i) ->
            let value =
              match i with
              | Push (x, i) -> Push (aux x, aux i)
              | Halt -> Halt
              | Succ i -> Succ (aux i)
              | Mul i -> Mul (aux i)
              | Dec i -> Dec (aux i)
              | CmpNZ i -> CmpNZ (aux i)
              | Loop (body, the_exit) -> Loop (aux body, aux the_exit)
              | Dup i -> Dup (aux i)
              | Swap i -> Swap (aux i)
              | Drop i -> Drop (aux i)
              | Dip (body, and_then) -> Dip (aux body, aux and_then)
            in
            {v with value = Some value}
        | (Int, _) -> v
        | (Bool, _) -> v
        | (Unit, _) -> v
        | (_, None) -> v
    in
    aux v
end

module MakeMPVM (Code : sig
  val program : MerkelizedMichelson.program
end):TestPVM =
struct
  open MerkelizedMichelson

  (**

      The state of the Merkelized interpreter for Michelson is
      made of merkelized pair of a stack of type ['s] and a
      continuation expecting a stack of this type.

      ['f] represents the type of the final stack.

      Both ['s] and ['f] are existentially quantified but can
      be recovered thanks to their dynamic representation held
      by the [repr] field of the merkelized value.

  *)
  type state = State : ('s, ('s, 'f) cont) cell v -> state

  let pp ppf (State cell) = show ppf cell

  let merkelize_state (State s) =
    merkelize s ;
    State s

  (** This function "compresses" the state representation by dropping the
      value. This should reduce the size of the serialization. However, if
      the value is shorter than the hash, we should probably keep the value
      and recompute the hash on the other side of the pipe. *)
  let compress (State s) = State {s with value = None}

  module Internal_for_tests = struct
    let initial_state =
      let taint = Taint.transparent in
      let stack = empty_stack ~taint in
      let cont = kcons ~taint Code.program (khalt ~taint (Cell (Int, Unit))) in
      merkelize_state (State (cell ~taint stack cont))

 

    let random_state _ _ =
      let taint = Taint.transparent in
      let s = cell ~taint (empty_stack ~taint) (khalt ~taint Unit) in
      compress (merkelize_state (State s))
  end
  let equal_states : state ->  state -> bool =
  fun (State s1) (State s2) ->
   match (s1.hash, s2.hash) with
   | (Some h1, Some h2) -> h1 = h2
   | (_, _) -> assert false

  (** The encoding is not really the main point here, I made arathe silly one (that only produces the initial state) 
    to move forward. *)
  let encoding :  state Data_encoding.t =
    Data_encoding.conv
      (fun x -> match x with State _ -> 3)
      (fun _ -> compress Internal_for_tests.initial_state)
      Data_encoding.int16

  let random_state _ _ =
    let taint = Taint.transparent in
    let s = cell ~taint (empty_stack ~taint) (khalt ~taint Unit) in
    compress (merkelize_state (State s))

  (**

     [step_instr ~taint i k stack] implements a single execution step.

     This interpreter is close the current Michelson interpreter
     except on the following points:

     - There is no recursive call to immediately evaluate the next
       instruction.

     - Values are deconstructed through [get] which taints them to
       determine their useful parts. As said earlier, replacing
       [get] with the identity should recover the current Michelson
       interpreter.

     - This interpreter checks that the useful part of the state
       remains compatible with the size limit of its serialization.

  *)
  let step_instr :
      type s t f.
      taint:Taint.t ->
      int ref ->
      (s, t) instr v ->
      (t, f) cont v ->
      s v ->
       state =
   fun ~taint left_space i cont s ->
    let return s = State s in
    match get ~taint left_space i with
    | Halt -> return (cell ~taint s cont)
    | Push (x, i) ->
        return (cell ~taint (cell ~taint x s) (kcons ~taint i cont))
    | Succ i -> (
        match get ~taint left_space s with
        | (x, s) ->
            let x = get ~taint left_space x in
            return
              (cell
                 ~taint
                 (cell ~taint (lint ~taint (x + 1)) s)
                 (kcons ~taint i cont)))
    | Mul i -> (
        match get ~taint left_space s with
        | (x, s) -> (
            match get ~taint left_space s with
            | (y, s) ->
                let x = get ~taint left_space x in
                let y = get ~taint left_space y in
                return
                  (cell
                     ~taint
                     (cell ~taint (lint ~taint (x * y)) s)
                     (kcons ~taint i cont))))
    | Dec i -> (
        match get ~taint left_space s with
        | (x, s) ->
            let x = get ~taint left_space x in
            return
              (cell
                 ~taint
                 (cell ~taint (lint ~taint (x - 1)) s)
                 (kcons ~taint i cont)))
    | CmpNZ i -> (
        match get ~taint left_space s with
        | (x, s) ->
            let x = get ~taint left_space x in
            return
              (cell
                 ~taint
                 (cell ~taint (lbool ~taint (x <> 0)) s)
                 (kcons ~taint i cont)))
    | Loop (body, the_exit) -> (
        match get ~taint left_space s with
        | (b, s) ->
            if get ~taint left_space b then
              return (cell ~taint s (kcons ~taint body (kcons ~taint i cont)))
            else return (cell ~taint s (kcons ~taint the_exit cont)))
    | Dup i -> (
        match get ~taint left_space s with
        | (x, _) -> return (cell ~taint (cell ~taint x s) (kcons ~taint i cont))
        )
    | Swap i -> (
        match get ~taint left_space s with
        | (x, s) -> (
            match get ~taint left_space s with
            | (y, s) ->
                return
                  (cell
                     ~taint
                     (cell ~taint y (cell ~taint x s))
                     (kcons ~taint i cont))))
    | Drop i -> (
        match get ~taint left_space s with
        | (_, s) -> return (cell ~taint s (kcons ~taint i cont)))
    | Dip (body, and_then) -> (
        match get ~taint left_space s with
        | (x, s) ->
            let cont =
              kcons ~taint body (kcons ~taint (push ~taint x and_then) cont)
            in
            return (cell ~taint s cont))

  let step_cont :
      type s f.
      taint:Taint.t ->
      int ref ->
      (s, f) cont v ->
      s v ->
       state =
   fun ~taint left_space cont s ->
    match get ~taint left_space cont with
    | KHalt -> State (cell ~taint s cont)
    | KCons (i, cont) -> step_instr ~taint left_space i cont s

  (**

     The history contains at most K snapshots of the state
     where K is the number of section in the previous dissection.

     Hence, if the initial section of the game has N ticks, at
     the step I, we have (N / K^I) execution steps to replay.
     This looks reasonable.

  *)

  type history =  state Tick_repr.Map.t

  let empty_history : history = Tick_repr.Map.empty

  let remember history (tick : Tick_repr.t) state =
    Tick_repr.Map.add tick state history

  type tick = Tick_repr.t

  let forward_eval history tick =
    match Tick_repr.Map.split tick history with
    | (lower, None, _) -> Tick_repr.Map.max_binding lower
    | (_, Some state, _) -> Some (tick, state)

  let eval_to :
      taint:Taint.t ->
      history ->
      tick ->
       state =
   fun ~taint history target_tick ->
    let (tick0, state0) =
      Option.value ~default:(Tick_repr.initial, Internal_for_tests.initial_state)
      @@ forward_eval history target_tick
    in
    let rec go tick state =
      if tick = target_tick then state
      else
        let (State s) = state in
        let left_space = ref (16 * 1024) in
        let (v, cont) = get ~taint left_space s in
        let state' = step_cont ~taint left_space cont v in
        go (Tick_repr.next tick) state'
    in
    go tick0 state0

  let state_at : history -> tick ->  state =
   fun history tick ->
    let taint = Taint.of_tick tick in
    merkelize_state @@ eval_to ~taint history tick

  let verifiable_state_at :
      history -> tick ->  state =
   fun history tick ->
    let (State s0) = state_at history tick in
    let taint = Taint.of_tick tick in
    let left_space = ref (16 * 1024) in
    let (v, cont) = get ~taint left_space s0 in
    let _ = step_cont ~taint left_space cont v in
    State (useful_part ~taint s0)

  let eval : state -> state option =
   fun (State s) ->
      let taint = Taint.of_tick tick in
      let left_space = ref (16 * 1024) in
      let (v, cont) = get ~taint left_space s in
      Some (merkelize_state (step_cont ~taint left_space cont v))

  let rec execute_until :
      failures:tick list ->
      tick ->
       state ->
      (tick -> state -> bool) ->
      tick * state =
   fun ~failures tick state pred ->
    if pred tick state then (tick, merkelize_state state)
    else
      let state =  Option.value ~default:(assert false) (eval state) in
      execute_until ~failures (Tick_repr.next tick) state pred
end

module Push = struct
  open MerkelizedMichelson

  let program =
    let taint = Taint.transparent in
    push ~taint (lint ~taint 1) (halt ~taint (Cell (Int, Unit)))
end

module Fact20 = struct
  open MerkelizedMichelson

  let program : program =
    let taint = Taint.transparent in

    push ~taint (lint ~taint 20)
    @@ push ~taint (lint ~taint 1)
    @@ dup ~taint @@ cmpnz ~taint
    @@ dip ~taint (swap ~taint (halt ~taint (Cell (Int, Cell (Int, Unit)))))
    @@ loop
         ~taint
         (dup ~taint
         @@ dip
              ~taint
              (swap ~taint (halt ~taint (Cell (Int, Cell (Int, Unit)))))
         @@ mul ~taint @@ swap ~taint @@ dec ~taint @@ dup ~taint
         @@ cmpnz
              ~taint
              (halt ~taint (Cell (Bool, Cell (Int, Cell (Int, Unit))))))
    @@ drop ~taint Int (halt ~taint (Cell (Int, Unit)))
end *)

(** This module introduces some testing strategies for a game created from a PVM
*)
module Strategies (P : TestPVM) = struct
  module Game = Game_repr.Make (P)
  open Game
  open PVM

  (** this eception is needed for a small that alows a "fold-with break"
*)
  exception Section of Game.Section_repr.section

  let random_tick ?(from = 0) () =
    Option.value
      ~default:Tick_repr.initial
      (Tick_repr.of_int (from + Random.int 31))

  (** this picks a random section between start_at and stop_at. The states 
  are determined by the random_state function.*)
  let random_section (start_at : Tick_repr.t) start_state
      (stop_at : Tick_repr.t) =
    let x = min 10000 @@ Z.to_int (Tick_repr.distance start_at stop_at) in
    let length = 1 + try Random.int x with _ -> 0 in
    let stop_at = Tick_repr.(of_int (to_int start_at + length)) in

    ({
       section_start_at = start_at;
       section_start_state = start_state;
       section_stop_at = Option.value ~default:start_at stop_at;
       section_stop_state = P.Internal_for_tests.random_state length start_state;
     }
      : Section_repr.section)

  (** this picks a random dissection of a given section. 
  The sections involved are random and their states have no connection with the initial section.*)
  let random_dissection (gsection : Section_repr.section) =
    let open Tick_repr in
    let rec aux dissection start_at start_state =
      if start_at = gsection.section_stop_at then dissection
      else
        let section =
          random_section start_at start_state gsection.section_stop_at
        in
        if
          section.section_start_at = gsection.section_start_at
          && section.section_stop_at = gsection.section_stop_at
        then aux dissection start_at start_state
        else
          aux
            (Map.add section.section_start_at section dissection)
            section.section_stop_at
            section.section_stop_state
    in
    if
      Compare.Int.(
        Z.to_int (distance gsection.section_stop_at gsection.section_start_at)
        > 1)
    then
      Some
        (aux Map.empty gsection.section_start_at gsection.section_start_state)
    else None

  (** this function assmbles a random decision from a given dissection.
    It first picks a random section from the dissection and modifies randomly its states.
    If the length of this section is one tick the returns a conclusion with the given modified states.
    If the length is longer it creates a random decision and outputs a Refine decisoon with this dissection.*)
  let random_decision d =
    let open Section_repr in
    let open Tick_repr.Map in
    let cardinal = cardinal d in
    let x = Random.int cardinal in
    (* Section_repr.pp_of_dissection Format.std_formatter d; *)
    let (_, section) =
      try
        fold
          (fun _ s (n, _) -> if n = x then raise (Section s) else (n + 1, None))
          d
          (0, None)
      with Section sec -> (0, Some sec)
    in
    let section =
      match section with None -> raise Not_found | Some section -> section
    in
    let section_start_at = section.section_start_at in
    let section_stop_at = section.section_stop_at in
    let section_start_state =
      P.Internal_for_tests.random_state 0 section.section_start_state
    in
    let section_stop_state =
      P.Internal_for_tests.random_state
        Tick_repr.(to_int section_stop_at - to_int section_start_at)
        section.section_start_state
    in

    let next_dissection = random_dissection section in
    let section =
      {
        section_start_state;
        section_start_at;
        section_stop_state;
        section_stop_at;
      }
    in
    let conflict_search_step =
      match next_dissection with
      | None ->
          Conclude
            {
              start_state = section.section_start_state;
              stop_state = section.section_stop_state;
            }
      | Some next_dissection ->
          Refine {stop_state = section.section_stop_state; next_dissection}
    in
    ConflictInside {choice = section; conflict_search_step}

  (** technical params for machine directed strategies, branching is the number of pieces for a dissection
failing level*)
  type parameters = {
    branching : int;
    failing_level : int;
    max_failure : int option;
  }

  type checkpoint = Tick_repr.t -> bool

  (** there are two kinds of strategies, random and machine dirrected by a params and a checkpoint*)
  type strategy = Random | MachineDirected of parameters * checkpoint

  (**checks that the stop state of a section conflicts with the one in the history.*)
  let conflicting_section (history : history) (section : Section_repr.section) =
    not
      (equal_states
         section.section_stop_state
         (state_at history section.section_stop_at section.section_start_state))

  (** updates the history*)
  let remember_section history (section : Section_repr.section) =
    let history =
      remember history section.section_start_at section.section_start_state
    in
    remember history section.section_stop_at section.section_stop_state

  (** Finds the section (if it exists) is a dissection that conflicts with the history. 
    This is where the trick with the exception appears*)
  let find_conflict history dissection =
    try
      Tick_repr.Map.fold
        (fun _ v _ ->
          if conflicting_section history v then raise (Section v) else None)
        dissection
        None
    with Section section -> Some section

  (** [next_move history branching dissection] 
  If finds the next move based on a dissection and history.
  It finds the first section of dissection that conflicts with the history. 
  If the section has length one tick it returns a move with a Conclude conflict_search_step.
  If the section is longer it creates a new dissection with branching many pieces, updates the history based on 
  this dissection and returns a move with a Refine type conflict_search_step.
   *)
  let next_move history branching dissection =
    let section =
      find_conflict history dissection |> function
      | None -> raise (TickNotFound Tick_repr.initial)
      | Some s -> s
    in
    let next_dissection =
      Section_repr.dissection_of_section history branching section
    in
    let (empty_history : history) = Tick_repr.Map.empty in
    let (conflict_search_step, history) =
      match next_dissection with
      | None ->
          let stop_state =
            state_at
              history
              (Tick_repr.next section.section_start_at)
              P.Internal_for_tests.initial_state
          in
          ( Conclude
              {
                start_state =
                  Game.(
                    state_at
                      history
                      section.section_start_at
                      P.Internal_for_tests.initial_state);
                stop_state;
              },
            empty_history )
      | Some next_dissection ->
          let stop_state =
            state_at
              history
              section.section_stop_at
              P.Internal_for_tests.initial_state
          in
          let history =
            Tick_repr.Map.fold
              (fun _ v acc -> remember_section acc v)
              next_dissection
              empty_history
          in
          (Refine {stop_state; next_dissection}, history)
    in
    (ConflictInside {choice = section; conflict_search_step}, history)

  (** helper function that generates an array of failing_level many ticks between start and stop*)
  let generate_failures failing_level (section_start_at : Tick_repr.t)
      (section_stop_at : Tick_repr.t) max_failure =
    let d = Z.to_int (Tick_repr.distance section_stop_at section_stop_at) in
    let d = match max_failure with None -> d | Some x -> x in
    if failing_level > 0 then
      let s =
        repeat failing_level (fun _ ->
            let s = Tick_repr.to_int section_start_at + Random.int (max d 1) in
            Option.value ~default:(assert false) (Tick_repr.of_int s))
      in
      Result.value ~default:[] s
    else []

  (** this is an outomatic commuter client. It generates a "perfect" client for the commuter unless 
given some positive failing level when it "forgets" to evaluate the ticks on the autmatically generated failure list.*)
  let machine_directed_committer {branching; _} pred =
    let (history : history ref) = ref Tick_repr.Map.empty in
    let initial ((section_start_at : Tick_repr.t), section_start_state) : commit
        =
      (* let section_stop_at =
           Option.value ~default:(assert false) (Tick_repr.of_int ((Tick_repr.to_int section_start_at) + Random.int 2))
         in *)
      (* let failures =
           generate_failures
             failing_level
             section_start_at
             section_stop_at
             max_failure
         in *)
      let (section_stop_at, section_stop_state) =
        Game.execute_until section_start_at section_start_state @@ fun tick _ ->
        pred tick
      in
      history := Game.remember !history section_start_at section_start_state ;
      history := Game.remember !history section_stop_at section_stop_state ;
      Commit
        {
          section_start_state;
          section_start_at;
          section_stop_state;
          section_stop_at;
        }
    in
    let next_move dissection =
      let (move, history') = next_move !history branching dissection in
      history := history' ;
      move
    in

    ({initial; next_move} : _ client)

  (** this is an outomatic refuter client. It generates a "perfect" client for the commuter unless 
given some positive failing level when it "forgets" to evaluate the ticks on the autmatically generated failure list.*)
  let machine_directed_refuter {branching; _} =
    let (history : history ref) = ref Tick_repr.Map.empty in
    let initial (section_start_state, Commit section) : refutation =
      let ({section_start_at; section_stop_at; _} : Section_repr.section) =
        section
      in
      (* let failures =
           generate_failures
             failing_level
             section_start_at
             section_stop_at
             max_failure
         in *)
      let (_stop_at, section_stop_state) =
        Game.execute_until section_start_at section_start_state @@ fun tick _ ->
        tick >= section_stop_at
      in
      history := Game.remember !history section_start_at section_start_state ;
      history := Game.remember !history section_stop_at section_stop_state ;
      let next_dissection =
        Section_repr.dissection_of_section
          !history
          branching
          {section with section_stop_state}
      in
      let conflict_search_step =
        match next_dissection with
        | None ->
            Conclude
              {
                start_state =
                  Game.state_at
                    !history
                    section_start_at
                    P.Internal_for_tests.initial_state;
                stop_state = section_stop_state;
              }
        | Some next_dissection ->
            Refine {stop_state = section_stop_state; next_dissection}
      in
      RefuteByConflict conflict_search_step
    in
    let next_move dissection =
      let (move, history') = next_move !history branching dissection in
      history := history' ;
      move
    in
    ({initial; next_move} : _ client)

  (** This builds a commiter client from a strategy. 
    If the strategy is MachineDirected it uses the above constructions. 
    if the strategy is random then it usesa random section for the initial commitments 
     and  the random decision for the next move.*)
  let committer_from_strategy : strategy -> _ client = function
    | Random ->
        {
          initial =
            (fun ((section_start_at : Tick_repr.t), start_state) ->
              let section_stop_at =
                random_tick ~from:(Tick_repr.to_int section_start_at) ()
              in
              let section =
                random_section section_start_at start_state section_stop_at
              in
              Commit section);
          next_move = random_decision;
        }
    | MachineDirected (parameters, checkpoint) ->
        machine_directed_committer parameters checkpoint

  (** This builds a refuter client from a strategy. 
    If the strategy is MachineDirected it uses the above constructions. 
    If the strategy is random then it uses a randomdissection 
    of the commited section for the initial refutation 
     and  the random decision for the next move.*)
  let refuter_from_strategy : strategy -> _ client = function
    | Random ->
        {
          initial =
            (fun ((start_state : state), Commit section) ->
              let conflict_search_step =
                let next_dissection = random_dissection section in
                match next_dissection with
                | None ->
                    Conclude
                      {
                        start_state;
                        stop_state =
                          P.Internal_for_tests.random_state 1 start_state;
                      }
                | Some next_dissection ->
                    let (_, section) =
                      Option.value
                        ~default:(Tick_repr.initial, section)
                        (Tick_repr.Map.max_binding next_dissection)
                    in
                    Refine
                      {stop_state = section.section_stop_state; next_dissection}
              in
              RefuteByConflict conflict_search_step);
          next_move = random_decision;
        }
    | MachineDirected (parameters, _) -> machine_directed_refuter parameters

  (** [test_strategies committer_strategy refuter_strategy expectation] 
    runs a game based oin the two given strategies and checks that the resulting 
    outcome fits the expectations. *)
  let test_strategies committer_strategy refuter_strategy expectation =
    let start_state = P.Internal_for_tests.initial_state in
    let committer = committer_from_strategy committer_strategy in
    let refuter = refuter_from_strategy refuter_strategy in
    let outcome =
      run ~start_at:Tick_repr.initial ~start_state ~committer ~refuter
    in
    expectation outcome

  (** This is a commuter client having a perfect strategy*)
  let perfect_committer =
    MachineDirected
      ( {failing_level = 0; branching = 2; max_failure = None},
        fun tick -> Tick_repr.to_int tick >= 20 + Random.int 100 )
  (** This is a refuter client having a perfect strategy*)

  let perfect_refuter =
    MachineDirected
      ( {failing_level = 0; branching = 2; max_failure = None},
        fun _ -> assert false )

  (** This is a commuter client having a strategy that forgets a tick*)
  let failing_committer max_failure =
    MachineDirected
      ( {failing_level = 1; branching = 2; max_failure},
        fun tick ->
          let s = match max_failure with None -> 20 | Some x -> x in
          Tick_repr.to_int tick >= s )

  (** This is a commuter client having a strategy that forgets a tick*)
  let failing_refuter max_failure =
    MachineDirected
      ({failing_level = 1; branching = 2; max_failure}, fun _ -> assert false)

  (** the possible expectation functions *)
  let commiter_wins = function
    | {winner = Some Committer; _} -> true
    | _ -> false

  let refuter_wins = function {winner = Some Refuter; _} -> true | _ -> false

  let all_win (_ : outcome) = true
end

(** the following are the possible combinations of strategies*)
let perfect_perfect (module P : TestPVM) _max_failure =
  let module R = Strategies (P) in
  R.test_strategies R.perfect_committer R.perfect_refuter R.commiter_wins

let random_random (module P : TestPVM) _max_failure =
  let module S = Strategies (P) in
  S.test_strategies Random Random S.all_win

let random_perfect (module P : TestPVM) _max_failure =
  let module S = Strategies (P) in
  S.test_strategies Random S.perfect_refuter S.refuter_wins

let perfect_random (module P : TestPVM) _max_failure =
  let module S = Strategies (P) in
  S.test_strategies S.perfect_committer Random S.commiter_wins

let failing_perfect (module P : TestPVM) max_failure =
  let module S = Strategies (P) in
  S.test_strategies
    (S.failing_committer max_failure)
    S.perfect_refuter
    S.refuter_wins

let perfect_failing (module P : TestPVM) max_failure =
  let module S = Strategies (P) in
  S.test_strategies
    S.perfect_committer
    (S.failing_refuter max_failure)
    S.commiter_wins

(** this assembles a test from a RandomPVM and a function that choses the type of strategies *)
let testing_randomPVM (f : (module TestPVM) -> int option -> bool) name =
  QCheck.Test.make
    ~name
    (QCheck.list_of_size QCheck.Gen.small_int (QCheck.int_range 0 100))
    (fun initial_prog ->
      QCheck.assume (initial_prog <> []) ;
      f
        (module MakeRandomPVM (struct
          let initial_prog = initial_prog
        end))
        (Some (List.length initial_prog)))

(** this assembles a test from a CountingPVM and a function that choses the type of strategies *)
let testing_countPVM (f : (module TestPVM) -> int option -> bool) name =
  QCheck.Test.make ~name QCheck.small_int (fun target ->
      QCheck.assume (target > 0) ;
      f
        (module MakeCountingPVM (struct
          let target = target
        end))
        (Some target))

(** this assembles a test from a MichelsonPVM and a function that choses the type of strategies *)

(* let testing_mich (f : (module TestPVM) -> int option -> bool) name =
  QCheck.Test.make ~name QCheck.small_int (fun _ ->
      f (module MakeMPVM (Fact20)) (Some 20)) *)

let test_random_dissection (module P : TestPVM) start_at length branching =
  let open P in
  let module S = Strategies (P) in
  let section_start_state = Internal_for_tests.initial_state in
  let section_stop_at =
    match Tick_repr.of_int (start_at + length) with
    | None -> assert false
    | Some x -> x
  in
  let section_start_at =
    match Tick_repr.of_int start_at with None -> assert false | Some x -> x
  in

  let section =
    S.Game.Section_repr.
      {
        section_start_at;
        section_start_state;
        section_stop_at;
        section_stop_state =
          Internal_for_tests.random_state length section_start_state;
      }
  in
  let option_dissection =
    let empty_history = Tick_repr.Map.empty in
    S.Game.Section_repr.dissection_of_section empty_history branching section
  in
  let dissection =
    match option_dissection with
    | None -> raise (Invalid_argument "no dissection")
    | Some x -> x
  in
  S.Game.Section_repr.valid_dissection section dissection

let testDissection =
  [
    QCheck.Test.make
      ~name:"randomVPN"
      (QCheck.quad
         (QCheck.list_of_size QCheck.Gen.small_int (QCheck.int_range 0 100))
         QCheck.small_int
         QCheck.small_int
         QCheck.small_int)
      (fun (initial_prog, start_at, length, branching) ->
        QCheck.assume
          (start_at >= 0 && length > 1
          && List.length initial_prog > start_at + length
          && 1 < branching) ;
        let module P = MakeRandomPVM (struct
          let initial_prog = initial_prog
        end) in
        test_random_dissection (module P) start_at length branching);
    QCheck.Test.make
      ~name:"count"
      (QCheck.quad
         QCheck.small_int
         QCheck.small_int
         QCheck.small_int
         QCheck.small_int)
      (fun (target, start_at, length, branching) ->
        QCheck.assume (start_at >= 0 && length > 1 && 1 < branching) ;
        let module P = MakeCountingPVM (struct
          let target = target
        end) in
        test_random_dissection (module P) start_at length branching);
    (* QCheck.Test.make
       ~name:"Mich"
       (QCheck.triple QCheck.small_int QCheck.small_int QCheck.small_int)
       (fun (start_at, length, branching) ->
         QCheck.assume (start_at >= 0 && length > 1 && 1 < branching) ;
         let module P = MakeMPVM (Fact20) in
         test_random_dissection (module P) start_at length branching); *)
  ]

let () =
  Alcotest.run
    "Refutation Game"
    [
      ("Dissection tests", qcheck_wrap testDissection);
      ( "RandomPVM",
        qcheck_wrap
          [
            testing_randomPVM perfect_perfect "perfect-perfect";
            testing_randomPVM random_random "random-random";
            testing_randomPVM random_perfect "random-perfect";
            testing_randomPVM perfect_random "perfect-random";
          ] );
      ( "CountingPVM",
        qcheck_wrap
          [
            testing_countPVM perfect_perfect "perfect-perfect";
            testing_countPVM random_random "random-random";
            testing_countPVM random_perfect "random-perfect";
            testing_countPVM perfect_random "perfect-random";
          ] );
      (* ( "Fact20PVM",
         qcheck_wrap
           [
             testing_mich perfect_perfect "perfect-perfect";
             testing_mich random_random "random-random";
             testing_mich random_perfect "random-perfect";
             testing_mich perfect_random "perfect-random";
             testing_mich failing_perfect "failing_perfect";
             testing_mich perfect_failing "perfect-failing";
           ] ); *)
    ]

(*
let test_machine (module M : PVM) =
  let module PCG = MakeGame (M) in
  let module S = Strategies (PCG) in
  S.test ()


let () =
  test_machine
    (module RandomPVM (struct
      let initial_prog =
        QCheck.Gen.generate1
          (QCheck.Gen.list_size
             QCheck.Gen.small_int
             (QCheck.Gen.int_range 0 100))
    end)) *)
