#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
git init -q

forbidden=$(printf '\342\200\224')
printf 'Historical text %s\n' "$forbidden" > history.txt
git add history.txt
git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=Fixture \
    -c user.email=fixture@example.invalid commit -qm 'test: seed fixture'

printf 'Plain staged text\n' > 'new text.txt'
git add 'new text.txt'
printf 'Unstaged text %s\n' "$forbidden" >> 'new text.txt'
"$root/.githooks/pre-commit"

# An added line beginning with "++" must not be mistaken for a file header.
printf 'Plain staged text\n++ Forbidden staged text %s\n' "$forbidden" > 'new text.txt'
git add 'new text.txt'
if "$root/.githooks/pre-commit" > hook.log 2>&1; then
    printf '%s\n' 'pre-commit accepted a staged em dash.' >&2
    exit 1
fi
grep -q 'Commit rejected: Unicode em dash' hook.log

printf 'fix(scope): describe the change\n\nExplain the change.\n' > message
"$root/.githooks/commit-msg" message
printf 'invalid message\n' > message
if "$root/.githooks/commit-msg" message > hook.log 2>&1; then
    printf '%s\n' 'commit-msg accepted an invalid commit message.' >&2
    exit 1
fi
grep -q 'See CONTRIBUTING.md' hook.log
printf '%s\n' 'Git hook checks passed.'
