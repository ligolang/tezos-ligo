(* This file is part of Lwt, released under the MIT license. See LICENSE.md for
   details, or visit https://github.com/ocsigen/lwt/blob/master/LICENSE.md. *)

(** List helpers *)

(** Note: this module use the same naming convention as
    {!Lwt_stream}. *)

(** {2 List iterators} *)

val map_s : ('a -> 'b Lwt.t) -> 'a list -> 'b list Lwt.t

val mapi_s : (int -> 'a -> 'b Lwt.t) -> 'a list -> 'b list Lwt.t

val rev_map_s : ('a -> 'b Lwt.t) -> 'a list -> 'b list Lwt.t

val fold_left_s : ('a -> 'b -> 'a Lwt.t) -> 'a -> 'b list -> 'a Lwt.t

val fold_right_s : ('a -> 'b -> 'b Lwt.t) -> 'a list -> 'b -> 'b Lwt.t

(** {2 List scanning} *)

val for_all_s : ('a -> bool Lwt.t) -> 'a list -> bool Lwt.t

val exists_s : ('a -> bool Lwt.t) -> 'a list -> bool Lwt.t

(** {2 List searching} *)

val find_s : ('a -> bool Lwt.t) -> 'a list -> 'a Lwt.t

val filter_s : ('a -> bool Lwt.t) -> 'a list -> 'a list Lwt.t

val filter_map_s : ('a -> 'b option Lwt.t) -> 'a list -> 'b list Lwt.t

val partition_s : ('a -> bool Lwt.t) -> 'a list -> ('a list * 'a list) Lwt.t
