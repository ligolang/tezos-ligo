(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2019-2020 Nomadic Labs <contact@nomadic-labs.com>           *)
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

open Storage_sigs

module Registered = struct
  let ghost = false
end

module Ghost = struct
  let ghost = true
end

module Make_encoder (V : VALUE) = struct
  let of_bytes ~key b =
    match Data_encoding.Binary.of_bytes V.encoding b with
    | None ->
        error (Raw_context.Storage_error (Corrupted_data key))
    | Some v ->
        Ok v

  let to_bytes v =
    match Data_encoding.Binary.to_bytes V.encoding v with
    | Some b ->
        b
    | None ->
        Bytes.empty
end

let len_name = "len"

let data_name = "data"

let encode_len_value bytes =
  let length = Bytes.length bytes in
  Data_encoding.(Binary.to_bytes_exn int31) length

let decode_len_value key len =
  match Data_encoding.(Binary.of_bytes int31) len with
  | None ->
      error (Raw_context.Storage_error (Corrupted_data key))
  | Some len ->
      ok len

let map_key f = function `Key k -> `Key (f k) | `Dir k -> `Dir (f k)

module Make_subcontext (R : REGISTER) (C : Raw_context.T) (N : NAME) :
  Raw_context.T with type t = C.t = struct
  type t = C.t

  type context = t

  let name_length = List.length N.name

  let to_key k = N.name @ k

  let of_key k = Misc.remove_elem_from_list name_length k

  let mem t k = C.mem t (to_key k)

  let dir_mem t k = C.dir_mem t (to_key k)

  let get t k = C.get t (to_key k)

  let get_option t k = C.get_option t (to_key k)

  let init t k v = C.init t (to_key k) v

  let set t k v = C.set t (to_key k) v

  let init_set t k v = C.init_set t (to_key k) v

  let set_option t k v = C.set_option t (to_key k) v

  let delete t k = C.delete t (to_key k)

  let remove t k = C.remove t (to_key k)

  let remove_rec t k = C.remove_rec t (to_key k)

  let copy t ~from ~to_ = C.copy t ~from:(to_key from) ~to_:(to_key to_)

  let fold t k ~init ~f =
    C.fold t (to_key k) ~init ~f:(fun k acc -> f (map_key of_key k) acc)

  let keys t k = C.keys t (to_key k) >|= fun keys -> List.map of_key keys

  let fold_keys t k ~init ~f =
    C.fold_keys t (to_key k) ~init ~f:(fun k acc -> f (of_key k) acc)

  let project = C.project

  let absolute_key c k = C.absolute_key c (to_key k)

  let consume_gas = C.consume_gas

  let check_enough_gas = C.check_enough_gas

  let description =
    let description =
      if R.ghost then Storage_description.create () else C.description
    in
    Storage_description.register_named_subcontext description N.name
end

module Make_single_data_storage
    (R : REGISTER)
    (C : Raw_context.T)
    (N : NAME)
    (V : VALUE) : Single_data_storage with type t = C.t and type value = V.t =
struct
  type t = C.t

  type context = t

  type value = V.t

  let mem t = C.mem t N.name

  include Make_encoder (V)

  let get t =
    C.get t N.name
    >>=? fun b ->
    let key = C.absolute_key t N.name in
    Lwt.return (of_bytes ~key b)

  let get_option t =
    C.get_option t N.name
    >|= function
    | None ->
        ok_none
    | Some b ->
        let key = C.absolute_key t N.name in
        of_bytes ~key b >|? fun v -> Some v

  let init t v = C.init t N.name (to_bytes v) >|=? fun t -> C.project t

  let set t v = C.set t N.name (to_bytes v) >|=? fun t -> C.project t

  let init_set t v = C.init_set t N.name (to_bytes v) >|= fun t -> C.project t

  let set_option t v =
    C.set_option t N.name (Option.map to_bytes v) >|= fun t -> C.project t

  let remove t = C.remove t N.name >|= fun t -> C.project t

  let delete t = C.delete t N.name >|=? fun t -> C.project t

  let () =
    let open Storage_description in
    let description =
      if R.ghost then Storage_description.create () else C.description
    in
    register_value
      ~get:get_option
      (register_named_subcontext description N.name)
      V.encoding
end

module type INDEX = sig
  type t

  val path_length : int

  val to_path : t -> string list -> string list

  val of_path : string list -> t option

  type 'a ipath

  val args : ('a, t, 'a ipath) Storage_description.args
end

module Pair (I1 : INDEX) (I2 : INDEX) : INDEX with type t = I1.t * I2.t =
struct
  type t = I1.t * I2.t

  let path_length = I1.path_length + I2.path_length

  let to_path (x, y) l = I1.to_path x (I2.to_path y l)

  let of_path l =
    match Misc.take I1.path_length l with
    | None ->
        None
    | Some (l1, l2) -> (
      match (I1.of_path l1, I2.of_path l2) with
      | (Some x, Some y) ->
          Some (x, y)
      | _ ->
          None )

  type 'a ipath = 'a I1.ipath I2.ipath

  let args = Storage_description.Pair (I1.args, I2.args)
end

module Make_data_set_storage (C : Raw_context.T) (I : INDEX) :
  Data_set_storage with type t = C.t and type elt = I.t = struct
  type t = C.t

  type context = t

  type elt = I.t

  let inited = Bytes.of_string "inited"

  let mem s i = C.mem s (I.to_path i [])

  let add s i = C.init_set s (I.to_path i []) inited >|= fun t -> C.project t

  let del s i = C.remove s (I.to_path i []) >|= fun t -> C.project t

  let set s i = function true -> add s i | false -> del s i

  let clear s = C.remove_rec s [] >|= fun t -> C.project t

  let fold s ~init ~f =
    let rec dig i path acc =
      if Compare.Int.(i <= 1) then
        C.fold s path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir _ ->
                Lwt.return acc
            | `Key file -> (
              match I.of_path file with
              | None ->
                  assert false
              | Some p ->
                  f p acc ))
      else
        C.fold s path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir k ->
                dig (i - 1) k acc
            | `Key _ ->
                Lwt.return acc)
    in
    dig I.path_length [] init

  let elements s = fold s ~init:[] ~f:(fun p acc -> Lwt.return (p :: acc))

  let () =
    let open Storage_description in
    let unpack = unpack I.args in
    register_value (* TODO fixme 'elements...' *)
      ~get:(fun c ->
        let (c, k) = unpack c in
        mem c k >>= function true -> return_some true | false -> return_none)
      (register_indexed_subcontext
         ~list:(fun c -> elements c >|= ok)
         C.description
         I.args)
      Data_encoding.bool
end

module Make_indexed_data_storage (C : Raw_context.T) (I : INDEX) (V : VALUE) :
  Indexed_data_storage
    with type t = C.t
     and type key = I.t
     and type value = V.t = struct
  type t = C.t

  type context = t

  type key = I.t

  type value = V.t

  include Make_encoder (V)

  let mem s i = C.mem s (I.to_path i [])

  let get s i =
    C.get s (I.to_path i [])
    >>=? fun b ->
    let key = C.absolute_key s (I.to_path i []) in
    Lwt.return (of_bytes ~key b)

  let get_option s i =
    C.get_option s (I.to_path i [])
    >|= function
    | None ->
        ok_none
    | Some b ->
        let key = C.absolute_key s (I.to_path i []) in
        of_bytes ~key b >|? fun v -> Some v

  let set s i v =
    C.set s (I.to_path i []) (to_bytes v) >|=? fun t -> C.project t

  let init s i v =
    C.init s (I.to_path i []) (to_bytes v) >|=? fun t -> C.project t

  let init_set s i v =
    C.init_set s (I.to_path i []) (to_bytes v) >|= fun t -> C.project t

  let set_option s i v =
    C.set_option s (I.to_path i []) (Option.map to_bytes v)
    >|= fun t -> C.project t

  let remove s i = C.remove s (I.to_path i []) >|= fun t -> C.project t

  let delete s i = C.delete s (I.to_path i []) >|=? fun t -> C.project t

  let clear s = C.remove_rec s [] >|= fun t -> C.project t

  let fold_keys s ~init ~f =
    let rec dig i path acc =
      if Compare.Int.(i <= 1) then
        C.fold s path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir _ ->
                Lwt.return acc
            | `Key file -> (
              match I.of_path file with
              | None ->
                  assert false
              | Some path ->
                  f path acc ))
      else
        C.fold s path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir k ->
                dig (i - 1) k acc
            | `Key _ ->
                Lwt.return acc)
    in
    dig I.path_length [] init

  let fold s ~init ~f =
    let f path acc =
      get s path
      >>= function
      | Error _ ->
          (* FIXME: silently ignore unparsable data *)
          Lwt.return acc
      | Ok v ->
          f path v acc
    in
    fold_keys s ~init ~f

  let bindings s =
    fold s ~init:[] ~f:(fun p v acc -> Lwt.return ((p, v) :: acc))

  let keys s = fold_keys s ~init:[] ~f:(fun p acc -> Lwt.return (p :: acc))

  let () =
    let open Storage_description in
    let unpack = unpack I.args in
    register_value
      ~get:(fun c ->
        let (c, k) = unpack c in
        get_option c k)
      (register_indexed_subcontext
         ~list:(fun c -> keys c >|= ok)
         C.description
         I.args)
      V.encoding
end

(* Internal-use-only version of {!Make_indexed_carbonated_data_storage} to
   expose fold_keys_unaccounted *)
module Make_indexed_carbonated_data_storage_INTERNAL
    (C : Raw_context.T)
    (I : INDEX)
    (V : VALUE) =
struct
  type t = C.t

  type context = t

  type key = I.t

  type value = V.t

  include Make_encoder (V)

  let data_key i = I.to_path i [data_name]

  let len_key i = I.to_path i [len_name]

  let consume_mem_gas c =
    C.consume_gas c (Gas_limit_repr.read_bytes_cost Z.zero)

  let existing_size c i =
    C.get_option c (len_key i)
    >|= function
    | None ->
        ok (0, false)
    | Some len ->
        decode_len_value (len_key i) len >|? fun len -> (len, true)

  let consume_read_gas get c i =
    get c (len_key i)
    >>=? fun len ->
    Lwt.return
      ( decode_len_value (len_key i) len
      >>? fun len ->
      C.consume_gas c (Gas_limit_repr.read_bytes_cost (Z.of_int len)) )

  let consume_serialize_write_gas set c i v =
    let bytes = to_bytes v in
    let len = Bytes.length bytes in
    C.consume_gas c (Gas_limit_repr.alloc_mbytes_cost len)
    >>?= fun c ->
    C.consume_gas c (Gas_limit_repr.write_bytes_cost (Z.of_int len))
    >>?= fun c ->
    set c (len_key i) (encode_len_value bytes) >|=? fun c -> (c, bytes)

  let consume_remove_gas del c i =
    C.consume_gas c (Gas_limit_repr.write_bytes_cost Z.zero)
    >>?= fun c -> del c (len_key i)

  let mem s i =
    consume_mem_gas s
    >>?= fun s ->
    C.mem s (data_key i) >|= fun exists -> ok (C.project s, exists)

  let get s i =
    consume_read_gas C.get s i
    >>=? fun s ->
    C.get s (data_key i)
    >>=? fun b ->
    let key = C.absolute_key s (data_key i) in
    Lwt.return (of_bytes ~key b >|? fun v -> (C.project s, v))

  let get_option s i =
    consume_mem_gas s
    >>?= fun s ->
    C.mem s (data_key i)
    >>= fun exists ->
    if exists then get s i >|=? fun (s, v) -> (s, Some v)
    else return (C.project s, None)

  let set s i v =
    existing_size s i
    >>=? fun (prev_size, _) ->
    consume_serialize_write_gas C.set s i v
    >>=? fun (s, bytes) ->
    C.set s (data_key i) bytes
    >|=? fun t ->
    let size_diff = Bytes.length bytes - prev_size in
    (C.project t, size_diff)

  let init s i v =
    consume_serialize_write_gas C.init s i v
    >>=? fun (s, bytes) ->
    C.init s (data_key i) bytes
    >|=? fun t ->
    let size = Bytes.length bytes in
    (C.project t, size)

  let init_set s i v =
    let init_set s i v = C.init_set s i v >|= ok in
    existing_size s i
    >>=? fun (prev_size, existed) ->
    consume_serialize_write_gas init_set s i v
    >>=? fun (s, bytes) ->
    init_set s (data_key i) bytes
    >|=? fun t ->
    let size_diff = Bytes.length bytes - prev_size in
    (C.project t, size_diff, existed)

  let remove s i =
    let remove s i = C.remove s i >|= ok in
    existing_size s i
    >>=? fun (prev_size, existed) ->
    consume_remove_gas remove s i
    >>=? fun s ->
    remove s (data_key i) >|=? fun t -> (C.project t, prev_size, existed)

  let delete s i =
    existing_size s i
    >>=? fun (prev_size, _) ->
    consume_remove_gas C.delete s i
    >>=? fun s -> C.delete s (data_key i) >|=? fun t -> (C.project t, prev_size)

  let set_option s i v =
    match v with None -> remove s i | Some v -> init_set s i v

  let fold_keys_unaccounted s ~init ~f =
    let rec dig i path acc =
      if Compare.Int.(i <= 0) then
        C.fold s path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir _ ->
                Lwt.return acc
            | `Key file -> (
              match List.rev file with
              | last :: _ when Compare.String.(last = len_name) ->
                  Lwt.return acc
              | last :: rest when Compare.String.(last = data_name) -> (
                  let file = List.rev rest in
                  match I.of_path file with
                  | None ->
                      assert false
                  | Some path ->
                      f path acc )
              | _ ->
                  assert false ))
      else
        C.fold s path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir k ->
                dig (i - 1) k acc
            | `Key _ ->
                Lwt.return acc)
    in
    dig I.path_length [] init

  let keys_unaccounted s =
    fold_keys_unaccounted s ~init:[] ~f:(fun p acc -> Lwt.return (p :: acc))

  let () =
    let open Storage_description in
    let unpack = unpack I.args in
    register_value (* TODO export consumed gas ?? *)
      ~get:(fun c ->
        let (c, k) = unpack c in
        get_option c k >|=? fun (_, v) -> v)
      (register_indexed_subcontext
         ~list:(fun c -> keys_unaccounted c >|= ok)
         C.description
         I.args)
      V.encoding
end

module Make_indexed_carbonated_data_storage : functor
  (C : Raw_context.T)
  (I : INDEX)
  (V : VALUE)
  ->
  Non_iterable_indexed_carbonated_data_storage
    with type t = C.t
     and type key = I.t
     and type value = V.t =
  Make_indexed_carbonated_data_storage_INTERNAL

module Make_carbonated_data_set_storage (C : Raw_context.T) (I : INDEX) :
  Carbonated_data_set_storage with type t = C.t and type elt = I.t = struct
  module V = struct
    type t = unit

    let encoding = Data_encoding.unit
  end

  module M = Make_indexed_carbonated_data_storage_INTERNAL (C) (I) (V)

  type t = M.t

  type context = t

  type elt = I.t

  let mem = M.mem

  let init s i = M.init s i ()

  let del s i = M.remove s i

  let fold_keys_unaccounted = M.fold_keys_unaccounted
end

module Make_indexed_data_snapshotable_storage
    (C : Raw_context.T)
    (Snapshot_index : INDEX)
    (I : INDEX)
    (V : VALUE) :
  Indexed_data_snapshotable_storage
    with type t = C.t
     and type snapshot = Snapshot_index.t
     and type key = I.t
     and type value = V.t = struct
  type snapshot = Snapshot_index.t

  let data_name = ["current"]

  let snapshot_name = ["snapshot"]

  module C_data =
    Make_subcontext (Registered) (C)
      (struct
        let name = data_name
      end)

  module C_snapshot =
    Make_subcontext (Registered) (C)
      (struct
        let name = snapshot_name
      end)

  include Make_indexed_data_storage (C_data) (I) (V)
  module Snapshot =
    Make_indexed_data_storage (C_snapshot) (Pair (Snapshot_index) (I)) (V)

  let snapshot_path id = snapshot_name @ Snapshot_index.to_path id []

  let snapshot_exists s id = C.dir_mem s (snapshot_path id)

  let snapshot s id =
    C.copy s ~from:data_name ~to_:(snapshot_path id) >|=? fun t -> C.project t

  let delete_snapshot s id =
    C.remove_rec s (snapshot_path id) >|= fun t -> C.project t
end

module Make_indexed_subcontext (C : Raw_context.T) (I : INDEX) :
  Indexed_raw_context
    with type t = C.t
     and type key = I.t
     and type 'a ipath = 'a I.ipath = struct
  type t = C.t

  type context = t

  type key = I.t

  type 'a ipath = 'a I.ipath

  let clear t = C.remove_rec t [] >|= fun t -> C.project t

  let fold_keys t ~init ~f =
    let rec dig i path acc =
      if Compare.Int.(i <= 0) then
        match I.of_path path with
        | None ->
            assert false
        | Some path ->
            f path acc
      else
        C.fold t path ~init:acc ~f:(fun k acc ->
            match k with
            | `Dir k ->
                dig (i - 1) k acc
            | `Key _ ->
                Lwt.return acc)
    in
    dig I.path_length [] init

  let keys t = fold_keys t ~init:[] ~f:(fun i acc -> Lwt.return (i :: acc))

  let list t k = C.fold t k ~init:[] ~f:(fun k acc -> Lwt.return (k :: acc))

  let remove_rec t k = C.remove_rec t (I.to_path k [])

  let copy t ~from ~to_ =
    C.copy t ~from:(I.to_path from []) ~to_:(I.to_path to_ [])

  let description =
    Storage_description.register_indexed_subcontext
      ~list:(fun c -> keys c >|= ok)
      C.description
      I.args

  let unpack = Storage_description.unpack I.args

  let pack = Storage_description.pack I.args

  module Raw_context = struct
    type t = C.t I.ipath

    type context = t

    let to_key i k = I.to_path i k

    let of_key k = Misc.remove_elem_from_list I.path_length k

    let mem c k =
      let (t, i) = unpack c in
      C.mem t (to_key i k)

    let dir_mem c k =
      let (t, i) = unpack c in
      C.dir_mem t (to_key i k)

    let get c k =
      let (t, i) = unpack c in
      C.get t (to_key i k)

    let get_option c k =
      let (t, i) = unpack c in
      C.get_option t (to_key i k)

    let init c k v =
      let (t, i) = unpack c in
      C.init t (to_key i k) v >|=? fun t -> pack t i

    let set c k v =
      let (t, i) = unpack c in
      C.set t (to_key i k) v >|=? fun t -> pack t i

    let init_set c k v =
      let (t, i) = unpack c in
      C.init_set t (to_key i k) v >|= fun t -> pack t i

    let set_option c k v =
      let (t, i) = unpack c in
      C.set_option t (to_key i k) v >|= fun t -> pack t i

    let delete c k =
      let (t, i) = unpack c in
      C.delete t (to_key i k) >|=? fun t -> pack t i

    let remove c k =
      let (t, i) = unpack c in
      C.remove t (to_key i k) >|= fun t -> pack t i

    let remove_rec c k =
      let (t, i) = unpack c in
      C.remove_rec t (to_key i k) >|= fun t -> pack t i

    let copy c ~from ~to_ =
      let (t, i) = unpack c in
      C.copy t ~from:(to_key i from) ~to_:(to_key i to_) >|=? fun t -> pack t i

    let fold c k ~init ~f =
      let (t, i) = unpack c in
      C.fold t (to_key i k) ~init ~f:(fun k acc -> f (map_key of_key k) acc)

    let keys c k =
      let (t, i) = unpack c in
      C.keys t (to_key i k) >|= fun keys -> List.map of_key keys

    let fold_keys c k ~init ~f =
      let (t, i) = unpack c in
      C.fold_keys t (to_key i k) ~init ~f:(fun k acc -> f (of_key k) acc)

    let project c =
      let (t, _) = unpack c in
      C.project t

    let absolute_key c k =
      let (t, i) = unpack c in
      C.absolute_key t (to_key i k)

    let consume_gas c g =
      let (t, i) = unpack c in
      C.consume_gas t g >>? fun t -> ok (pack t i)

    let check_enough_gas c g =
      let (t, _i) = unpack c in
      C.check_enough_gas t g

    let description = description
  end

  let resolve t prefix =
    let rec loop i prefix = function
      | [] when Compare.Int.(i = I.path_length) -> (
        match I.of_path prefix with
        | None ->
            assert false
        | Some path ->
            Lwt.return [path] )
      | [] ->
          list t prefix
          >>= fun prefixes ->
          Lwt_list.map_s
            (function `Key prefix | `Dir prefix -> loop (i + 1) prefix [])
            prefixes
          >|= List.flatten
      | [d] when Compare.Int.(i = I.path_length - 1) ->
          if Compare.Int.(i >= I.path_length) then invalid_arg "IO.resolve" ;
          list t prefix
          >>= fun prefixes ->
          Lwt_list.map_s
            (function
              | `Key prefix | `Dir prefix -> (
                match
                  Misc.remove_prefix ~prefix:d (List.hd (List.rev prefix))
                with
                | None ->
                    Lwt.return_nil
                | Some _ ->
                    loop (i + 1) prefix [] ))
            prefixes
          >|= List.flatten
      | "" :: ds ->
          list t prefix
          >>= fun prefixes ->
          Lwt_list.map_s
            (function `Key prefix | `Dir prefix -> loop (i + 1) prefix ds)
            prefixes
          >|= List.flatten
      | d :: ds -> (
          if Compare.Int.(i >= I.path_length) then invalid_arg "IO.resolve" ;
          C.dir_mem t (prefix @ [d])
          >>= function
          | true -> loop (i + 1) (prefix @ [d]) ds | false -> Lwt.return_nil )
    in
    loop 0 [] prefix

  module Make_set (R : REGISTER) (N : NAME) = struct
    type t = C.t

    type context = t

    type elt = I.t

    let inited = Bytes.of_string "inited"

    let mem s i = Raw_context.mem (pack s i) N.name

    let add s i =
      Raw_context.init_set (pack s i) N.name inited
      >|= fun c ->
      let (s, _) = unpack c in
      C.project s

    let del s i =
      Raw_context.remove (pack s i) N.name
      >|= fun c ->
      let (s, _) = unpack c in
      C.project s

    let set s i = function true -> add s i | false -> del s i

    let clear s =
      fold_keys s ~init:s ~f:(fun i s ->
          Raw_context.remove (pack s i) N.name
          >|= fun c ->
          let (s, _) = unpack c in
          s)
      >|= fun t -> C.project t

    let fold s ~init ~f =
      fold_keys s ~init ~f:(fun i acc ->
          mem s i >>= function true -> f i acc | false -> Lwt.return acc)

    let elements s = fold s ~init:[] ~f:(fun p acc -> Lwt.return (p :: acc))

    let () =
      let open Storage_description in
      let unpack = unpack I.args in
      let description =
        if R.ghost then Storage_description.create ()
        else Raw_context.description
      in
      register_value
        ~get:(fun c ->
          let (c, k) = unpack c in
          mem c k
          >>= function true -> return_some true | false -> return_none)
        (register_named_subcontext description N.name)
        Data_encoding.bool
  end

  module Make_map (N : NAME) (V : VALUE) = struct
    type t = C.t

    type context = t

    type key = I.t

    type value = V.t

    include Make_encoder (V)

    let mem s i = Raw_context.mem (pack s i) N.name

    let get s i =
      Raw_context.get (pack s i) N.name
      >>=? fun b ->
      let key = Raw_context.absolute_key (pack s i) N.name in
      Lwt.return (of_bytes ~key b)

    let get_option s i =
      Raw_context.get_option (pack s i) N.name
      >|= function
      | None ->
          ok_none
      | Some b ->
          let key = Raw_context.absolute_key (pack s i) N.name in
          of_bytes ~key b >|? fun v -> Some v

    let set s i v =
      Raw_context.set (pack s i) N.name (to_bytes v)
      >|=? fun c ->
      let (s, _) = unpack c in
      C.project s

    let init s i v =
      Raw_context.init (pack s i) N.name (to_bytes v)
      >|=? fun c ->
      let (s, _) = unpack c in
      C.project s

    let init_set s i v =
      Raw_context.init_set (pack s i) N.name (to_bytes v)
      >|= fun c ->
      let (s, _) = unpack c in
      C.project s

    let set_option s i v =
      Raw_context.set_option (pack s i) N.name (Option.map to_bytes v)
      >|= fun c ->
      let (s, _) = unpack c in
      C.project s

    let remove s i =
      Raw_context.remove (pack s i) N.name
      >|= fun c ->
      let (s, _) = unpack c in
      C.project s

    let delete s i =
      Raw_context.delete (pack s i) N.name
      >|=? fun c ->
      let (s, _) = unpack c in
      C.project s

    let clear s =
      fold_keys s ~init:s ~f:(fun i s ->
          Raw_context.remove (pack s i) N.name
          >|= fun c ->
          let (s, _) = unpack c in
          s)
      >|= fun t -> C.project t

    let fold s ~init ~f =
      fold_keys s ~init ~f:(fun i acc ->
          get s i >>= function Error _ -> Lwt.return acc | Ok v -> f i v acc)

    let bindings s =
      fold s ~init:[] ~f:(fun p v acc -> Lwt.return ((p, v) :: acc))

    let fold_keys s ~init ~f =
      fold_keys s ~init ~f:(fun i acc ->
          mem s i >>= function false -> Lwt.return acc | true -> f i acc)

    let keys s = fold_keys s ~init:[] ~f:(fun p acc -> Lwt.return (p :: acc))

    let () =
      let open Storage_description in
      let unpack = unpack I.args in
      register_value
        ~get:(fun c ->
          let (c, k) = unpack c in
          get_option c k)
        (register_named_subcontext Raw_context.description N.name)
        V.encoding
  end

  module Make_carbonated_map (N : NAME) (V : VALUE) = struct
    type t = C.t

    type context = t

    type key = I.t

    type value = V.t

    include Make_encoder (V)

    let len_name = len_name :: N.name

    let data_name = data_name :: N.name

    let consume_mem_gas c =
      Raw_context.consume_gas c (Gas_limit_repr.read_bytes_cost Z.zero)

    let existing_size c =
      Raw_context.get_option c len_name
      >|= function
      | None ->
          ok (0, false)
      | Some len ->
          decode_len_value len_name len >|? fun len -> (len, true)

    let consume_read_gas get c =
      get c len_name
      >>=? fun len ->
      Lwt.return
        ( decode_len_value len_name len
        >>? fun len ->
        Raw_context.consume_gas
          c
          (Gas_limit_repr.read_bytes_cost (Z.of_int len)) )

    let consume_write_gas set c v =
      let bytes = to_bytes v in
      let len = Bytes.length bytes in
      Raw_context.consume_gas
        c
        (Gas_limit_repr.write_bytes_cost (Z.of_int len))
      >>?= fun c ->
      set c len_name (encode_len_value bytes) >|=? fun c -> (c, bytes)

    let consume_remove_gas del c =
      Raw_context.consume_gas c (Gas_limit_repr.write_bytes_cost Z.zero)
      >>?= fun c -> del c len_name

    let mem s i =
      consume_mem_gas (pack s i)
      >>?= fun c ->
      Raw_context.mem c data_name >|= fun res -> ok (Raw_context.project c, res)

    let get s i =
      consume_read_gas Raw_context.get (pack s i)
      >>=? fun c ->
      Raw_context.get c data_name
      >>=? fun b ->
      let key = Raw_context.absolute_key c data_name in
      Lwt.return (of_bytes ~key b >|? fun v -> (Raw_context.project c, v))

    let get_option s i =
      consume_mem_gas (pack s i)
      >>?= fun c ->
      let (s, _) = unpack c in
      Raw_context.mem (pack s i) data_name
      >>= fun exists ->
      if exists then get s i >|=? fun (s, v) -> (s, Some v)
      else return (C.project s, None)

    let set s i v =
      existing_size (pack s i)
      >>=? fun (prev_size, _) ->
      consume_write_gas Raw_context.set (pack s i) v
      >>=? fun (c, bytes) ->
      Raw_context.set c data_name bytes
      >|=? fun c ->
      let size_diff = Bytes.length bytes - prev_size in
      (Raw_context.project c, size_diff)

    let init s i v =
      consume_write_gas Raw_context.init (pack s i) v
      >>=? fun (c, bytes) ->
      Raw_context.init c data_name bytes
      >|=? fun c ->
      let size = Bytes.length bytes in
      (Raw_context.project c, size)

    let init_set s i v =
      let init_set c k v = Raw_context.init_set c k v >|= ok in
      existing_size (pack s i)
      >>=? fun (prev_size, existed) ->
      consume_write_gas init_set (pack s i) v
      >>=? fun (c, bytes) ->
      init_set c data_name bytes
      >|=? fun c ->
      let size_diff = Bytes.length bytes - prev_size in
      (Raw_context.project c, size_diff, existed)

    let remove s i =
      let remove c k = Raw_context.remove c k >|= ok in
      existing_size (pack s i)
      >>=? fun (prev_size, existed) ->
      consume_remove_gas remove (pack s i)
      >>=? fun c ->
      remove c data_name
      >|=? fun c -> (Raw_context.project c, prev_size, existed)

    let delete s i =
      existing_size (pack s i)
      >>=? fun (prev_size, _) ->
      consume_remove_gas Raw_context.delete (pack s i)
      >>=? fun c ->
      Raw_context.delete c data_name
      >|=? fun c -> (Raw_context.project c, prev_size)

    let set_option s i v =
      match v with None -> remove s i | Some v -> init_set s i v

    let set_free s i v =
      let c = pack s i in
      let bytes = to_bytes v in
      existing_size c
      >>=? fun (prev_size, _) ->
      Raw_context.set c len_name (encode_len_value bytes)
      >>=? fun c ->
      Raw_context.set c data_name bytes
      >>=? fun c ->
      let size_diff = Bytes.length bytes - prev_size in
      return (Raw_context.project c, size_diff)

    let () =
      let open Storage_description in
      let unpack = unpack I.args in
      register_value
        ~get:(fun c ->
          let (c, k) = unpack c in
          get_option c k >|=? fun (_, v) -> v)
        (register_named_subcontext Raw_context.description N.name)
        V.encoding
  end
end

module type WRAPPER = sig
  type t

  type key

  val wrap : t -> key

  val unwrap : key -> t option
end

module Wrap_indexed_data_storage
    (C : Indexed_data_storage)
    (K : WRAPPER with type key := C.key) =
struct
  type t = C.t

  type context = C.t

  type key = K.t

  type value = C.value

  let mem ctxt k = C.mem ctxt (K.wrap k)

  let get ctxt k = C.get ctxt (K.wrap k)

  let get_option ctxt k = C.get_option ctxt (K.wrap k)

  let set ctxt k v = C.set ctxt (K.wrap k) v

  let init ctxt k v = C.init ctxt (K.wrap k) v

  let init_set ctxt k v = C.init_set ctxt (K.wrap k) v

  let set_option ctxt k v = C.set_option ctxt (K.wrap k) v

  let delete ctxt k = C.delete ctxt (K.wrap k)

  let remove ctxt k = C.remove ctxt (K.wrap k)

  let clear ctxt = C.clear ctxt

  let fold ctxt ~init ~f =
    C.fold ctxt ~init ~f:(fun k v acc ->
        match K.unwrap k with None -> Lwt.return acc | Some k -> f k v acc)

  let bindings s =
    fold s ~init:[] ~f:(fun p v acc -> Lwt.return ((p, v) :: acc))

  let fold_keys s ~init ~f =
    C.fold_keys s ~init ~f:(fun k acc ->
        match K.unwrap k with None -> Lwt.return acc | Some k -> f k acc)

  let keys s = fold_keys s ~init:[] ~f:(fun p acc -> Lwt.return (p :: acc))
end
