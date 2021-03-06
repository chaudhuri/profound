(*
 * Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>
 * Copyright (C) 2013  Inria (Institut National de Recherche
 *                     en Informatique et en Automatique)
 * See LICENSE for licensing details.
 *)

open Batteries

type term =
  | Idx of int
  | App of Idt.t * term list

val equals : Idt.t

type sign = ASSERT | REFUTE

type fcx

type form = private
  | Atom  of sign * Idt.t * term list
  | Conn  of conn * form list
  | Subst of fcx * form
  | Mark  of mkind * form

and frame = {
  conn : conn ;
  left : form list;
  right : form list;
}

and quant = All | Ex

and conn =
  | Tens | Plus | Par | With | Lto
  | Qu of quant * Idt.t
  | Bang | Qm

and mkind = ARG | SRC | SNK

type sub = Shift of int | Dot of sub * term

val sub_idx : sub -> int -> term
val sub_term : sub -> term -> term
val sub_form : sub -> form -> form
val sub_fcx : sub -> fcx -> fcx * sub
val seq : sub -> sub -> sub

val unsubst : form -> fcx * form
val unframe : frame -> form -> form

module Fcx     : sig
  val empty    : fcx
  val cons     : frame -> fcx   -> fcx
  val snoc     : fcx   -> frame -> fcx
  val append   : fcx   -> fcx   -> fcx
  val front    : fcx   -> (frame * fcx) option
  val rear     : fcx   -> (fcx * frame) option
  val to_list  : fcx   -> frame list
  val size     : fcx   -> int
  val is_empty : fcx   -> bool
end

val focus : form -> form

val head1 : form -> form

type test = dep:int -> term -> bool
val test_term : test -> term        -> bool
val test_form : test -> form        -> bool
val test_fcx  : test -> fcx -> form -> bool

val fcx_vars : fcx -> Idt.t list

val atom  : sign -> Idt.t -> term list -> form
val conn  : conn -> form list -> form
val subst : fcx -> form -> form

val _Tens : form  -> form -> form
val _One  : form
val _Plus : form  -> form -> form
val _Zero : form
val _Par  : form  -> form -> form
val _Bot  : form
val _With : form  -> form -> form
val _Top  : form
val _Lto  : form  -> form -> form
val _All  : Idt.t -> form -> form
val _Ex   : Idt.t -> form -> form
val _Bang : form  -> form
val _Qm   : form  -> form

exception Cannot_mark
val mark   : mkind -> form -> form
val has_mark : ?m:mkind -> form -> bool
val unmark : form -> form

val aeq_forms : form -> form -> bool

val var_occurs : Idt.t -> form -> bool

val negate : form -> form
