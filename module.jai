// Based on Ignacio’s CTags_Generator

// CTags file format:
// http://ctags.sourceforge.net/FORMAT

// @Incomplete: Missing features
// * How to we get a polymorphic struct’s parameters?
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
        parent: string; // @ToDo: Nested parents (CTags format says to use paths like "outer/inner")
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
process_message :: (using ctags: *CTags, message: *Message) {
	if message.kind == .TYPECHECKED {
		tc := cast(*Message_Typechecked) message;

		for tc: tc.declarations {
            decl := tc.expression;
            add_declaration(ctags, decl);
		}

        for tc: tc.procedure_bodies {
            decl := tc.expression;

            filename := get_filename(decl);
            if base_path && begins_with(filename, base_path) {
                filename = slice(filename, base_path.count + 1, filename.count - base_path.count - 1);
            }
            if transform_path {
                filename = transform_path(ctags, filename);
            }

            // print("Function body: % in %\n", decl.header.name, filename);
            for decl.block.members {
                assert(it.kind == .DECLARATION);
                member_decl := cast(*Code_Declaration)it;

                // @ToDo: Include imported members (but we have to get the filename differently for them).
                if member_decl.flags & .IS_IMPORTED continue; // Do not process imported variables for now.

                // print("Function member: % %\n", it.name, <<cast(*Code_Declaration)it);
                // @ToDo: Somehow get the flags of the header declaration
                add_symbol(*symbols, filename, it.name, it, .VARIABLE, 0, decl.header.name);
            }
        }

	} else if message.kind == .COMPLETE {
		print("Generating ctags file '%' (% symbols)\n", output_filename, symbols.count);

		intro_sort(symbols, (a: *CTags.Symbol, b: *CTags.Symbol) -> int {
			return compare(a.name, b.name);
		});

		// print the symbols in ctags format:
		builder: String_Builder;
		for symbols {
			print_to_builder(*builder, "%\t%\t/\\%%%l\\%%%c/;\"", it.name, it.filename, it.line, it.column);
			if #complete it.kind == {
				case .ENUM;
					print_to_builder(*builder, "\tkind:g");
				case .ENUM_MEMBER;
					print_to_builder(*builder, "\tkind:e\tenum:%", it.parent);
				case .FUNCTION;
					print_to_builder(*builder, "\tkind:f");
				case .STRUCT;
					print_to_builder(*builder, "\tkind:s");
				case .STRUCT_MEMBER;
					print_to_builder(*builder, "\tkind:m\tstruct:%", it.parent);
				case .VARIABLE;
					print_to_builder(*builder, "\tkind:v");
                    if it.parent {
                        print_to_builder(*builder, "\tfunction:%", it.parent);
                    }
				case .UNSPECIFIED;
			}

			if it.arity >= 0 {
				print_to_builder(*builder, "\tarity:%", it.arity);
			}
			if it.scope_file {
				print_to_builder(*builder, "\tfile:");
			}
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
	#if #run (get_current_workspace() != 2) return;

    set_build_options_dc(.{do_output = false});

	w := compiler_create_workspace();
	build_options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *build_options);
	build_options.output_type = .EXECUTABLE;
    build_options.output_executable_name = basename(filename);
	set_build_options(build_options, w);

	compiler_begin_intercept(w);

	add_build_file(filename, w);

	ctags: CTags;
	ctags.base_path = get_working_directory();

    // Need forward slashes in order to compare with Code_Node filenames.
    #if OS == .WINDOWS path_overwrite_separators(ctags.base_path, #char "/");

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

add_symbol :: (symbols: *[..] *CTags.Symbol, filename: string, name: string, node: *Code_Node, kind: CTags.Kind, flags: type_of(Code_Declaration.flags), parent := "", arity := -1) {
    symbol := New(CTags.Symbol);
    symbol.name = name;
    symbol.filename = filename;
    symbol.line = node.l0;
    symbol.column = node.c0;
    symbol.kind = kind;
    symbol.parent = parent;
    symbol.arity = arity;
    symbol.scope_file = cast(bool) flags & .SCOPE_FILE;
    // print("Adding symbol: %\n", <<symbol);

    array_add(symbols, symbol);
}

add_declaration :: (using ctags: *CTags, decl: *Code_Declaration) {
    if decl.flags & .IS_IMPORTED return; // Do not process duplicates for import links.

    if !decl.name {
        // @ToDo: What are declarations with no name?
        print("Found declaration wihout a name: %\n", <<decl);
        return;
    }

    filename := get_filename(decl);
    if base_path && begins_with(filename, base_path) {
        filename = slice(filename, base_path.count + 1, filename.count - base_path.count - 1);
    }
    if transform_path {
        filename = transform_path(ctags, filename);
    }

    assert(path_extension(filename).count > 0, "No path extension: %", filename);

    // print("Found declaration % in %\n", decl.name, filename);

    if decl.expression {
        if decl.expression.kind == {
            case .STRUCT;
                struct_decl := cast(*Code_Struct) decl.expression;
                add_symbol(*symbols, filename, decl.name, decl, .STRUCT, decl.flags);
                // print("Struct members:\n");
                if struct_decl.block {
                    for struct_decl.block.members {
                        // print("Member: %\n", it.name);
                        add_symbol(*symbols, filename, it.name, it, .STRUCT_MEMBER, decl.flags, decl.name);
                    }
                }
                if struct_decl.constants_block {
                    for struct_decl.constants_block.members {
                        // print("Constant member: %\n", it.name);
                        add_symbol(*symbols, filename, it.name, it, .STRUCT_MEMBER, decl.flags, decl.name);
                    }
                }
            case .ENUM;
                enum_decl := cast(*Code_Enum) decl.expression;
                add_symbol(*symbols, filename, decl.name, decl, .ENUM, decl.flags);
                // print("Enum members:\n");
                if enum_decl.block {
                    for enum_decl.block.members {
                        // print("Member: %\n", it.name);
                        add_symbol(*symbols, filename, it.name, it, .ENUM_MEMBER, decl.flags, decl.name);
                    }
                }
            case .PROCEDURE_HEADER;
                header_decl := cast(*Code_Procedure_Header) decl.expression;
                add_symbol(*symbols, filename, decl.name, decl, .FUNCTION, decl.flags, "", header_decl.arguments.count);
                for header_decl.arguments {
                    add_symbol(*symbols, filename, it.name, it, .VARIABLE, it.flags, decl.name);
                }
            case .PROCEDURE_BODY;
                body_decl := cast(*Code_Procedure_Body) decl.expression;
            case;
                // print("Found other kind: %\n", decl.expression.kind);
                add_symbol(*symbols, filename, decl.name, decl, .UNSPECIFIED, decl.flags);
        }
    } else {
        // print("No expression: %\n", <<decl);
        add_symbol(*symbols, filename, decl.name, decl, .VARIABLE, decl.flags);
    }
}


#import "Compiler";
#import "String";
#import "IntroSort";
#import "File";
#import "Basic";

