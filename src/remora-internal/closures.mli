(******************************************************************************)
(* Copyright (c) 2015, NVIDIA CORPORATION. All rights reserved.               *)
(*                                                                            *)
(* Redistribution and use in source and binary forms, with or without         *)
(* modification, are permitted provided that the following conditions         *)
(* are met:                                                                   *)
(*  * Redistributions of source code must retain the above copyright          *)
(*    notice, this list of conditions and the following disclaimer.           *)
(*  * Redistributions in binary form must reproduce the above copyright       *)
(*    notice, this list of conditions and the following disclaimer in the     *)
(*    documentation and/or other materials provided with the distribution.    *)
(*  * Neither the name of NVIDIA CORPORATION nor the names of its             *)
(*    contributors may be used to endorse or promote products derived         *)
(*    from this software without specific prior written permission.           *)
(*                                                                            *)
(* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY       *)
(* EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE          *)
(* IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR         *)
(* PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR          *)
(* CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,      *)
(* EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,        *)
(* PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR         *)
(* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY        *)
(* OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT               *)
(* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE      *)
(* OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.       *)
(******************************************************************************)

module MR = Map_replicate_ast;;
module B = Basic_ast;;
module E = Erased_ast;;
open Frame_notes

type var = Basic_ast.var with sexp

type 'a cl_app_t = {closure: 'a; args: 'a list;} with sexp
type 'a closure_t = {code: 'a; env: 'a} with sexp

type 'a expr_form =
| App of 'a cl_app_t
| Vec of 'a MR.vec_t
| Map of 'a MR.map_t
| Rep of 'a MR.rep_t
| Tup of 'a MR.tup_t
| LetTup of 'a MR.lettup_t
| Fld of 'a MR.fld_t
| Let of 'a MR.let_t
| Cls of 'a closure_t
| Lam of 'a MR.lam_t
| Var of var
| Int of int
| Float of float
| Bool of bool
with sexp

val map_expr_form : f:('a -> 'b) -> 'a expr_form -> 'b expr_form

type expr = Expr of expr expr_form with sexp
type defn = Defn of var * expr with sexp
type prog = Prog of defn list * expr with sexp

type 'annot ann_expr = AExpr of 'annot * ('annot ann_expr) expr_form with sexp
type 'annot ann_defn = ADefn of var * 'annot ann_expr with sexp
type 'annot ann_prog =
  AProg of 'annot * 'annot ann_defn list * 'annot ann_expr with sexp

val expr_of_maprep :
  var list
  -> (E.typ * arg_frame * app_frame) MR.ann_expr
  -> (E.typ * arg_frame * app_frame) ann_expr

val annot_expr_drop : 'a ann_expr -> expr
val annot_defn_drop : 'a ann_defn -> defn
val annot_prog_drop : 'a ann_prog -> prog

val annot_expr_map : f:('a -> 'b) -> 'a ann_expr -> 'b ann_expr
val annot_defn_map : f:('a -> 'b) -> 'a ann_defn -> 'b ann_defn
val annot_prog_map : f:('a -> 'b) -> 'a ann_prog -> 'b ann_prog

module Defn_writer : sig
  type ('v, 'a) t = 'v * 'a ann_defn list
  val (>>=) : ('v, 'a) t -> ('v -> ('w, 'a) t) -> ('w, 'a) t
  val (>>|) : ('v, 'a) t -> ('v -> 'w) -> ('w, 'a) t
  val (>>) : ('v, 'a) t -> ('w, 'a) t -> ('w, 'a) t
  val bind : ('v, 'a) t -> ('v -> ('w, 'a) t) -> ('w, 'a) t
  val return : 'v -> ('v, 'a) t
  val map : ('v, 'a) t -> f:('v -> 'w) -> ('w, 'a) t
  val join : (('v, 'a) t, 'a) t -> ('v, 'a) t
  val all : ('v, 'a) t list -> ('v list, 'a) t
  val tell : 'a ann_defn list -> (unit, 'a) t
end

val expr_hoist_lambdas : 'a ann_expr -> ('a ann_expr, 'a) Defn_writer.t

module Passes : sig
  val prog : (E.typ * arg_frame * app_frame) MR.ann_prog
    -> (E.typ * arg_frame * app_frame) ann_prog
  val defn : (E.typ * arg_frame * app_frame) MR.ann_defn
    -> (E.typ * arg_frame * app_frame) ann_defn
  val expr : (E.typ * arg_frame * app_frame) MR.ann_expr
    -> (E.typ * arg_frame * app_frame) ann_expr

  val prog_all : B.rem_prog -> (E.typ * arg_frame * app_frame) ann_prog option
  val defn_all : B.rem_defn -> (E.typ * arg_frame * app_frame) ann_defn option
  val expr_all : B.rem_expr -> (E.typ * arg_frame * app_frame) ann_expr option
  val elt_all : B.rem_elt -> (E.typ * arg_frame * app_frame) ann_expr option
end
