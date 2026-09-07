#!/bin/sh
# Integration tests use disposable repositories, not the working tree's history.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd "$script_dir/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/macmanager-hooks.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
trap 'exit 1' HUP INT TERM

# Keep tests independent from the caller's Git repository and personal settings.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
unset GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Hook Test' GIT_AUTHOR_EMAIL='hook-test@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_TERMINAL_PROMPT=0

repo="$test_root/repository with spaces"
git -c init.templateDir= init -q "$repo"
mkdir -p "$repo/scripts"
cp -R "$repo_root/.githooks" "$repo/"
cp "$script_dir/install-git-hooks.sh" "$repo/scripts/"
cd "$repo"
./scripts/install-git-hooks.sh >/dev/null
./scripts/install-git-hooks.sh >/dev/null
[ "$(git config --local --get core.hooksPath)" = ".githooks" ]

checks=0
check_message() {
    expected=$1
    body=$2
    printf '%b\n' "$body" > "$test_root/message"
    if .githooks/commit-msg "$test_root/message" > "$test_root/output" 2>&1; then
        actual=accept
    else
        actual=reject
    fi
    if [ "$actual" != "$expected" ]; then
        printf '%s\n' "Expected $expected, got $actual for: $body" >&2
        cat "$test_root/output" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

for type in feat fix docs style refactor perf test build ci chore revert; do
    check_message accept "$type: describe a change"
done
check_message accept 'feat(metrics): add CPU monitoring'
check_message accept 'fix(scroll/mouse): preserve trackpad gestures'
check_message accept 'refactor!: change the public interface'
check_message accept 'refactor(core)!: change the public interface'
check_message accept 'FEAT(UI): add a panel'
check_message accept 'docs: dodaj dokumentację'
check_message accept 'fix: correct parsing\n\nExplain why.\n\nRefs: #12'
check_message accept 'feat: change the API\n\nBREAKING CHANGE: callers must migrate'
check_message accept 'feat: change the API\n\nBREAKING-CHANGE: callers must migrate'
check_message accept '# editor comment\ndocs: add a guide\n\n# trailing comment'
git config --local core.commentChar ';'
check_message accept '; editor comment\ndocs: add a guide'
git config --local --unset core.commentChar

for body in '' 'update docs' 'Merge branch main' 'fixup! feat: add a panel' \
    'unknown: change something' 'feat:no space' 'feat: ' 'feat:  ' \
    'feat:  double space' 'feat:  invalid: still invalid' 'feat(): empty scope' 'feat(two words): invalid scope' \
    'feat(core)!!: invalid marker' 'feat: title\nbody without separator' \
    'feat: title\n\nBREAKING CHANGE:'; do
    check_message reject "$body"
done

# Exercise Git itself: rejection must leave HEAD unchanged.
git -c commit.gpgsign=false commit -q --allow-empty -m 'chore: initialize hook test'
before=$(git rev-parse HEAD)
if git -c commit.gpgsign=false commit --allow-empty -m 'invalid subject' > "$test_root/output" 2>&1; then
    printf '%s\n' 'Git unexpectedly accepted an invalid subject.' >&2
    exit 1
fi
[ "$(git rev-parse HEAD)" = "$before" ]
git -c commit.gpgsign=false commit -q --allow-empty -m 'feat(core)!: verify commit integration'
[ "$(git rev-parse HEAD)" != "$before" ]

# Installer must preserve another hook configuration and existing default hooks.
git config --local core.hooksPath custom-hooks
if ./scripts/install-git-hooks.sh > "$test_root/output" 2>&1; then
    printf '%s\n' 'Installer overwrote another hooksPath.' >&2
    exit 1
fi
[ "$(git config --local --get core.hooksPath)" = "custom-hooks" ]
git config --local --unset core.hooksPath
mkdir -p .git/hooks
printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
if ./scripts/install-git-hooks.sh > "$test_root/output" 2>&1; then
    printf '%s\n' 'Installer disabled an existing default hook.' >&2
    exit 1
fi

printf '%s\n' "Passed $checks message cases, Git commit integration, and installer safety checks."
