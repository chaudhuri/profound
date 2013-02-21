(******************************************************************************)
(* Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>                     *)
(* Copyright (C) 2013  INRIA                                                  *)
(* See LICENSE for licensing details.                                         *)
(******************************************************************************)

open Batteries

open Syntax

let wash_file = "tex/wash_form1.png"

let form_to_pixbuf cur his =
  Syntax_tex.wash_forms cur (List.map fst his) ;
  try
    let img = GdkPixbuf.from_file wash_file in
    Some img
  with _ -> None

type mark_mode =
  | NO_MARKS
  | HAS_SRC
  | HAS_BOTH

type gui = {
  mutable mmode : mark_mode ;
  mutable cur : form ;
  mutable hist : (form * mark_mode) list ;
  mutable win : GWindow.window ;
  mutable img : GMisc.image ;
  mutable stxt : GMisc.statusbar_context ;
}

let gui : gui = {
  mmode = NO_MARKS ;
  cur = atom ASSERT (Idt.intern "a") [] ;
  hist = [] ;
  win = Obj.magic 0 ;
  img = Obj.magic 0 ;
  stxt = Obj.magic 0 ;
}

let flash fmt =
  Printf.ksprintf (gui.stxt#flash ~delay:1500) fmt

let redisplay () =
  gui.stxt#pop () ;
  begin match form_to_pixbuf gui.cur gui.hist with
  | None -> ()
  | Some pix ->
      gui.img#set_pixbuf pix ;
      let _ = gui.stxt#push begin
        match gui.mmode with
        | NO_MARKS -> "Select a subformula with ENTER to mark a source"
        | HAS_SRC -> "Select a subformula to mark a sink"
        | HAS_BOTH -> "INTERNAL ERROR!"
      end in
      ()
  end

let rewrite_cur ?(log = false) ?mmode f =
  if log then gui.hist <- (gui.cur, gui.mmode) :: gui.hist ;
  gui.cur <- f ;
  (match mmode with Some mmode -> gui.mmode <- mmode | None -> ()) ;
  redisplay ()

let mod_to_string m =
  begin match m with
  | `BUTTON1 -> "BUTTON1"
  | `BUTTON2 -> "BUTTON2"
  | `BUTTON3 -> "BUTTON3"
  | `BUTTON4 -> "BUTTON4"
  | `BUTTON5 -> "BUTTON5"
  | `CONTROL -> "CONTROL"
  | `HYPER -> "HYPER"
  | `LOCK -> "LOCK"
  | `META -> "META"
  | `MOD1 -> "MOD1"
  | `MOD2 -> "MOD2"
  | `MOD3 -> "MOD3"
  | `MOD4 -> "MOD4"
  | `MOD5 -> "MOD5"
  | `RELEASE -> "RELEASE"
  | `SHIFT -> "SHIFT"
  | `SUPER -> "SUPER"
  end

let log_mods mods =
  Log.(log DEBUG "Mods: [%s]"
         (String.concat "," (List.map mod_to_string mods)))

let kmap = ref Map.empty

let rec y_or_n handle_y key =
  let open GdkKeysyms in
  let ksym = GdkEvent.Key.keyval key in
  if ksym = _y || ksym = _Y then begin
    handle_y () ;
    gui.stxt#pop () ;
    true
  end else if ksym = _n || ksym = _N then begin
    ignore (gui.win#event#connect#key_press ~callback:handle_key) ;
    gui.stxt#pop () ;
    true
  end else begin
    false
  end

and handle_key key =
  begin 
    let ksym = GdkEvent.Key.keyval key in
    Log.(log DEBUG "handle_key/ksym: 0x%04x" ksym) ;
    let mods = GdkEvent.Key.state key in
    log_mods mods ;
    Map.mem ksym !kmap && (Map.find ksym !kmap) mods
  end

let key_down _ =
  Traversal.(
    try
      rewrite_cur (go_down 0 gui.cur)
    with
    | Traversal At_leaf ->
        flash "Cannot descend further"
    | Traversal _ -> ()) ;
  true

let key_up mods =
  Traversal.(
  let go_fn = if List.mem `SHIFT mods then go_top else go_up in
  try rewrite_cur (go_fn gui.cur) with
  | Traversal At_top ->
      flash "Cannot ascend further"
  | Traversal _ -> ()) ;
  true

let key_left _ =
  Traversal.(try begin
    rewrite_cur (go_left gui.cur)
  end with Traversal _ -> ()) ;
  true

let key_right _ =
  Traversal.(try begin
    rewrite_cur (go_right gui.cur)
  end with Traversal _ -> ()) ;
  true

let key_delete _ =
  Traversal.(
    let (fcx, f) = unsubst gui.cur in
    if Rules.has_lnk f then begin
      flash "Cannot delete a subformula with a mark"
    end else begin
      match f with
      | Conn (Qm, _) ->
          rewrite_cur ~log:true (subst fcx (conn Bot []))
      | _ -> 
          begin match Deque.rear fcx with
          | Some (fcx, ({fconn = PLUS ; _} as fr)) ->
              let f = conn Plus (fr.fleft @ fr.fright) in
              rewrite_cur ~log:true (subst fcx f)
          | _ ->
              flash "No rules allow deletion of this subformula"
          end
    end) ;
  true

exception Silently_fail

let key_enter mods =
  Traversal.(try begin
    if List.mem `SHIFT mods then begin
      let (fcx, f) = unsubst gui.cur in
      match f with
      | Conn (Qm, _) ->
          begin
            if Rules.has_lnk f then
              flash "Cannot contract a formula with a mark"
            else
              rewrite_cur ~log:true (subst fcx (conn Par [f ; f]))
          end
      | Conn (Ex x, [fb]) -> begin
          let dwin = GWindow.dialog
            ~parent:gui.win
            ~title:"Witness input"
            ~modal:true
            ~position:`CENTER_ON_PARENT () in
          dwin#vbox#misc#set_size_request ~width:640 () ;
          dwin#add_button_stock `OK `OK ;
          dwin#add_button_stock `CANCEL `CANCEL ;
          let lab = GMisc.label ~xalign:0.
            ~packing:(dwin#vbox#pack ~expand:false) () in
          let msg = "Enter a witness term to replace " ^ (Idt.rep x) ^ ":\n" in
          lab#set_text msg ;
          let ebox = GEdit.entry ~text:""
            ~width:80
            ~packing:(dwin#vbox#pack ~expand:false) () in
          let handler key = begin
            let open GdkKeysyms in
            let ks = GdkEvent.Key.keyval key in
            if ks = _Return then (dwin#response `OK ; true)
            else if ks = _Escape then (dwin#response `CANCEL ; true)
            else false
          end in
          ignore (dwin#event#connect#key_press ~callback:handler) ;
          let resp = dwin#run () in
          let txt = String.trim ebox#text in
          dwin#destroy () ;
          begin match resp with
          | `OK ->
              begin match Syntax_prs.parse_term (fcx_vars fcx) txt with
              | Prs.Read t ->
                  let ss = Dot (Shift 0, t) in
                  let fb = sub_form ss fb in
                  let f = subst fcx fb in
                  rewrite_cur ~log:true f
              | _ ->
                  flash "Could not parse: %S" txt ;
                  ()
              end
          | _ -> flash "Cancelled witness"
          end
      end
      | _ -> ()
    end else begin
      let (fcx, f) = unsubst gui.cur in
      match f with
      | Conn (Mark SRC, [_]) when gui.mmode = HAS_SRC ->
          Log.(log DEBUG "Hit enter on a source-marked subformula") ;
          rewrite_cur ~mmode:NO_MARKS (subst fcx (Rules.unlnk f)) ;
          flash "Source mark removed"
      | _ ->
          let (mrk, mmode) = match gui.mmode with
          | NO_MARKS -> (SRC, HAS_SRC)
          | HAS_SRC -> (SNK, HAS_BOTH)
          | HAS_BOTH ->
              Log.(log ERROR "Apparently both marks exist -- this is impossible!") ;
              raise Silently_fail
          in
          try (
            let f0 = Rules.make_lnk mrk gui.cur in
            begin match mmode with
            | HAS_BOTH ->
                rewrite_cur ~log:true ~mmode:NO_MARKS (Rules.resolve_mpar f0)
            | _ ->
                rewrite_cur ~mmode f0
            end
          ) with Rules.Rule_failure reason  ->
            flash "Cannot mark here: %s" begin
              match reason with
              | Rules.Promotion -> "invalid promotion"
              | Rules.Not_par ->
                  "not linked to source via an ancestral par"
              | Rules.Already_marked ->
                  "a strict subformula already has a mark"
              | Rules.Stuck ->
                  Log.(log ERROR "Got stuck!") ;
                  "the system does not know how to handle this source/sink pair (BUG -- please report!)"
            end
    end
  end with
  | Silently_fail
  | Traversal _ -> ()) ;
  true

let key_z mods =
  Traversal.(try begin
    if List.mem `CONTROL mods then begin
      match gui.hist with
      | [] ->
          flash "No history left to undo"
      | (cur, mmode) :: hist ->
          gui.hist <- hist ;
          rewrite_cur ~mmode cur
    end
  end with
  | Traversal _ -> ()) ;
  true

let key_q mods =
  Traversal.(try begin
    if List.mem `CONTROL mods then begin
      match gui.hist with
      | [] ->
          GMain.Main.quit ()
      | _ -> begin
        ignore (gui.stxt#push
                  "Quit without saving [y/n]?") ;
        ignore (gui.win#event#connect#key_press ~callback:(y_or_n GMain.Main.quit))
      end
    end
  end with
  | Traversal _ -> ()) ;
  true

let () =
  let open GdkKeysyms in
  kmap := List.fold_left begin
    fun kmap (k, act) ->
      Map.add k act kmap
  end Map.empty [
    _Down, key_down ;
    _Up, key_up ;
    _Left, key_left ;
    _Right, key_right ;
    _Return, key_enter ;
    _KP_Enter, key_enter ;
    _Delete, key_delete ;
    _z, key_z ;
    _Z, key_z ;
    _q, key_q ;
    _Q, key_q ;
  ]

let startup f =
  gui.cur <- f ;
  let win = GWindow.window
    ~title:"Profound"
    ~border_width:3
    ~deletable:true () in
  gui.win <- win ;
  win#misc#set_size_request ~width:800 ~height:600 () ;
  win#misc#modify_bg [`NORMAL, `NAME "ivory" ] ;
  ignore (win#event#connect#delete ~callback:(fun _ -> false)) ;
  ignore (win#connect#destroy ~callback:GMain.Main.quit) ;
  let box = GPack.vbox ~packing:win#add () in
  let sw = GBin.scrolled_window
    ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC
    ~packing:box#add () in
  let img = GMisc.image
    ~packing:sw#add_with_viewport () in
  gui.img <- img ;
  ignore (GMisc.separator `HORIZONTAL ~packing:(box#pack ~expand:false) ()) ;
  let sbar = GMisc.statusbar
    ~packing:(box#pack ~expand:false) () in
  let stxt = sbar#new_context "default" in
  gui.stxt <- stxt ;
  ignore (win#event#connect#key_press ~callback:handle_key) ;
  redisplay () ;
  win#show () ;
  GMain.Main.main ()
