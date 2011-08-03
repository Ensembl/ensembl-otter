
# Assumes we were called by script in this directory.  $0 is not this file!
dist_scripts="$( dirname "$0" )"

# Could differ from what we're operating upon, but probably doesn't
thisprog="$0 ($( cd "$dist_scripts" && git log -1 --format=%h ))"

bail() {
    echo "$1" >&2
    exit 1
}

config() {
    local key
    key="$1"
    head -n 1 -- "dist/conf/${key}"
}

config_set() {
    local key value
    key="$1"
    value="$2"
    if [ -n "$verbose" ]; then
        printf " : config_set(%s = %s)\n" "$key" "$value"
    fi
    sed -i -e "1s|.*|${value}|" "dist/conf/${key}"
    # returncode from sed
}

config_show_maybe() {
    local configs
#    if [ -n "$verbose" ]; then
# Useful always?
        printf "\ndist/conf/* for "
        git name-rev --always HEAD
        configs=$( cd dist/conf; echo * )
        for conf in $configs; do
            printf "  %-40s = '%s'\n" "$conf" "$(config "$conf" )"
        done
        echo
#    fi
}

git_show_maybe() {
    if [ -n "$verbose" ]; then
        git show
    fi
    true
}

git_listrefs_maybe() {
    if [ -n "$verbose" ]; then
        printf "\nTags\n"     && git tag     &&
        printf "\nBranches\n" && git branch
    fi
}
