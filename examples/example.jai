#load "../module.jai"; // In your code, you should do an #import instead of a #load
#run build_ctags(#file);

// Compile this to generate a "tags" file containing these functions an everything that got imported.

main :: () {
    a_function(25);
}

a_function :: (param: int) {
    value := 7;
}

