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

type annot = string list

type ('l, 'p) node =
  | Int of 'l * Z.t
  | String of 'l * string
  | Bytes of 'l * Bytes.t
  | Prim of 'l * 'p * ('l, 'p) node list * annot
  | Seq of 'l * ('l, 'p) node list

type canonical_location = int

let dummy_location = -1

let is_dummy_location loc = loc < 0

type 'p canonical = Canonical of (canonical_location, 'p) node

let canonical_location_encoding =
  let open Data_encoding in
  def
    "micheline.location"
    ~title:"Canonical location in a Micheline expression"
    ~description:
      "The location of a node in a Micheline expression tree in prefix order, \
       with zero being the root and adding one for every basic node, sequence \
       and primitive application."
  @@ int31

let location = function
  | Int (loc, _) -> loc
  | String (loc, _) -> loc
  | Bytes (loc, _) -> loc
  | Seq (loc, _) -> loc
  | Prim (loc, _, _, _) -> loc

let annotations = function
  | Int (_, _) -> []
  | String (_, _) -> []
  | Bytes (_, _) -> []
  | Seq (_, _) -> []
  | Prim (_, _, _, annots) -> annots

let root (Canonical expr) = expr

(* We use a defunctionalized CPS implementation. The type below corresponds to that of
   continuations. *)
type ('l, 'p, 'la, 'pa) cont =
  | Seq_cont of 'la * ('l, 'p, 'la, 'pa) list_cont
  | Prim_cont of 'la * 'pa * annot * ('l, 'p, 'la, 'pa) list_cont

and ('l, 'p, 'la, 'pa) list_cont =
  | List_cont of
      ('l, 'p) node list * ('la, 'pa) node list * ('l, 'p, 'la, 'pa) cont
  | Return

let strip_locations (type a b) (root : (a, b) node) : b canonical =
  let id =
    let id = ref (-1) in
    fun () ->
      incr id ;
      !id
  in
  let rec strip_locations l k =
    let id = id () in
    match l with
    | Int (_, v) -> (apply [@tailcall]) k (Int (id, v))
    | String (_, v) -> (apply [@tailcall]) k (String (id, v))
    | Bytes (_, v) -> (apply [@tailcall]) k (Bytes (id, v))
    | Seq (_, seq) ->
        (strip_locations_list [@tailcall]) seq [] (Seq_cont (id, k))
    | Prim (_, name, seq, annots) ->
        (strip_locations_list [@tailcall])
          seq
          []
          (Prim_cont (id, name, annots, k))
  and strip_locations_list ls acc k =
    match ls with
    | [] -> (apply_list [@tailcall]) k (List.rev acc)
    | x :: tl -> (strip_locations [@tailcall]) x (List_cont (tl, acc, k))
  and apply k node =
    match k with
    | List_cont (tl, acc, k) ->
        (strip_locations_list [@tailcall]) tl (node :: acc) k
    | Return -> node
  and apply_list k node_list =
    match k with
    | Seq_cont (id, k) -> (apply [@tailcall]) k (Seq (id, node_list))
    | Prim_cont (id, name, annots, k) ->
        (apply [@tailcall]) k (Prim (id, name, node_list, annots))
  in
  Canonical (strip_locations root Return)

let extract_locations :
    type l p. (l, p) node -> p canonical * (canonical_location * l) list =
 fun root ->
  let id =
    let id = ref (-1) in
    fun () ->
      incr id ;
      !id
  in
  let loc_table = ref [] in
  let rec strip_locations l k =
    let id = id () in
    match l with
    | Int (loc, v) ->
        loc_table := (id, loc) :: !loc_table ;
        (apply [@tailcall]) k (Int (id, v))
    | String (loc, v) ->
        loc_table := (id, loc) :: !loc_table ;
        (apply [@tailcall]) k (String (id, v))
    | Bytes (loc, v) ->
        loc_table := (id, loc) :: !loc_table ;
        (apply [@tailcall]) k (Bytes (id, v))
    | Seq (loc, seq) ->
        loc_table := (id, loc) :: !loc_table ;
        (strip_locations_list [@tailcall]) seq [] (Seq_cont (id, k))
    | Prim (loc, name, seq, annots) ->
        loc_table := (id, loc) :: !loc_table ;
        (strip_locations_list [@tailcall])
          seq
          []
          (Prim_cont (id, name, annots, k))
  and strip_locations_list ls acc k =
    match ls with
    | [] -> (apply_list [@tailcall]) k (List.rev acc)
    | x :: tl -> (strip_locations [@tailcall]) x (List_cont (tl, acc, k))
  and apply k node =
    match k with
    | List_cont (tl, acc, k) ->
        (strip_locations_list [@tailcall]) tl (node :: acc) k
    | Return -> node
  and apply_list k node_list =
    match k with
    | Seq_cont (id, k) -> (apply [@tailcall]) k (Seq (id, node_list))
    | Prim_cont (id, name, annots, k) ->
        (apply [@tailcall]) k (Prim (id, name, node_list, annots))
  in
  let stripped = strip_locations root Return in
  (Canonical stripped, List.rev !loc_table)

let inject_locations :
    type l p. (canonical_location -> l) -> p canonical -> (l, p) node =
 fun lookup (Canonical root) ->
  let rec inject_locations l k =
    match l with
    | Int (loc, v) -> (apply [@tailcall]) k (Int (lookup loc, v))
    | String (loc, v) -> (apply [@tailcall]) k (String (lookup loc, v))
    | Bytes (loc, v) -> (apply [@tailcall]) k (Bytes (lookup loc, v))
    | Seq (loc, seq) ->
        (inject_locations_list [@tailcall]) seq [] (Seq_cont (lookup loc, k))
    | Prim (loc, name, seq, annots) ->
        (inject_locations_list [@tailcall])
          seq
          []
          (Prim_cont (lookup loc, name, annots, k))
  and inject_locations_list ls acc k =
    match ls with
    | [] -> (apply_list [@tailcall]) k (List.rev acc)
    | x :: tl -> (inject_locations [@tailcall]) x (List_cont (tl, acc, k))
  and apply k node =
    match k with
    | List_cont (tl, acc, k) ->
        (inject_locations_list [@tailcall]) tl (node :: acc) k
    | Return -> node
  and apply_list k node_list =
    match k with
    | Seq_cont (id, k) -> (apply [@tailcall]) k (Seq (id, node_list))
    | Prim_cont (id, name, annots, k) ->
        (apply [@tailcall]) k (Prim (id, name, node_list, annots))
  in
  inject_locations root Return

let map : type a b. (a -> b) -> a canonical -> b canonical =
 fun f (Canonical expr) ->
  let rec map_node l k =
    match l with
    | (Int _ | String _ | Bytes _) as node -> (apply [@tailcall]) k node
    | Seq (loc, seq) -> (map_list [@tailcall]) seq [] (Seq_cont (loc, k))
    | Prim (loc, name, seq, annots) ->
        (map_list [@tailcall]) seq [] (Prim_cont (loc, f name, annots, k))
  and map_list ls acc k =
    match ls with
    | [] -> (apply_list [@tailcall]) k (List.rev acc)
    | x :: tl -> (map_node [@tailcall]) x (List_cont (tl, acc, k))
  and apply k node =
    match k with
    | List_cont (tl, acc, k) -> (map_list [@tailcall]) tl (node :: acc) k
    | Return -> node
  and apply_list k node_list =
    match k with
    | Seq_cont (id, k) -> (apply [@tailcall]) k (Seq (id, node_list))
    | Prim_cont (id, name, annots, k) ->
        (apply [@tailcall]) k (Prim (id, name, node_list, annots))
  in
  Canonical (map_node expr Return)

let map_node :
    type la lb pa pb. (la -> lb) -> (pa -> pb) -> (la, pa) node -> (lb, pb) node
    =
 fun fl fp node ->
  let rec map_node fl fp node k =
    match node with
    | Int (loc, v) -> (apply [@tailcall]) fl fp k (Int (fl loc, v))
    | String (loc, v) -> (apply [@tailcall]) fl fp k (String (fl loc, v))
    | Bytes (loc, v) -> (apply [@tailcall]) fl fp k (Bytes (fl loc, v))
    | Seq (loc, seq) ->
        (map_node_list [@tailcall]) fl fp seq [] (Seq_cont (fl loc, k))
    | Prim (loc, name, seq, annots) ->
        (map_node_list [@tailcall])
          fl
          fp
          seq
          []
          (Prim_cont (fl loc, fp name, annots, k))
  and map_node_list fl fp ls acc k =
    match ls with
    | [] -> (apply_list [@tailcall]) fl fp k (List.rev acc)
    | x :: tl -> (map_node [@tailcall]) fl fp x (List_cont (tl, acc, k))
  and apply fl fp k node =
    match k with
    | List_cont (tl, acc, k) ->
        (map_node_list [@tailcall]) fl fp tl (node :: acc) k
    | Return -> node
  and apply_list fl fp k node_list =
    match k with
    | Seq_cont (id, k) -> (apply [@tailcall]) fl fp k (Seq (id, node_list))
    | Prim_cont (id, name, annots, k) ->
        (apply [@tailcall]) fl fp k (Prim (id, name, node_list, annots))
  in
  (map_node [@tailcall]) fl fp node Return

type semantics = V0 | V1

let internal_canonical_encoding ~semantics ~variant prim_encoding =
  let open Data_encoding in
  let int_encoding = obj1 (req "int" z) in
  let string_encoding = obj1 (req "string" string) in
  let bytes_encoding = obj1 (req "bytes" bytes) in
  let int_encoding tag =
    case
      tag
      int_encoding
      ~title:"Int"
      (function Int (_, v) -> Some v | _ -> None)
      (fun v -> Int (0, v))
  in
  let string_encoding tag =
    case
      tag
      string_encoding
      ~title:"String"
      (function String (_, v) -> Some v | _ -> None)
      (fun v -> String (0, v))
  in
  let bytes_encoding tag =
    case
      tag
      bytes_encoding
      ~title:"Bytes"
      (function Bytes (_, v) -> Some v | _ -> None)
      (fun v -> Bytes (0, v))
  in
  let seq_encoding tag expr_encoding =
    case
      tag
      (list expr_encoding)
      ~title:"Sequence"
      (function Seq (_, v) -> Some v | _ -> None)
      (fun args -> Seq (0, args))
  in
  let annots_encoding =
    let split s =
      if s = "" && semantics <> V0 then []
      else
        let annots = String.split_on_char ' ' s in
        List.iter
          (fun a ->
            if String.length a > 255 then failwith "Oversized annotation")
          annots ;
        if String.concat " " annots <> s then
          failwith
            "Invalid annotation string, must be a sequence of valid \
             annotations with spaces" ;
        annots
    in
    splitted
      ~json:(list (Bounded.string 255))
      ~binary:(conv (String.concat " ") split string)
  in
  let application_encoding tag expr_encoding =
    case
      tag
      ~title:"Generic prim (any number of args with or without annot)"
      (obj3
         (req "prim" prim_encoding)
         (dft "args" (list expr_encoding) [])
         (dft "annots" annots_encoding []))
      (function
        | Prim (_, prim, args, annots) -> Some (prim, args, annots) | _ -> None)
      (fun (prim, args, annots) -> Prim (0, prim, args, annots))
  in
  let node_encoding =
    mu
      ("micheline." ^ variant ^ ".expression")
      (fun expr_encoding ->
        splitted
          ~json:
            (union
               ~tag_size:`Uint8
               [
                 int_encoding Json_only;
                 string_encoding Json_only;
                 bytes_encoding Json_only;
                 seq_encoding Json_only expr_encoding;
                 application_encoding Json_only expr_encoding;
               ])
          ~binary:
            (union
               ~tag_size:`Uint8
               [
                 int_encoding (Tag 0);
                 string_encoding (Tag 1);
                 seq_encoding (Tag 2) expr_encoding;
                 (* No args, no annot *)
                 case
                   (Tag 3)
                   ~title:"Prim (no args, annot)"
                   (obj1 (req "prim" prim_encoding))
                   (function Prim (_, v, [], []) -> Some v | _ -> None)
                   (fun v -> Prim (0, v, [], []));
                 (* No args, with annots *)
                 case
                   (Tag 4)
                   ~title:"Prim (no args + annot)"
                   (obj2
                      (req "prim" prim_encoding)
                      (req "annots" annots_encoding))
                   (function
                     | Prim (_, v, [], annots) -> Some (v, annots) | _ -> None)
                   (function (prim, annots) -> Prim (0, prim, [], annots));
                 (* Single arg, no annot *)
                 case
                   (Tag 5)
                   ~title:"Prim (1 arg, no annot)"
                   (obj2 (req "prim" prim_encoding) (req "arg" expr_encoding))
                   (function
                     | Prim (_, v, [arg], []) -> Some (v, arg) | _ -> None)
                   (function (prim, arg) -> Prim (0, prim, [arg], []));
                 (* Single arg, with annot *)
                 case
                   (Tag 6)
                   ~title:"Prim (1 arg + annot)"
                   (obj3
                      (req "prim" prim_encoding)
                      (req "arg" expr_encoding)
                      (req "annots" annots_encoding))
                   (function
                     | Prim (_, prim, [arg], annots) -> Some (prim, arg, annots)
                     | _ -> None)
                   (fun (prim, arg, annots) -> Prim (0, prim, [arg], annots));
                 (* Two args, no annot *)
                 case
                   (Tag 7)
                   ~title:"Prim (2 args, no annot)"
                   (obj3
                      (req "prim" prim_encoding)
                      (req "arg1" expr_encoding)
                      (req "arg2" expr_encoding))
                   (function
                     | Prim (_, prim, [arg1; arg2], []) ->
                         Some (prim, arg1, arg2)
                     | _ -> None)
                   (fun (prim, arg1, arg2) -> Prim (0, prim, [arg1; arg2], []));
                 (* Two args, with annots *)
                 case
                   (Tag 8)
                   ~title:"Prim (2 args + annot)"
                   (obj4
                      (req "prim" prim_encoding)
                      (req "arg1" expr_encoding)
                      (req "arg2" expr_encoding)
                      (req "annots" annots_encoding))
                   (function
                     | Prim (_, prim, [arg1; arg2], annots) ->
                         Some (prim, arg1, arg2, annots)
                     | _ -> None)
                   (fun (prim, arg1, arg2, annots) ->
                     Prim (0, prim, [arg1; arg2], annots));
                 (* General case *)
                 application_encoding (Tag 9) expr_encoding;
                 bytes_encoding (Tag 10);
               ]))
  in
  conv
    (function Canonical node -> node)
    (fun node -> strip_locations node)
    node_encoding

let canonical_encoding ~variant prim_encoding =
  internal_canonical_encoding ~semantics:V1 ~variant prim_encoding

let canonical_encoding_v1 ~variant prim_encoding =
  internal_canonical_encoding ~semantics:V1 ~variant prim_encoding

let canonical_encoding_v0 ~variant prim_encoding =
  internal_canonical_encoding ~semantics:V0 ~variant prim_encoding

let table_encoding ~variant location_encoding prim_encoding =
  let open Data_encoding in
  conv
    (fun node ->
      let (canon, assoc) = extract_locations node in
      let (_, table) = List.split assoc in
      (canon, table))
    (fun (canon, table) ->
      let table = Array.of_list table in
      inject_locations (fun i -> table.(i)) canon)
    (obj2
       (req "expression" (canonical_encoding ~variant prim_encoding))
       (req "locations" (list location_encoding)))

let erased_encoding ~variant default_location prim_encoding =
  let open Data_encoding in
  conv
    (fun node -> strip_locations node)
    (fun canon -> inject_locations (fun _ -> default_location) canon)
    (canonical_encoding ~variant prim_encoding)

(** Testing
    -------
    Component:    Micheline
    Invocation:   dune build @src/lib_micheline/runtest
    Subject:      Test preservation of semantics wrt original implementation
*)

let%test_module "semantics_preservation" =
  (module struct
    module Original = struct
      let strip_locations root =
        let id =
          let id = ref (-1) in
          fun () ->
            incr id ;
            !id
        in
        let rec strip_locations l =
          let id = id () in
          match l with
          | Int (_, v) -> Int (id, v)
          | String (_, v) -> String (id, v)
          | Bytes (_, v) -> Bytes (id, v)
          | Seq (_, seq) -> Seq (id, List.map strip_locations seq)
          | Prim (_, name, seq, annots) ->
              Prim (id, name, List.map strip_locations seq, annots)
        in
        Canonical (strip_locations root)

      let extract_locations root =
        let id =
          let id = ref (-1) in
          fun () ->
            incr id ;
            !id
        in
        let loc_table = ref [] in
        let rec strip_locations l =
          let id = id () in
          match l with
          | Int (loc, v) ->
              loc_table := (id, loc) :: !loc_table ;
              Int (id, v)
          | String (loc, v) ->
              loc_table := (id, loc) :: !loc_table ;
              String (id, v)
          | Bytes (loc, v) ->
              loc_table := (id, loc) :: !loc_table ;
              Bytes (id, v)
          | Seq (loc, seq) ->
              loc_table := (id, loc) :: !loc_table ;
              Seq (id, List.map strip_locations seq)
          | Prim (loc, name, seq, annots) ->
              loc_table := (id, loc) :: !loc_table ;
              Prim (id, name, List.map strip_locations seq, annots)
        in
        let stripped = strip_locations root in
        (Canonical stripped, List.rev !loc_table)

      let inject_locations lookup (Canonical root) =
        let rec inject_locations l =
          match l with
          | Int (loc, v) -> Int (lookup loc, v)
          | String (loc, v) -> String (lookup loc, v)
          | Bytes (loc, v) -> Bytes (lookup loc, v)
          | Seq (loc, seq) -> Seq (lookup loc, List.map inject_locations seq)
          | Prim (loc, name, seq, annots) ->
              Prim (lookup loc, name, List.map inject_locations seq, annots)
        in
        inject_locations root

      let map f (Canonical expr) =
        let rec map_node f = function
          | (Int _ | String _ | Bytes _) as node -> node
          | Seq (loc, seq) -> Seq (loc, List.map (map_node f) seq)
          | Prim (loc, name, seq, annots) ->
              Prim (loc, f name, List.map (map_node f) seq, annots)
        in
        Canonical (map_node f expr)

      let rec map_node fl fp = function
        | Int (loc, v) -> Int (fl loc, v)
        | String (loc, v) -> String (fl loc, v)
        | Bytes (loc, v) -> Bytes (fl loc, v)
        | Seq (loc, seq) -> Seq (fl loc, List.map (map_node fl fp) seq)
        | Prim (loc, name, seq, annots) ->
            Prim (fl loc, fp name, List.map (map_node fl fp) seq, annots)
    end

    module Sampler = struct
      (* Sampler copied from [micheline_benchmarks.ml] - lib-micheline cannot depend
         on lib-shell-benchmarks. *)

      type 'a sampler = Random.State.t -> 'a

      type width_function = depth:int -> int sampler

      type node_kind =
        | Int_node
        | String_node
        | Bytes_node
        | Seq_node
        | Prim_node

      (* We skew the distribution towards non-leaf nodes by repeating the
           relevant kinds ;) *)
      let all_kinds = [|Int_node; String_node; Bytes_node; Seq_node; Prim_node|]

      let sample_kind : node_kind sampler =
       fun rng_state ->
        let i = Random.State.int rng_state (Array.length all_kinds) in
        all_kinds.(i)

      let sample_string _ = ""

      let sample_bytes _ = Bytes.empty

      let sample_z _ = Z.zero

      let sample (w : width_function) rng_state =
        let rec sample depth rng_state k =
          match sample_kind rng_state with
          | Int_node -> k (Int (0, sample_z rng_state))
          | String_node -> k (String (0, sample_string rng_state))
          | Bytes_node -> k (Bytes (0, sample_bytes rng_state))
          | Seq_node ->
              let width = w ~depth rng_state in
              sample_list
                depth
                width
                []
                (fun terms -> k (Seq (0, terms)))
                rng_state
          | Prim_node ->
              let width = w ~depth rng_state in
              sample_list
                depth
                width
                []
                (fun terms -> k (Prim (0, (), terms, [])))
                rng_state
        and sample_list depth width acc k rng_state =
          if width < 0 then invalid_arg "sample_list: negative width"
          else if width = 0 then k (List.rev acc)
          else
            sample (depth + 1) rng_state (fun x ->
                sample_list depth (width - 1) (x :: acc) k rng_state)
        in
        sample 0 rng_state (fun x -> x)

      let sample_in_interval min max state =
        if max - min >= 0 then min + Random.State.int state (max - min + 1)
        else invalid_arg "sample_in_interval"

      let reasonable_width_function ~depth rng_state =
        (* Entirely ad-hoc *)
        sample_in_interval 0 (20 / (Bits.numbits depth + 1)) rng_state

      let sample = sample reasonable_width_function
    end

    let rng_state = Random.State.make [|0x1337; 0x533D|]

    let rec sample_and_check_n_times n f g =
      if n <= 0 then ()
      else
        let term = Sampler.sample rng_state in
        (* Is this a legit use of polymorphic equality? *)
        assert (f term = g term) ;
        sample_and_check_n_times (n - 1) f g

    let rec sample_and_check_n_times_canon n f g =
      if n <= 0 then ()
      else
        let term = Sampler.sample rng_state in
        let term = strip_locations term in
        (* Is this a legit use of polymorphic equality? *)
        assert (f term = g term) ;
        sample_and_check_n_times_canon (n - 1) f g

    let%test_unit "strip_locations" =
      sample_and_check_n_times 1_000 Original.strip_locations strip_locations

    let%test_unit "extract_locations" =
      sample_and_check_n_times
        1_000
        Original.extract_locations
        extract_locations

    let%test_unit "inject_locations" =
      sample_and_check_n_times_canon
        1_000
        (Original.inject_locations (fun i -> i))
        (inject_locations (fun i -> i))

    let%test_unit "map" =
      sample_and_check_n_times_canon
        1_000
        (Original.map (fun _i -> ()))
        (map (fun _i -> ()))

    let%test_unit "map_node" =
      sample_and_check_n_times
        1_000
        (Original.map_node (fun _i -> ()) (fun _i -> ()))
        (map_node (fun _i -> ()) (fun _i -> ()))
  end)
