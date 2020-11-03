# Jai module for generating Ctags

This module generates a [ctags file](https://en.wikipedia.org/wiki/Ctags) for your project as part of normal compilation.
This allows many editors to access definitions (functions, variables, structs, …) for quick navigation or lookup.

## Usage

If you don’t yet control compilation via workspaces, you can simply call the included `build_ctags(…)` function from your main file:

```jai
#import "ctags";
#run build_ctags(#file);
```

Otherwise, i.e., if you’ve already set up a custom workspace for compilation, you have to init a `CTags` struct and call `process_message(…)` from your compiler message loop:

```jai
#import "ctags";

your_build_function :: () {
    w := compiler_create_workspace();
	// your compilation setup
	…

	compiler_begin_intercept(w);

	// add your build files
	…

	// Set up ctags options
	ctags: CTags;
	ctags.base_path = get_working_directory();
	defer reset(*ctags);

	while true {
		message := compiler_wait_for_message();
		if !message continue;

		if message.workspace == w {
			// Forward message to ctags generator
			process_message(*ctags, message);
		}

		if message.kind == .COMPLETE break;
	}
}
```

## Options

See the `CTags` struct for available options.
