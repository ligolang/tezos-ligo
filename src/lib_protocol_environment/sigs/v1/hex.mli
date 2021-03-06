(*
 * Copyright (c) 2015 Trevor Summers Smith <trevorsummerssmith@gmail.com>
 * Copyright (c) 2014 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

(** Hexadecimal encoding.

    [Hex] defines hexadecimal encodings for {{!char}characters},
    {{!string}strings} and {{!cstruct}Cstruct.t} buffers. *)

(** The type var hexadecimal values. *)
type t = [`Hex of string]

(** {1:char Characters} *)

(** [of_char c] is the the hexadecimal encoding of the character
    [c]. *)
val of_char : char -> char * char

(** [to_char x y] is the character correspondong to the [xy]
    hexadecimal encoding. *)
val to_char : char -> char -> char

(** {1:string Strings} *)

(** [of_string s] is the hexadecimal representation of the binary
    string [s]. If [ignore] is set, skip the characters in the list
    when converting. Eg [of_string ~ignore:[' '] "a f"]. The default
    value of [ignore] is [[]]). *)
val of_string : ?ignore:char list -> string -> t

(** [to_string t] is the binary string [s] such that [of_string s] is
    [t]. *)
val to_string : t -> string

(** {1:byte Bytes} *)

(** [of_bytes s] is the hexadecimal representation of the binary
    string [s]. If [ignore] is set, skip the characters in the list
    when converting. Eg [of_bytes ~ignore:[' '] "a f"]. The default
    value of [ignore] is [[]]). *)
val of_bytes : ?ignore:char list -> bytes -> t

(** [to_bytes t] is the binary string [s] such that [of_bytes s] is
    [t]. *)
val to_bytes : t -> bytes

(** {1:cstruct Cstruct} *)

(** [of_cstruct buf] is the hexadecimal representation of the buffer
    [buf]. *)

(* val of_cstruct : ?ignore:char list -> Cstruct.t -> t *)

(** [to_cstruct t] is the buffer [b] such that [of_cstruct b] is
    [t]. *)

(* val to_cstruct : t -> Cstruct.t *)

(** {1:Bigstring Bigstring} *)

(** [of_bigstring buf] is the hexadecimal representation of the buffer
    [buf]. *)

(* val of_bigstring : ?ignore:char list -> Cstruct.buffer -> t *)

(** [to_bigstring t] is the buffer [b] such that [of_bigstring b] is
    [t]. *)

(* val to_bigstring : t -> Cstruct.buffer *)

(** {1 Debugging} *)

(** [hexdump h] dumps the hex encoding to stdout in the following format:

    {v
       00000000: 6865 6c6c 6f20 776f 726c 6420 6865 6c6c  hello world hell
       00000010: 6f20 776f 726c 640a                      o world.
    v}

    This is the same format as emacs hexl-mode, and is a very similar
    format to hexdump -C. '\t' and '\n' are printed as '.'.in the char
    column.

    [print_row_numbers] and [print_chars] both default to
    [true]. Setting either to [false] does not print the column.
 *)

(* val hexdump : ?print_row_numbers:bool -> ?print_chars:bool -> t -> unit *)

(** Same as [hexdump] except returns a string. *)

(* val hexdump_s : ?print_row_numbers:bool -> ?print_chars:bool -> t -> string *)

(** {1 Pretty printing} *)

(** [pp fmt t] will output a human-readable hex representation of [t]
    to the formatter [fmt]. *)

(* val pp : Format.formatter -> t -> unit
 *   [@@ocaml.toplevel_printer] *)

(** [show t] will return a human-readable hex representation of [t] as
    a string. *)
val show : t -> string
