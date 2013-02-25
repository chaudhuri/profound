(******************************************************************************)
(* Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>                     *)
(* Copyright (C) 2013  INRIA                                                  *)
(* See LICENSE for licensing details.                                         *)
(******************************************************************************)

{
  module P = Syntax_prs

  let newline lb =
    Lexing.(
      lb.lex_curr_p <- { lb.lex_curr_p with
        pos_bol = lb.lex_curr_p.pos_cnum ;
        pos_lnum = lb.lex_curr_p.pos_lnum + 1 ;
      }
    )
}

let ident_initial = ['A'-'Z' 'a'-'z']
let ident_body    = ident_initial | ['0'-'9' '_']
let ident         = ident_initial ident_body*

let space         = ' ' | '\t'
let newline       = '\r''\n' | '\n'

rule token = parse
| '%'              { line_comment lexbuf }

| space            { token lexbuf }
| newline          { newline lexbuf ; token lexbuf }

| ident            { P.IDENT (Idt.intern (Lexing.lexeme lexbuf)) }

| "~" | "\\lnot"   { P.LNOT }

| '*' | "\\tensor" { P.TENSOR }
| '1' | "\\one"    { P.ONE }
| '+' | "\\plus"   { P.PLUS }
| '0' | "\\zero"   { P.ZERO }

| '|' | "\\par"    { P.PAR }
| "#F" | "#f"
| "\\bot"          { P.BOT }
| "&" | "\\with"   { P.WITH }
| "#T" | "#t"
| "\\top"          { P.TOP }

| '!'              { P.BANG }
| '?'              { P.QM }

| "\\A"            { P.FORALL }
| "\\E"            { P.EXISTS }

| ','              { P.COMMA }
| '.'              { P.DOT }
| '('              { P.LPAREN }
| ')'              { P.RPAREN }

| eof              { P.EOS }
| _                {
  Printf.eprintf "Invalid character %s\n%!" (String.escaped (Lexing.lexeme lexbuf)) ;
  raise P.Error
}

and line_comment = parse
| newline          { newline lexbuf ; token lexbuf }
| eof              { P.EOS }
| _                { line_comment lexbuf }