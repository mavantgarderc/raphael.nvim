std = "lua54"
globals = {
    "vim",
    "package",
    "_G",
    "jit"
}

read_globals = {
    "vim"
}

files = {
    ["lua/**/*.lua"] = {
        globals = {"describe", "it", "before_each", "after_each", "teardown", "setup"}
    }
}
