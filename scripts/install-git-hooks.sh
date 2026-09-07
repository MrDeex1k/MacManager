#!/bin/sh
# Run once per clone. Only this repository's local Git configuration is changed.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
cd "$repo_root"

if [ ! -x .githooks/commit-msg ]; then
    printf '%s\n' 'Missing executable .githooks/commit-msg; restore its tracked executable bit.' >&2
    exit 1
fi

current=$(git config --get core.hooksPath || :)
if [ -n "$current" ] && [ "$current" != ".githooks" ]; then
    printf '%s\n' "Another hooksPath is configured ($current). Integrate existing hooks before installing." >&2
    exit 1
fi

# Avoid silently disabling existing hooks from the default directory.
if [ -z "$current" ]; then
    legacy_dir=$(git rev-parse --git-path hooks)
    for hook in "$legacy_dir"/*; do
        case "$hook" in *.sample) continue ;; esac
        if [ -f "$hook" ] && [ -x "$hook" ]; then
            printf '%s\n' "Existing hook found ($hook). Integrate it before installing." >&2
            exit 1
        fi
    done
fi

git config --local core.hooksPath .githooks
printf '%s\n' 'Conventional Commits enabled for this repository (.githooks/commit-msg).'
