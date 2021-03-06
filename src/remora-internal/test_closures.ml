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

open Core.Std
open Closures
module MR = Map_replicate_ast;;
module B = Basic_ast;;
module U = OUnit2;;
open Frame_notes
module E = Erased_ast;;

let unary_lam =
  Expr (Cls
          {code =
              Expr (Lam {MR.bindings = ["__ENV_1"; "x"];
                         MR.body = Expr (LetTup
                                            {MR.vars = [];
                                            MR.bound = Expr
                                               (Var "__ENV_1");
                                            MR.body = Expr
                                               (Vec {MR.dims = 1;
                                                     MR.elts =
                                                   [Expr (Int 3)]})})});
           env = Expr (Tup [])})


let mr_wrap e = MR.AExpr ((E.TUnknown, NotArg, NotApp), e)
let fn_wrap e = MR.AExpr ((E.TFun ([], E.TUnknown), NotArg, NotApp), e)

let escaping_function =
  mr_wrap (MR.LetTup {MR.vars = ["f"];
                      MR.bound = mr_wrap
      (MR.LetTup
         {MR.vars = ["x"];
          MR.bound = mr_wrap (MR.Tup [mr_wrap (MR.Int 5)]);
          MR.body = (fn_wrap
                       (MR.Lam {bindings = ["l"];
                                MR.body = mr_wrap
                           (MR.App {MR.fn = fn_wrap (MR.Var "+");
                                    MR.args = [mr_wrap (MR.Var "l");
                                               mr_wrap (MR.Var "x")]})}))});
                      MR.body = (mr_wrap
                                   (MR.App {MR.fn = fn_wrap (MR.Var "f");
                                            MR.args = [mr_wrap (MR.Int 6)]}))})
let converted =
  Expr
    (LetTup {MR.vars = ["f"];
             MR.bound =
        Expr
          (LetTup {MR.vars = ["x"];
                   MR.bound = Expr (Tup [Expr (Int 5)]);
                   MR.body =
              Expr (Cls {code =
                  Expr (Lam {MR.bindings = ["env";"l"];
                             MR.body = Expr
                      (LetTup
                         {MR.vars = ["x"];
                          MR.bound = Expr (Var "env");
                          MR.body = Expr (App {closure = Expr (Var "+");
                                               args = [Expr (Var "l");
                                                       Expr (Var "x")]})})});
                         env = Expr (Tup [Expr (Var "x")])})});
          MR.body = Expr (App {closure = Expr (Var "f");
                               args = [Expr (Int 6)]})})

let destr_dsum =
  mr_wrap
    (MR.LetTup {MR.vars = ["l";"n"];
                MR.bound = mr_wrap
        (MR.App {MR.fn = fn_wrap (MR.Var "iota");
                 MR.args = [mr_wrap
                               (MR.Vec {MR.dims = 1;
                                        MR.elts = [mr_wrap (MR.Int 5)]})]});
             MR.body = mr_wrap
        (MR.Tup [mr_wrap (MR.Var "l");
                 mr_wrap (MR.Map {MR.frame = mr_wrap (MR.Var "l");
                                  MR.fn = fn_wrap
                     (MR.Lam {MR.bindings = ["x"];
                              MR.body = mr_wrap
                         (MR.App {MR.fn = fn_wrap (MR.Var "+");
                                  MR.args = []})});
                                  MR.args = [];
                                  MR.shp = mr_wrap (MR.Var "l")})])})

let vec_scal_add =
  fn_wrap
    (MR.Lam {MR.bindings = ["l"];
             MR.body = fn_wrap
        (MR.Lam {MR.bindings = ["x";"y"];
                 MR.body = mr_wrap
            (MR.Map {MR.frame = mr_wrap (MR.Var "l");
                     MR.fn = fn_wrap (MR.Var "+");
                     MR.args =
                [mr_wrap (MR.Var "x");
                 mr_wrap (MR.Rep {MR.arg = mr_wrap (MR.Var "y");
                                  MR.old_frame = mr_wrap
                     (MR.Vec {MR.dims = 0; MR.elts = []});
                                  MR.new_frame = mr_wrap
                     (MR.Vec {MR.dims = 1;
                              MR.elts = [mr_wrap (MR.Var "l")]})})];
                     MR.shp = mr_wrap (MR.Var "l")})})})

let rec subst (s : (var, expr) List.Assoc.t) ((Expr e) as exp: expr) : expr =
  match e with
  | LetTup {MR.vars = vars; MR.bound = bound; MR.body = body} ->
    (* Shadow every substitution var that appears in vars. *)
    let new_s =
      List.fold_right ~init:s ~f:(fun l r -> List.Assoc.remove r l) vars in
    Expr (LetTup {MR.vars = vars;
                  MR.bound = subst s bound;
                  MR.body = subst new_s body})
  | Lam {MR.bindings = vars; MR.body = body} ->
    let new_s =
      List.fold_right ~init:s ~f:(fun l r -> List.Assoc.remove r l) vars in
    Expr (Lam {MR.bindings = vars;
               MR.body = subst new_s body})
  | Var v -> List.Assoc.find s v |> (Option.value ~default:exp)
  | _ -> Expr (map_expr_form ~f:(subst s) e)

let rec alpha_eqv
    (Expr e1: expr) (Expr e2: expr) : bool =
  match (e1, e2) with
  | (App {closure = c1; args = a1}, App {closure = c2; args = a2}) ->
    (alpha_eqv c1 c2) && (List.length a1 = List.length a2) &&
      (List.for_all2_exn ~f:alpha_eqv a1 a2)
  | (Vec {MR.dims = d1; MR.elts = l1}, Vec {MR.dims = d2; MR.elts = l2}) ->
    (d1 = d2) && (List.length l1 = List.length l2) &&
      (List.for_all2_exn ~f:alpha_eqv l1 l2)
  | (Map {MR.frame = fr1; MR.fn = fn1; MR.args = a1; MR.shp = s1},
     Map {MR.frame = fr2; MR.fn = fn2; MR.args = a2; MR.shp = s2}) ->
    (alpha_eqv fr1 fr2) && (alpha_eqv fn1 fn2) &&
      (List.length a1 = List.length a2) &&
      (List.for_all2_exn ~f:alpha_eqv a1 a2) &&
      (alpha_eqv s1 s2)
  | (Rep {MR.arg = a1; MR.old_frame = o1; MR.new_frame = n1},
     Rep {MR.arg = a2; MR.old_frame = o2; MR.new_frame = n2}) ->
    (alpha_eqv a1 a2) && (alpha_eqv o1 o2) && (alpha_eqv n1 n2)
  | (Tup l1, Tup l2) ->
    (* Tuples must have the same arity. *)
    (List.length l1 = List.length l2) &&
      (* Corresponding elements must be alpha-equivalent. *)
      (List.for_all2_exn ~f:alpha_eqv l1 l2)
  | (LetTup {MR.vars = v1; MR.bound = bn1; MR.body = bd1},
     LetTup {MR.vars = v2; MR.bound = bn2; MR.body = bd2}) ->
    (* Both lets must bind the same number of variables. *)
    (List.length v1 = List.length v2) &&
      (* Both bound terms must be alpha equivalent *)
      (alpha_eqv bn1 bn2) &&
      (* Changing the let-bound vars to fresh ones must give alpha-equivalent
         bodies. *)
      (let fresh_vars = List.map ~f:(fun _ -> Expr (Var (B.gensym "__="))) v1 in
       (alpha_eqv
          (subst (List.map2_exn ~f:Tuple2.create v1 fresh_vars) bd1)
          (subst (List.map2_exn ~f:Tuple2.create v2 fresh_vars) bd2)))
  | (Fld {MR.field = n1; MR.tuple = t1}, Fld {MR.field = n2; MR.tuple = t2}) ->
    n1 = n2 && (alpha_eqv t1 t2)
  | (Let {MR.var = v1; MR.bound = bn1; MR.body = bd1},
     Let {MR.var = v2; MR.bound = bn2; MR.body = bd2}) ->
    (alpha_eqv bn1 bn2) &&
      let fresh_var = Expr (Var (B.gensym "__=")) in
      (alpha_eqv (subst [v1, fresh_var] bd1) (subst [v2, fresh_var] bd2))
  | (Cls {code = c1; env = n1}, Cls {code = c2; env = n2}) ->
    (alpha_eqv c1 c2) && (alpha_eqv n1 n2)
  | (Lam {MR.bindings = vars1; MR.body = body1},
     Lam {MR.bindings = vars2; MR.body = body2}) ->
    (* Both lambdas must bind the same number of variables. *)
    (List.length vars1 = List.length vars2) &&
      (* Changing those vars to fresh ones must give alpha-equivalent bodies. *)
      (let fresh_vars = List.map
         ~f:(fun _ -> Expr (Var (B.gensym "__=")))
         vars1 in
       alpha_eqv
         (subst (List.map2_exn ~f:Tuple2.create vars1 fresh_vars) body1)
         (subst (List.map2_exn ~f:Tuple2.create vars2 fresh_vars) body2))
  | (Var v1, Var v2) -> v1 = v2
  | (Int v1, Int v2) -> v1 = v2
  | (Float v1, Float v2) -> v1 = v2
  | (Bool v1, Bool v2) -> v1 = v2
  | ((App _ | Vec _ | Map _ | Rep _ | Tup _ | LetTup _ | Fld _ | Let _ |
      Cls _ | Lam _ | Var _ | Int _ | Float _ | Bool _), _) -> false

module Test_closure_conversion : sig
  val tests : U.test
end = struct
  let test_1 _ =
    U.assert_bool "Non-equivalent result from closure conversion!"
      (alpha_eqv converted
         (escaping_function |> expr_of_maprep ["+"] |> annot_expr_drop))
  let tests =
    let open OUnit2 in
    "translate from Map/Rep AST into AST with explicit closures">:::
      ["lambda escaping with a let-bound var">:: test_1]
end

  (* Make sure we can undo hoisting by substituting defn bodies back in. *)
let expr_unhoist ((expr, defns): ('a ann_expr, 'a) Defn_writer.t) : expr =
  subst
    (List.map ~f:(fun (ADefn (name, value)) ->
      (name, annot_expr_drop value)) defns)
    (annot_expr_drop expr)
let hoist_unhoist (e: 'a ann_expr) : bool =
  (e |> expr_hoist_lambdas |> expr_unhoist) = (e |> annot_expr_drop)

  (* Make sure we generate code with no inline lambdas. *)
let rec lambda_free (AExpr (_, e): 'a ann_expr) : bool =
  match e with
  | App {closure = c; args = a} ->
    lambda_free c && List.for_all ~f:lambda_free a
  | Vec {MR.dims = _; MR.elts = elts} -> List.for_all ~f:lambda_free elts
  | Map {MR.frame = fr; MR.fn = fn; MR.args = a; MR.shp} ->
    List.for_all ~f:lambda_free (fr :: fn :: shp :: a)
  | Rep {MR.arg = a; MR.old_frame = o; MR.new_frame = n} ->
    lambda_free a && lambda_free o && lambda_free n
  | Tup elts -> List.for_all ~f:lambda_free elts
  | LetTup {MR.vars = _; MR.bound = bn; MR.body = bd} ->
    lambda_free bn && lambda_free bd
  | Fld {MR.field = _; MR.tuple = tup} -> lambda_free tup
  | Let {MR.var = _; MR.bound = bn; MR.body = bd} ->
    lambda_free bn && lambda_free bd
  | Lam _ -> false
  | Cls {code = c; env = n} -> lambda_free c && lambda_free n
  | Var _ | Int _ | Float _ | Bool _ -> true
  (* It's ok to define a function, but make sure no lambdas appear in the
     function body. *)
let defn_lambda_free (ADefn (_, (AExpr (_, e) as expr)): 'a ann_defn) : bool =
  match e with
  | Lam {MR.bindings = _; MR.body = b} -> lambda_free b
  | _ -> lambda_free expr
let writer_lambda_free ((expr, defns): ('a ann_expr, 'a) Defn_writer.t)
    : bool =
  List.for_all ~f:defn_lambda_free defns && lambda_free expr

module Test_lambda_hoisting : sig
  val tests : U.test
end = struct
  let test_hoist_unhoist e =
    e |> hoist_unhoist |> U.assert_bool "Hoist-unhoist match check"
  let test_lambda_free expr =
    expr |> expr_hoist_lambdas |> writer_lambda_free |>
        U.assert_bool "Generate lambda-free code"

  (* TODO: More test cases (code samples) *)
  let test_1 _ =
    escaping_function |> expr_of_maprep ["+"] |> test_hoist_unhoist
  let test_2 _ =
    escaping_function |> expr_of_maprep ["+"] |> test_lambda_free
  let test_3 _ =
    destr_dsum |> expr_of_maprep ["+"; "iota"] |> test_hoist_unhoist
  let test_4 _ =
    destr_dsum |> expr_of_maprep ["+"; "iota"] |> test_lambda_free
  (* Unhoisting does not work with lambda-producing lambdas (and making it
     work would risk infinitely unrolling a recursive call), so eliding this
     test. *)
  (* let test_5 _ = *)
  (*   vec_scal_add |> expr_of_maprep ["+"] |> test_hoist_unhoist *)
  let test_6 _ =
    vec_scal_add |> expr_of_maprep ["+"] |> test_lambda_free
  let tests =
    let open OUnit2 in
    "hoist lambdas out to top-level definitions">:::
      ["lambda escaping with a let-bound var">:: test_1;
       "lambda escaping with a let-bound var">:: test_2;
       "destructing a dependent sum">:: test_3;
       "destructing a dependent sum">:: test_4;
       "adding vector and scalar">:: test_6]
end

module UnitTests : sig
  val tests : U.test
end = struct
  let tests =
    let open OUnit2 in
    "Explicit-closure AST tests">:::
      [Test_closure_conversion.tests;
       Test_lambda_hoisting.tests]
end
