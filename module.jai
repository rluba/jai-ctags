// Based on Ignacio’s CTags_Generator

// CTags file format:
// http://ctags.sourceforge.net/FORMAT

// @Incomplete: Missing features
// * How to we get a polymorphic struct’s parameters?
// * What’s the best way to find a struct/enum member’s parent to get its name? (if it has one)
// * How can we determine "scope_file" for non-root declarations? (We should probably simply tag all non-global, non-exported declarations as "scope_file")
// * Add support for Emacs’ etags format? Jon, are you interested in this? (https://en.wikipedia.org/wiki/Ctags#Etags_2)

CTags :: struct {
	output_filename := "tags";
	base_path: string;

	// If you need to convert the declarations’ paths for some reason
	transform_path: (ctags: *CTags, path: string) -> string;

    Symbol :: struct {
        name: string;
        filename: string;
        line: int;
        column: int;
		kind: Kind;
		arity: int;
		scope_file: bool;
    }

	Kind :: enum {
		UNSPECIFIED;
		ENUM;
		ENUM_MEMBER;
		FUNCTION;
		STRUCT;
		STRUCT_MEMBER;
		VARIABLE;
	}

    symbols: [..] *Symbol;
    strings: [..] string;  // Strings that need to be freed.
}

// You have to call this in your message loop
process_message :: (using ctags: *CTags, message: *Compiler_Message) {
	if message.kind == .CODE_TYPECHECKED {
		tc := cast(*Compiler_Message_Code_Typechecked) message;
		for decl: tc.declarations {
			if !decl.filename continue; // Skip language-defined declarations.

			if decl.flags & .IS_STRUCT_PARAMETER_CONSTANT continue; // Skip struct parameters.
			if decl.flags & .IS_IMPORTED continue; // Do not process declarations twice.

			if decl.name && is_alpha(decl.name[0]) {    // Make sure it's an ident (@@ skip operators for now).
				filename := decl.filename;
				if base_path && begins_with(filename, base_path) {
					filename = slice(filename, base_path.count + 1, filename.count - base_path.count - 1);
				}
				if transform_path {
					filename = transform_path(ctags, filename);
				}

				assert(path_extension(filename).count > 0, "No path extension: %", filename);

				symbol := New(Symbol);
				symbol.name = decl.name;
				symbol.filename = filename;
				symbol.line = decl.l0;
				symbol.column = decl.c0;
				symbol.kind = .UNSPECIFIED;
				symbol.arity = -1;
				symbol.scope_file = cast(bool) decl.flags & .SCOPE_FILE;

				if decl.flags & .IS_ENUM_MEMBER {
					symbol.kind = .ENUM_MEMBER;
				} else if decl.flags & .IS_STRUCT_MEMBER {
					symbol.kind = .STRUCT_MEMBER;
				} else if decl.root_expression {
					if decl.root_expression.kind == .PROCEDURE_HEADER {
						header := cast(*Code_Procedure_Header) decl.root_expression;
						symbol.kind = .FUNCTION;
						symbol.arity = header.arguments.count;
					} else if decl.root_expression.kind == .STRUCT {
						str := cast(*Code_Struct) decl.root_expression;
						symbol.kind = .STRUCT;
						// @ToDo: Arity/parameters of polymorphic structs?
					} else if decl.root_expression.kind == .ENUM {
						symbol.kind = .ENUM;
					} else {
						// @ToDo: kind: Variable
						// print("Adding other declaration: % (%, %)\n", decl.name, decl.flags, filename);
						// if decl.type_inst	 print("Type: %\n", <<decl.type_inst);
						// print("Root: %\n", <<decl.root_expression);
					}
				}

				array_add(*symbols, symbol);
			}
			else {
				// @@ What are declarations with no name?
			}
		}
	} else if message.kind == .COMPLETE {
		print ("Generating ctags file '%'\n", output_filename);

		intro_sort(symbols, (a: *CTags.Symbol, b: *CTags.Symbol) -> int {
			return compare(a.name, b.name);
		});

		// print the symbols in ctags format:
		builder: String_Builder;
		defer free_buffers(*builder);
		for symbols {
			print_to_builder(*builder, "%\t%\t%;\"", it.name, it.filename, it.line);
			if #complete it.kind == {
				case .ENUM;
					print_to_builder(*builder, "\tkind:g");
				case .ENUM_MEMBER;
					print_to_builder(*builder, "\tkind:e");
				case .FUNCTION;
					print_to_builder(*builder, "\tkind:f");
				case .STRUCT;
					print_to_builder(*builder, "\tkind:s");
				case .STRUCT_MEMBER;
					print_to_builder(*builder, "\tkind:m");
				case .VARIABLE;
					print_to_builder(*builder, "\tkind:v");
				case .UNSPECIFIED;
			}

			if it.arity >= 0 {
				print_to_builder(*builder, "\tarity:%", it.arity);
			}
			if it.scope_file {
				print_to_builder(*builder, "\tfile:");
			}
			// @ToDo tagfields: function, enum, struct
			print_to_builder(*builder, "\n");
		}

		write_entire_file(output_filename, builder_to_string(*builder));
	}
}

reset :: (using ctags: *CTags) {
	for symbols free(it);
	array_reset(*symbols);
	for strings free(it);
	array_reset(*strings);
}

// Example build function (but you probably want to roll your own)
build_ctags :: (filename: string) {
    build_options := get_build_options();
    build_options.output_type = .NO_OUTPUT;
    set_build_options(build_options);

    w := compiler_create_workspace();
    build_options.output_type = .EXECUTABLE;
    set_build_options(build_options, w);

	compiler_begin_intercept(w);

    add_build_file(filename, w);

	ctags: CTags;
	ctags.base_path = get_working_directory();
	defer reset(*ctags);

	while true {
		message := compiler_wait_for_message();
		if !message continue;

		if message.workspace == w {
			process_message(*ctags, message);
		}

		if message.kind == .COMPLETE break;
	}

	compiler_end_intercept(w);
}

#scope_file

#import "Compiler";
#import "String";
#import "IntroSort";
#import "File";
#import "Basic";

