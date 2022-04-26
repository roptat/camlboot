open Data
open Conf
open Eval
open Envir

let parse filename =
  let inc = try open_in filename with e -> Format.eprintf "Error opening file: %s@." filename; raise e in
  let lexbuf = Lexing.from_channel inc in
  Location.init lexbuf filename;
(*  let parsed = Parser.implementation Lexer.real_token lexbuf in *)
  let parsed = Parse.implementation lexbuf in
  close_in inc;
  parsed

type env_flag = Open of Longident.t

let stdlib_flag = [Open (Longident.Lident "Stdlib")]
let no_stdlib_flag = []

let stdlib_units =
  let stdlib_path = stdlib_path () in
  let fullpath file = Filename.concat stdlib_path file in
  (no_stdlib_flag, fullpath "stdlib.ml")
  ::
  List.map (fun file -> stdlib_flag, fullpath file) [
    "bool.ml";
    "fun.ml";
    "int.ml";
    "unit.ml";
    "option.ml";
    "pervasives.ml";
    "result.ml";
    "sys.ml";
    "callback.ml";
    "complex.ml";
    "float.ml";
    "char.ml";
    "bytes.ml";
    "string.ml";
    "bytesLabels.ml";
    "stringLabels.ml";
    "seq.ml";
    "list.ml";
    "listLabels.ml";
    "set.ml";
    "map.ml";
    "uchar.ml";
    "buffer.ml";
    "stream.ml";
    "genlex.ml";
    "camlinternalFormatBasics.ml";
    "camlinternalFormat.ml";
    "printf.ml";
    "scanf.ml";
    "queue.ml";
    "stack.ml";
    "format.ml";
    "obj.ml";
    "gc.ml";
    "camlinternalOO.ml";
    "oo.ml";
    "camlinternalLazy.ml";
    "lazy.ml";
    "printexc.ml";
    "array.ml";
    "arrayLabels.ml";
    "int64.ml";
    "int32.ml";
    "nativeint.ml";
    "digest.ml";
    "random.ml";
    "hashtbl.ml";
    "lexing.ml";
    "parsing.ml";
    "weak.ml";
    "ephemeron.ml";
    "spacetime.ml";
    "arg.ml";
    "filename.ml";
    "marshal.ml";
    "bigarray.ml";
    "moreLabels.ml";
    "stdLabels.ml";
  ]

let eval_env_flag ~loc env flag =
  match flag with
  | Open module_ident ->
     let module_ident = Location.mkloc module_ident loc in
     env_extend false env (env_get_module_data env module_ident)

let load_rec_units env flags_and_units =
  let unit_paths = List.map snd flags_and_units in
  let env = List.fold_left declare_unit env unit_paths in
  List.fold_left
    (fun global_env (flags, unit_path) ->
      let module_name = module_name_of_unit_path unit_path in
      if debug then Format.eprintf "Loading %s from %s@." module_name unit_path;
      let module_contents =
        let loc = Location.in_file unit_path in
        let local_env = List.fold_left (eval_env_flag ~loc) global_env flags in
        eval_structure Primitives.prims local_env (parse unit_path)
      in
      define_unit global_env unit_path (make_module_data module_contents))
    env
    flags_and_units

let stdlib_env =
  let env = Runtime_base.initial_env in
  let env = load_rec_units env stdlib_units in
  env

module Compiler_files = struct
  let utils = List.map (Filename.concat "utils") [
    "config.ml";
    "misc.ml";
    "identifiable.ml";
    "numbers.ml";
    "arg_helper.ml";
    "clflags.ml";
    "profile.ml";
    "terminfo.ml";
    "ccomp.ml";
    "warnings.ml";
    "consistbl.ml";
    "strongly_connected_components.ml";
    "build_path_prefix_map.ml";
    "targetint.ml";
    "int_replace_polymorphic_compare.ml"
  ]

  let parsing = List.map (Filename.concat "parsing") [
    "camlinternalMenhirLib.ml";
    "asttypes.mli";
    "location.ml";
    "longident.ml";
    "parsetree.mli";
    "docstrings.ml";
    "syntaxerr.ml";
    "ast_helper.ml";
    "parser.ml";
    "lexer.ml";
    "parse.ml";
    "printast.ml";
    "pprintast.ml";
    "ast_mapper.ml";
    "ast_iterator.ml";
    "attr_helper.ml";
    "builtin_attributes.ml";
    "ast_invariants.ml";
    "depend.ml";
  ]

  let file_formats = List.map (Filename.concat "file_formats") [
    "cmi_format.ml";
  ]

  let pure_typing = List.map (Filename.concat "typing") [
    "ident.ml";
    "outcometree.mli";
    "annot.mli";
    "path.ml";
    "primitive.ml";
    "types.ml";
    "btype.ml";
    "oprint.ml";
    "subst.ml";
    "predef.ml";
    "datarepr.ml";
    "persistent_env.ml";
    "env.ml";
    "typedtree.ml";
    "printtyped.ml";
    "ctype.ml";
    "printtyp.ml";
    "includeclass.ml";
    "mtype.ml";
    "envaux.ml";
    "includecore.ml";
    "tast_mapper.ml";
    "untypeast.ml";
    "includemod.ml";
    "typetexp.ml";
    "printpat.ml";
    "parmatch.ml";
    "stypes.ml";
    "typedecl_unboxed.ml";
    "typedecl.ml";
  ]

  let more_file_formats = List.map (Filename.concat "file_formats") [
    "cmt_format.ml";
    "cmo_format.mli";
    "cmx_format.mli";
    "cmxs_format.mli";
  ]

  let lambda = List.map (Filename.concat "lambda") [
    "lambda.ml";
  ]

  let more_typing = List.map (Filename.concat "typing") [
    "typeopt.ml";
    "typecore.ml";
    "typeclass.ml";
    "typemod.ml";
  ]

  let more_lambda = List.map (Filename.concat "lambda") [
    "printlambda.ml";
    "switch.ml";
    "matching.ml";
    "translobj.ml";
    "translattribute.ml";
    "translprim.ml";
    "translcore.ml";
    "translclass.ml";
    "translmod.ml";
    "simplif.ml";
    "runtimedef.ml";
    "debuginfo.ml";
  ]

  let bytecomp = List.map (Filename.concat "bytecomp") [
    "meta.ml";
    "opcodes.ml";
    "bytesections.ml";
    "dll.ml";
    "symtable.ml";
  ]

  let driver = List.map (Filename.concat "driver") [
    "pparse.ml";
    "main_args.ml";
    "compenv.ml";
    "compmisc.ml";
    "makedepend.ml";
  ]

  let middle_end = List.map (Filename.concat "middle_end") [
    "semantics_of_primitives.ml";
    "flambda/base_types/id_types.ml";
    "compilation_unit.ml";
    "flambda/base_types/set_of_closures_id.ml";
    "symbol.ml";
    "variable.ml";
    "flambda/base_types/closure_element.ml";
    "flambda/base_types/closure_id.ml";
    "flambda/base_types/var_within_closure.ml";
    "linkage_name.ml";
    "flambda/flambda_utils.ml";
    "flambda/simple_value_approx.ml";
    "clambda.ml";
    "flambda/export_info.ml";
    "compilenv.ml";
    "flambda/import_approx.ml";
    "backend_var.ml";
    "clambda_primitives.ml";
    "closure/closure.ml";
  ]

  let asmcomp = List.map (Filename.concat "asmcomp") [
    "debug/reg_with_debug_info.ml";
    "debug/reg_availability_set.ml";
    "debug/available_regs.ml";

    "x86_ast.mli";
    "x86_proc.ml";
    "x86_dsl.ml";
    "x86_gas.ml";

    "arch.ml";
    "cmm.ml";
    "reg.ml";
    "mach.ml";
    "proc.ml";

    "selectgen.ml";
    "spacetime_profiling.ml";
    "selection.ml";

    "strmatch.ml";
    "cmmgen.ml";
    "linearize.ml";
    "branch_relaxation.ml";
    "emitaux.ml";
    "emit.ml";
    "comballoc.ml";
    "CSEgen.ml";
    "CSE.ml";
    "liveness.ml";
    "deadcode.ml";
    "split.ml";
    "spill.ml";
    "interf.ml";
    "coloring.ml";
    "reloadgen.ml";
    "reload.ml";
    "schedgen.ml";
    "scheduling.ml";
    "asmgen.ml";

    "asmlink.ml";
    "asmlibrarian.ml";
  ]

  let bytegen = List.map (Filename.concat "bytecomp") [
    "instruct.ml";
    "bytegen.ml";
    "printinstr.ml";
    "emitcode.ml";
    "bytelink.ml";
    "bytelibrarian.ml";
    "bytepackager.ml";
  ]

  let bytecode_main = List.map (Filename.concat "driver") [
    "errors.ml";
    "compile.ml";
    "main.ml";
  ]

  let native_main = List.map (Filename.concat "driver") [
    "opterrors.ml";
    "compile_common.ml";
    "optcompile.ml";
    "optmain.ml";
  ]
end

let bytecode_compiler_units =
  let compiler_source_path = compiler_source_path () in
  let fullpath file = Filename.concat compiler_source_path file in
  List.map (fun modfile -> stdlib_flag, fullpath modfile)
  ( Compiler_files.utils
  @ Compiler_files.parsing
  @ Compiler_files.file_formats
  @ Compiler_files.pure_typing
  @ Compiler_files.more_file_formats
  @ Compiler_files.lambda
  @ Compiler_files.more_typing
  @ Compiler_files.more_lambda
  @ Compiler_files.bytecomp
  @ Compiler_files.driver
  @ Compiler_files.bytegen
  @ Compiler_files.bytecode_main
  )

let native_compiler_units =
  let compiler_source_path = compiler_source_path () in
  let fullpath file = Filename.concat compiler_source_path file in
  List.map (fun modfile -> stdlib_flag, fullpath modfile)
  ( Compiler_files.utils
  @ Compiler_files.parsing
  @ Compiler_files.file_formats
  @ Compiler_files.pure_typing
  @ Compiler_files.more_file_formats
  @ Compiler_files.lambda
  @ Compiler_files.more_typing
  @ Compiler_files.more_lambda
  @ Compiler_files.bytecomp
  @ Compiler_files.driver
  @ Compiler_files.middle_end
  @ Compiler_files.asmcomp
  @ Compiler_files.native_main
  )

let run_ocamlc () =
  ignore (load_rec_units stdlib_env bytecode_compiler_units)

let run_ocamlopt () =
  ignore (load_rec_units stdlib_env native_compiler_units)

let run_files () =
  let rev_files = ref [] in
  let anon_fun file = rev_files := file :: !rev_files in
  Arg.parse [] anon_fun "";
  let files = List.rev !rev_files in
  files
  |> List.map (fun file -> stdlib_flag, file)
  |> load_rec_units stdlib_env
  |> ignore

(* let _ = load_rec_units stdlib_env [stdlib_flag, "test.ml"] *)
let () =
  let open Conf in
  try match Conf.command () with
    | Some cmd ->
      begin match cmd with
        | Ocamlc -> run_ocamlc ()
        | Ocamlopt -> run_ocamlopt ()
        | Files -> run_files ()
      end
    | None -> run_ocamlc ()
  with InternalException e ->
    Format.eprintf "Code raised exception: %a@." pp_print_value e
