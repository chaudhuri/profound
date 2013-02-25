(******************************************************************************)
(* Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>                     *)
(* Copyright (C) 2013  INRIA                                                  *)
(* See LICENSE for licensing details.                                         *)
(******************************************************************************)

open Batteries

open Syntax
open Result

let rec index_term cx = function
  | Idx n -> Idx n
  | App (c, []) ->
      begin match index_find cx c with
      | None -> App (c, [])
      | Some n -> Idx n
      end
  | App (f, ts) ->
      App (f, List.map (index_term cx) ts)

and index_find ?(dep = 0) cx c =
  begin match cx with
  | [] -> None
  | x :: _ when c = x -> Some dep
  | _ :: cx -> index_find ~dep:(dep + 1) cx c
  end

let rec index_form cx f =
  begin match f with
  | Syntax.Atom (s, p, ts) ->
      atom s p (List.map (index_term cx) ts)
  | Conn (Qu (_, x) as q, fs) ->
      let fs = List.map (index_form (x :: cx)) fs in
      conn q fs
  | Conn (c, fs) ->
      conn c (List.map (index_form cx) fs)
  | Subst _ -> assert false
  end


let thing_of_string prs ind cx str =
  let lb = Lexing.from_string str in
  try
    let t = prs Syntax_lex.token lb in
    Ok (ind cx t)
  with Syntax_prs.Error -> Bad "reading term"

let form_of_string cx str = thing_of_string Syntax_prs.one_form index_form cx str
let term_of_string cx str = thing_of_string Syntax_prs.one_term index_term cx str

let parse_file f =
  try
    let ch = open_in_bin f in
    let lb = Lexing.from_channel ch in
    let f = Syntax_prs.one_form Syntax_lex.token lb in
    close_in ch ;
    Ok (index_form [] f)
  with 
  | Sys_error _ -> Bad (Printf.sprintf "could not read %S" f)
  | Syntax_prs.Error -> Bad "parsing error"

let newer_than f1 f2 =
  Unix.((lstat f1).st_mtime > (lstat f2).st_mtime)

exception Save_invalid

let save_name fin =
  let saven =
    if Filename.check_suffix fin ".p" then
      Filename.chop_extension fin
    else fin in
  saven ^ ".pc"

let load_file fin =
  let magic = Digest.file fin in
  Result.Monad.(
    parse_file fin >>= fun f ->
    let saven = save_name fin in
    let hi = 
      if Sys.file_exists saven && newer_than saven fin then begin
        try
          let mch = open_in_bin saven in
          if (Marshal.from_channel mch <> Version.str
              || Marshal.from_channel mch <> Version.built
              || Marshal.from_channel mch <> magic)
          then begin
            Log.(log DEBUG "Magic numbers in %S do not match" saven) ;
            raise Save_invalid
          end ;
          let hi = Marshal.from_channel mch in
          close_in mch ;
          (* if not (Action.is_history_of hi f) then begin *)
          (*   Log.(log DEBUG "History in %S does not match %S" saven fin) ; *)
          (*   raise Save_invalid *)
          (* end ; *)
          Log.(log INFO "Saved state of %S loaded from %S" fin saven) ;
          hi
        with Save_invalid ->
          Log.(log DEBUG "Could not reload state of %S" fin) ;
          Log.(log DEBUG "   from %S" saven) ;
          Action.init f
      end else begin
        Log.(log DEBUG "Save file %S does not exist or is older than %S" saven fin) ;
        Action.init f
      end
    in
    return hi
  )

let save_file fin hi =
  let saven = save_name fin in
  let mch = open_out_bin saven in
  Marshal.to_channel mch Version.str [] ;
  Marshal.to_channel mch Version.built [] ;
  Marshal.to_channel mch (Digest.file fin) [] ;
  Marshal.to_channel mch hi [] ;
  close_out mch ;
  Log.(log INFO "State of %S saved to %S" fin saven) ;