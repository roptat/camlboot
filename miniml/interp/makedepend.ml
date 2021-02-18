(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1999 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Parsetree

module StringMap = Depend.StringMap
module StringSet = Depend.StringSet

let ppf = Format.err_formatter
(* Print the dependencies *)

type file_kind = ML | MLI;;

let first_include_dirs = ref ([] : string list)
let include_dirs = ref ([] : string list)
let load_path = ref ([] : (string * string array) list)
let ml_synonyms = ref [".ml"]
let mli_synonyms = ref [".mli"]
let shared = ref false
let native_only = ref false
let bytecode_only = ref false
let error_occurred = ref false
let raw_dependencies = ref false
let all_dependencies = ref false
let one_line = ref false
let files =
  ref ([] : (string * file_kind * StringSet.t * string list) list)

let map_files = ref []
let module_map = ref StringMap.empty
let debug = ref false

(* Fix path to use '/' as directory separator instead of '\'.
   Only under Windows. *)

let fix_slash s =
  if Sys.os_type = "Unix" then s else begin
    String.map (function '\\' -> '/' | c -> c) s
  end

(* Since we reinitialize load_path after reading OCAMLCOMP,
  we must use a cache instead of calling Sys.readdir too often. *)
let dirs = ref StringMap.empty
let readdir dir =
  try
    StringMap.find dir !dirs
  with Not_found ->
    let contents =
      try
        Sys.readdir dir
      with Sys_error msg ->
        Format.fprintf Format.err_formatter "@[Bad -I option: %s@]@." msg;
        error_occurred := true;
        [||]
    in
    dirs := StringMap.add dir contents !dirs;
    contents

let add_to_list li s =
  li := s :: !li

let add_to_load_path dir =
  try
    (* let dir = Misc.expand_directory Config.standard_library dir in *)
    let contents = readdir dir in
    add_to_list load_path (dir, contents)
  with Sys_error msg ->
    Format.fprintf Format.err_formatter "@[Bad -I option: %s@]@." msg;
    error_occurred := true

let add_to_synonym_list synonyms suffix =
  if (String.length suffix) > 1 && suffix.[0] = '.' then
    add_to_list synonyms suffix
  else begin
    Format.fprintf Format.err_formatter "@[Bad suffix: '%s'@]@." suffix;
    error_occurred := true
  end

(* Find file 'name' (capitalized) in search path *)
let find_file name =
  let uname = String.uncapitalize_ascii name in
  let rec find_in_array a pos =
    if pos >= Array.length a then None else begin
      let s = a.(pos) in
      if s = name || s = uname then Some s else find_in_array a (pos + 1)
    end in
  let rec find_in_path = function
    [] -> raise Not_found
  | (dir, contents) :: rem ->
      match find_in_array contents 0 with
        Some truename ->
          if dir = "." then truename else Filename.concat dir truename
      | None -> find_in_path rem in
  find_in_path !load_path

let rec find_file_in_list = function
  [] -> raise Not_found
| x :: rem -> try find_file x with Not_found -> find_file_in_list rem


let find_dependency target_kind modname (byt_deps, opt_deps) =
  try
    let candidates = List.map ((^) modname) !mli_synonyms in
    let filename = find_file_in_list candidates in
    let basename = Filename.chop_extension filename in
    let cmi_file = basename ^ ".cmi" in
    let cmx_file = basename ^ ".cmx" in
    let ml_exists =
      List.exists (fun ext -> Sys.file_exists (basename ^ ext)) !ml_synonyms in
    let new_opt_dep =
      if !all_dependencies then
        match target_kind with
        | MLI -> [ cmi_file ]
        | ML  ->
          cmi_file :: (if ml_exists then [ cmx_file ] else [])
      else
        (* this is a make-specific hack that makes .cmx to be a 'proxy'
           target that would force the dependency on .cmi via transitivity *)
        if ml_exists
        then [ cmx_file ]
        else [ cmi_file ]
    in
    ( cmi_file :: byt_deps, new_opt_dep @ opt_deps)
  with Not_found ->
  try
    (* "just .ml" case *)
    let candidates = List.map ((^) modname) !ml_synonyms in
    let filename = find_file_in_list candidates in
    let basename = Filename.chop_extension filename in
    let cmi_file = basename ^ ".cmi" in
    let cmx_file = basename ^ ".cmx" in
    let bytenames =
      if !all_dependencies then
        match target_kind with
        | MLI -> [ cmi_file ]
        | ML  -> [ cmi_file ]
      else
        (* again, make-specific hack *)
        [basename ^ (if !native_only then ".cmx" else ".cmo")] in
    let optnames =
      if !all_dependencies
      then match target_kind with
        | MLI -> [ cmi_file ]
        | ML  -> [ cmi_file; cmx_file ]
      else [ cmx_file ]
    in
    (bytenames @ byt_deps, optnames @  opt_deps)
  with Not_found ->
    (byt_deps, opt_deps)

let depends_on = ":"
let escaped_eol = " \\\n    "

let print_filename s =
  let s = fix_slash s in
  if not (String.contains s ' ') then begin
    print_string s;
  end else begin
    let rec count n i =
      if i >= String.length s then n
      else if s.[i] = ' ' then count (n+1) (i+1)
      else count n (i+1)
    in
    let spaces = count 0 0 in
    let result = Bytes.create (String.length s + spaces) in
    let rec loop i j =
      if i >= String.length s then ()
      else if s.[i] = ' ' then begin
        Bytes.set result j '\\';
        Bytes.set result (j+1) ' ';
        loop (i+1) (j+2);
      end else begin
        Bytes.set result j s.[i];
        loop (i+1) (j+1);
      end
    in
    loop 0 0;
    print_bytes result;
  end
;;

let print_dependencies target_files deps =
  let rec print_items pos = function
    [] -> print_string "\n"
  | dep :: rem ->
    if !one_line || (pos + 1 + String.length dep <= 77) then begin
        if pos <> 0 then print_string " "; print_filename dep;
        print_items (pos + String.length dep + 1) rem
      end else begin
        print_string escaped_eol; print_filename dep;
        print_items (String.length dep + 4) rem
      end in
  print_items 0 (target_files @ [depends_on] @ deps)

let print_raw_dependencies source_file deps =
  print_filename source_file; print_string depends_on;
  StringSet.iter
    (fun dep ->
       (* filter out "*predef*" *)
      if (String.length dep > 0)
          && (match dep.[0] with
              | 'A'..'Z' | '\128'..'\255' -> true
              | _ -> false) then
        begin
          print_char ' ';
          print_string dep
        end)
    deps;
  print_char '\n'


(* Process one file *)

let report_err exn = error_occurred := true

let tool_name = "ocamldep"

let rec lexical_approximation lexbuf =
  (* Approximation when a file can't be parsed.
     Heuristic:
     - first component of any path starting with an uppercase character is a
       dependency.
     - always skip the token after a dot, unless dot is preceded by a
       lower-case identifier
     - always skip the token after a backquote
  *)
  try
    let rec process after_lident lexbuf =
      match Lexer.token lexbuf with
      | Parser.UIDENT name ->
          Depend.free_structure_names :=
            StringSet.add name !Depend.free_structure_names;
          process false lexbuf
      | Parser.LIDENT _ -> process true lexbuf
      | Parser.DOT when after_lident -> process false lexbuf
      | Parser.DOT | Parser.BACKQUOTE -> skip_one lexbuf
      | Parser.EOF -> ()
      | _ -> process false lexbuf
    and skip_one lexbuf =
      match Lexer.token lexbuf with
      | Parser.DOT | Parser.BACKQUOTE -> skip_one lexbuf
      | Parser.EOF -> ()
      | _ -> process false lexbuf

    in
    process false lexbuf
  with Lexer.Error _ -> lexical_approximation lexbuf

let read_and_approximate inputfile =
  error_occurred := false;
  Depend.free_structure_names := StringSet.empty;
  let ic = open_in_bin inputfile in
  try
    seek_in ic 0;
    Location.input_name := inputfile;
    let lexbuf = Lexing.from_channel ic in
    Location.init lexbuf inputfile;
    lexical_approximation lexbuf;
    close_in ic;
    !Depend.free_structure_names
  with exn ->
    close_in ic;
    report_err exn;
    !Depend.free_structure_names

let read_parse_and_extract parse_function extract_function source_file =
  Depend.pp_deps := [];
  Depend.free_structure_names := Depend.StringSet.empty;
  try
    let ic = open_in source_file in
    let lexbuf = Lexing.from_channel ic in
    Location.init lexbuf source_file;
    let ast = parse_function lexbuf in
    let bound_vars = !module_map in
    extract_function bound_vars ast;
    !Depend.free_structure_names
  with x -> begin
    read_and_approximate source_file
  end


let print_ml_dependencies source_file extracted_deps pp_deps =
  let basename = Filename.chop_extension source_file in
  let byte_targets = [ basename ^ ".cmo" ] in
  let native_targets =
    if !all_dependencies
    then [ basename ^ ".cmx"; basename ^ ".o" ]
    else [ basename ^ ".cmx" ] in
  let shared_targets = [ basename ^ ".cmxs" ] in
  let init_deps = if !all_dependencies then [source_file] else [] in
  let cmi_name = basename ^ ".cmi" in
  let init_deps, extra_targets =
    if List.exists (fun ext -> Sys.file_exists (basename ^ ext))
        !mli_synonyms
    then (cmi_name :: init_deps, cmi_name :: init_deps), []
    else (init_deps, init_deps),
         (if !all_dependencies then [cmi_name] else [])
  in
  let (byt_deps, native_deps) =
    StringSet.fold (find_dependency ML)
      extracted_deps init_deps in
  if not !native_only then
    print_dependencies (byte_targets @ extra_targets) (byt_deps @ pp_deps);
  if not !bytecode_only then
    begin
      print_dependencies (native_targets @ extra_targets)
        (native_deps @ pp_deps);
      if !shared then
        print_dependencies (shared_targets @ extra_targets)
          (native_deps @ pp_deps)
    end

let print_mli_dependencies source_file extracted_deps pp_deps =
  let basename = Filename.chop_extension source_file in
  let (byt_deps, _opt_deps) =
    StringSet.fold (find_dependency MLI)
      extracted_deps ([], []) in
  print_dependencies [basename ^ ".cmi"] (byt_deps @ pp_deps)

let print_file_dependencies (source_file, kind, extracted_deps, pp_deps) =
  if !raw_dependencies then begin
    print_raw_dependencies source_file extracted_deps
  end else
    match kind with
    | ML -> print_ml_dependencies source_file extracted_deps pp_deps
    | MLI -> print_mli_dependencies source_file extracted_deps pp_deps


let ml_file_dependencies source_file =
  let parse_use_file_as_impl lexbuf =
    let f x =
      match x with
      | Ptop_def s -> s
      | Ptop_dir _ -> []
    in
    List.flatten (List.map f (Parse.use_file lexbuf))
  in
  let extracted_deps =
    read_parse_and_extract parse_use_file_as_impl Depend.add_implementation source_file
  in
  files := (source_file, ML, extracted_deps, []) :: !files

let mli_file_dependencies source_file =
  let extracted_deps =
    read_parse_and_extract Parse.interface Depend.add_signature source_file
  in
  files := (source_file, MLI, extracted_deps, []) :: !files

let process_file_as process_fun def source_file =
  load_path := [];
  List.iter add_to_load_path (
      (!include_dirs @
       !first_include_dirs
      ));
  Location.input_name := source_file;
  try
    if Sys.file_exists source_file then process_fun source_file else def
  with x -> report_err x; def

let process_file source_file ~ml_file ~mli_file ~def =
  if List.exists (Filename.check_suffix source_file) !ml_synonyms then
    process_file_as ml_file def source_file
  else if List.exists (Filename.check_suffix source_file) !mli_synonyms then
    process_file_as mli_file def source_file
  else def

let file_dependencies source_file =
  process_file source_file ~def:()
    ~ml_file:ml_file_dependencies
    ~mli_file:mli_file_dependencies

let file_dependencies_as kind =
  match kind with
  | ML -> process_file_as ml_file_dependencies ()
  | MLI -> process_file_as mli_file_dependencies ()

(* Entry point *)

let main () =
  add_to_list first_include_dirs Filename.current_dir_name;
  let specs = [
     "-I", Arg.String (add_to_list include_dirs),
        "<dir>  Add <dir> to the list of include directories";
     "-impl", Arg.String (file_dependencies_as ML),
        "<f>  Process <f> as a .ml file";
     "-intf", Arg.String (file_dependencies_as MLI),
        "<f>  Process <f> as a .mli file";
     "-native", Arg.Set native_only,
        " Generate dependencies for native-code only (no .cmo files)";
     "-bytecode", Arg.Set bytecode_only,
        " Generate dependencies for bytecode-code only (no .cmx files)";
     (* "-pp", Arg.String(fun s -> Clflags.preprocessor := Some s),
         "<cmd>  Pipe sources through preprocessor <cmd>"; *)
  ] in
  let usage =
    Printf.sprintf "Usage: %s [options] <source files>\nOptions are:"
                   (Filename.basename Sys.argv.(0))
  in
  Arg.parse specs file_dependencies usage;
  List.iter print_file_dependencies (List.sort compare !files);
  exit (if !error_occurred then 2 else 0)

let () = main ()
