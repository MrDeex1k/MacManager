#!/bin/sh
# Run once per clone. Only this repository's local Git configuration is changed.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
cd "$repo_root"

for required_hook in .githooks/pre-commit .githooks/commit-msg; do
    if [ ! -x "$required_hook" ]; then
        printf '%s\n' "Missing executable $required_hook; restore its tracked executable bit." >&2
        exit 1
    fi
done

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
printf '%s\n' 'Repository commit checks enabled from .githooks.'
