#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
JUSTFILE="$REPO_ROOT/justfile"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_dir() {
    local path="$1"
    [ -d "$path" ] || fail "missing directory: ${path#$REPO_ROOT/}"
}

assert_target_contains() {
    local target="$1" pattern="$2"
    awk -v target="$target" -v pattern="$pattern" '
        $0 == target ":" { in_target = 1; next }
        in_target && /^[^[:space:]#].*:/ { exit }
        in_target && $0 ~ pattern { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$JUSTFILE" || fail "target $target does not contain $pattern"
}

assert_target_orders() {
    local target="$1" first="$2" second="$3"
    awk -v target="$target" -v first="$first" -v second="$second" '
        $0 == target ":" { in_target = 1; next }
        in_target && /^[^[:space:]#].*:/ { exit }
        in_target && first_line == 0 && $0 ~ first { first_line = NR }
        in_target && second_line == 0 && $0 ~ second { second_line = NR }
        END { exit first_line > 0 && second_line > first_line ? 0 : 1 }
    ' "$JUSTFILE" || fail "target $target does not order $first before $second"
}

assert_no_shell_scripts() {
    local path="$1"
    [ ! -d "$path" ] || ! find "$path" -type f -name '*.sh' -print -quit | grep -q . \
        || fail "legacy shell scripts remain under ${path#$REPO_ROOT/}"
}

assert_versioned_state_defaults() {
    local version="$1" expected_env="$2" expected_state="$3"
    local temp_root output env_path state_path
    temp_root=$(mktemp -d)
    mkdir -p "$temp_root/scripts/porep-market/shared"
    cp "$ROOT/shared/_common.sh" "$temp_root/scripts/porep-market/shared/_common.sh"
    output=$(POREP_MARKET_VERSION="$version" bash -c '
        source "$1"
        printf "%s\\n%s\\n" "$ENV_FILE" "$STATE_FILE"
    ' _ "$temp_root/scripts/porep-market/shared/_common.sh")
    env_path=$(printf '%s\n' "$output" | sed -n '1p')
    state_path=$(printf '%s\n' "$output" | sed -n '2p')
    [[ "$env_path" == */"$expected_env" ]] || fail "${version} environment default was $env_path"
    [[ "$state_path" == */"$expected_state" ]] || fail "${version} state default was $state_path"
}

assert_default_porep_dir() {
    local version="$1" expected_name="$2" temp_root common output expected
    temp_root=$(mktemp -d)
    mkdir -p "$temp_root/scripts/porep-market/shared"
    common="$temp_root/scripts/porep-market/shared/_common.sh"
    cp "$ROOT/shared/_common.sh" "$common"
    output=$(POREP_MARKET_VERSION="$version" bash -c 'source "$1"; default_porep_dir "$2"' _ "$common" "$version")
    expected="$temp_root/scripts/porep-market/$expected_name"
    [ "$output" = "$expected" ] || fail "${version} managed checkout was $output, expected $expected"
}

assert_new_pinned_checkout_is_detached() {
    local temp_root source_repo bare_repo checkout_dir ref
    temp_root=$(mktemp -d)
    source_repo="$temp_root/source"
    bare_repo="$temp_root/source.git"
    checkout_dir="$temp_root/checkout"

    git init -q "$source_repo"
    git -C "$source_repo" config user.email test@example.invalid
    git -C "$source_repo" config user.name test
    touch "$source_repo/fixture"
    git -C "$source_repo" add fixture
    git -C "$source_repo" commit -qm fixture
    ref=$(git -C "$source_repo" rev-parse HEAD)
    git init -q --bare "$bare_repo"
    git -C "$source_repo" remote add origin "$bare_repo"
    git -C "$source_repo" push -q origin HEAD:main
    git -C "$bare_repo" symbolic-ref HEAD refs/heads/main

    mkdir -p "$temp_root/scripts/porep-market/shared"
    cp "$ROOT/shared/_common.sh" "$temp_root/scripts/porep-market/shared/_common.sh"
    bash -c 'source "$1"; checkout_pinned_repo fixture "$2" "$3" "$4"' _ \
        "$temp_root/scripts/porep-market/shared/_common.sh" "$bare_repo" "$checkout_dir" "$ref"
    git -C "$checkout_dir" rev-parse HEAD | grep -Fxq "$ref" \
        || fail "new checkout did not resolve to requested ref"
    ! git -C "$checkout_dir" symbolic-ref -q HEAD >/dev/null \
        || fail "new checkout is not detached at requested ref"
}

init_checkout_fixture() {
    local directory="$1"
    git init -q "$directory"
    git -C "$directory" config user.email test@example.invalid
    git -C "$directory" config user.name test
    printf 'fixture\n' > "$directory/source.txt"
    git -C "$directory" add source.txt
    git -C "$directory" commit -qm fixture
}

assert_explicit_checkout_rejects_wrong_head() {
    local temp_root checkout_dir expected_ref output
    temp_root=$(mktemp -d)
    checkout_dir="$temp_root/checkout"
    init_checkout_fixture "$checkout_dir"
    expected_ref=$(git -C "$checkout_dir" rev-parse HEAD)
    printf 'second\n' >> "$checkout_dir/source.txt"
    git -C "$checkout_dir" commit -qam second

    if output=$(bash -c 'source "$1"; require_pinned_repo fixture "$2" "$3"' _ \
        "$ROOT/shared/_common.sh" "$checkout_dir" "$expected_ref" 2>&1); then
        fail "explicit checkout accepted the wrong HEAD"
    fi
    grep -Fq "expected $expected_ref" <<<"$output" \
        || fail "wrong-HEAD error did not name the expected ref"
}

assert_matching_checkout_rejects_source_changes() {
    local temp_root checkout_dir ref output
    temp_root=$(mktemp -d)
    checkout_dir="$temp_root/checkout"
    init_checkout_fixture "$checkout_dir"
    ref=$(git -C "$checkout_dir" rev-parse HEAD)
    printf 'dirty\n' >> "$checkout_dir/source.txt"

    if output=$(bash -c 'source "$1"; checkout_pinned_repo fixture "$2" "$3" "$4"' _ \
        "$ROOT/shared/_common.sh" "$checkout_dir" "$checkout_dir" "$ref" 2>&1); then
        fail "matching checkout accepted source changes"
    fi
    grep -Fq 'source-bearing local changes' <<<"$output" \
        || fail "dirty-source error was not explicit"
}

assert_deployment_json_only_changes_are_allowed() {
    local temp_root checkout_dir ref
    temp_root=$(mktemp -d)
    checkout_dir="$temp_root/checkout"
    init_checkout_fixture "$checkout_dir"
    mkdir -p "$checkout_dir/deployments/devnet"
    printf '{}\n' > "$checkout_dir/deployments/devnet/latest.json"
    git -C "$checkout_dir" add deployments/devnet/latest.json
    git -C "$checkout_dir" commit -qm deployment
    ref=$(git -C "$checkout_dir" rev-parse HEAD)
    printf '{"updated":true}\n' > "$checkout_dir/deployments/devnet/latest.json"
    printf '{}\n' > "$checkout_dir/deployments/devnet/run.json"

    bash -c 'source "$1"; require_pinned_repo fixture "$2" "$3"' _ \
        "$ROOT/shared/_common.sh" "$checkout_dir" "$ref" \
        || fail "deployment JSON-only changes were rejected"
}

assert_untracked_foundry_lock_is_allowed() {
    local temp_root checkout_dir ref
    temp_root=$(mktemp -d)
    checkout_dir="$temp_root/checkout"
    init_checkout_fixture "$checkout_dir"
    ref=$(git -C "$checkout_dir" rev-parse HEAD)
    printf 'generated lock\n' > "$checkout_dir/foundry.lock"

    bash -c 'source "$1"; require_pinned_repo fixture "$2" "$3"' _ \
        "$ROOT/shared/_common.sh" "$checkout_dir" "$ref" \
        || fail "untracked generated foundry.lock was rejected"
    bash -c 'source "$1"; checkout_pinned_repo fixture "$2" "$3" "$4"' _ \
        "$ROOT/shared/_common.sh" "$checkout_dir" "$checkout_dir" "$ref" \
        || fail "managed checkout rejected untracked generated foundry.lock"
}

assert_tracked_foundry_lock_changes_are_rejected() {
    local temp_root checkout_dir ref output
    temp_root=$(mktemp -d)
    checkout_dir="$temp_root/checkout"
    init_checkout_fixture "$checkout_dir"
    printf 'tracked lock\n' > "$checkout_dir/foundry.lock"
    git -C "$checkout_dir" add foundry.lock
    git -C "$checkout_dir" commit -qm lock
    ref=$(git -C "$checkout_dir" rev-parse HEAD)
    printf 'modified lock\n' > "$checkout_dir/foundry.lock"

    if output=$(bash -c 'source "$1"; checkout_pinned_repo fixture "$2" "$3" "$4"' _ \
        "$ROOT/shared/_common.sh" "$checkout_dir" "$checkout_dir" "$ref" 2>&1); then
        fail "modified tracked foundry.lock was accepted"
    fi
    grep -Fq ' M foundry.lock' <<<"$output" \
        || fail "tracked foundry.lock error did not report the modified file"
}

assert_chain_mismatch_stops_before_key_extraction() {
    local temp_root fake_bin calls output
    temp_root=$(mktemp -d)
    fake_bin="$temp_root/bin"
    calls="$temp_root/calls.log"
    mkdir -p "$fake_bin" "$temp_root/scripts/porep-market/v1/setup" "$temp_root/scripts/porep-market/shared"
    cp "$ROOT/shared/_common.sh" "$temp_root/scripts/porep-market/shared/_common.sh"
    cp "$ROOT/v1/_common.sh" "$temp_root/scripts/porep-market/v1/_common.sh"
    cp "$ROOT/v1/setup/_common.sh" "$temp_root/scripts/porep-market/v1/setup/_common.sh"
    cp "$ROOT/v1/setup/01_extract_key.sh" "$temp_root/scripts/porep-market/v1/setup/01_extract_key.sh"

    cat > "$fake_bin/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >> "$CALLS"
exit 0
EOF
    cat > "$fake_bin/cast" <<'EOF'
#!/bin/bash
echo "cast $*" >> "$CALLS"
if [ "${1:-}" = "chain-id" ]; then
    echo 1
    exit 0
fi
echo 'unexpected cast command' >&2
exit 1
EOF
    chmod +x "$fake_bin/docker" "$fake_bin/cast"

    if output=$(CALLS="$calls" PATH="$fake_bin:$PATH" \
        bash "$temp_root/scripts/porep-market/v1/setup/01_extract_key.sh" 2>&1); then
        fail "wrong chain ID did not stop key extraction"
    fi
    grep -Fq 'expected chain ID 31415926, got 1' <<<"$output" \
        || fail "wrong-chain error was not explicit"
    ! grep -Eq 'wallet (default|export)|lotus send' "$calls" \
        || fail "key extraction or send ran after a chain mismatch"
}

assert_chain_mismatch_stops_deposit_scripts_before_key_use() {
    local temp_root fake_bin calls output script label
    temp_root=$(mktemp -d)
    fake_bin="$temp_root/bin"
    mkdir -p \
        "$fake_bin" \
        "$temp_root/v1/scripts/porep-market/shared" \
        "$temp_root/v1/scripts/porep-market/v1/steps" \
        "$temp_root/legacy/scripts/porep-market/steps"

    cp "$ROOT/shared/_common.sh" "$temp_root/v1/scripts/porep-market/shared/_common.sh"
    cp "$ROOT/v1/_common.sh" "$temp_root/v1/scripts/porep-market/v1/_common.sh"
    cp "$ROOT/v1/steps/_common.sh" "$temp_root/v1/scripts/porep-market/v1/steps/_common.sh"
    cp "$ROOT/v1/steps/11_deposit_and_approve_operator.sh" \
        "$temp_root/v1/scripts/porep-market/v1/steps/11_deposit_and_approve_operator.sh"
    cp "$ROOT/_common.sh" "$temp_root/legacy/scripts/porep-market/_common.sh"
    cp "$ROOT/steps/_common.sh" "$temp_root/legacy/scripts/porep-market/steps/_common.sh"
    cp "$ROOT/steps/11_deposit_and_approve_operator.sh" \
        "$temp_root/legacy/scripts/porep-market/steps/11_deposit_and_approve_operator.sh"

    cat > "$fake_bin/docker" <<'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$fake_bin/cast" <<'EOF'
#!/bin/bash
echo "cast $*" >> "$CALLS"
if [ "${1:-}" = "chain-id" ]; then
    echo 1
    exit 0
fi
exit 97
EOF
    cat > "$fake_bin/node" <<'EOF'
#!/bin/bash
echo "node $*" >> "$CALLS"
exit 97
EOF
    chmod +x "$fake_bin/docker" "$fake_bin/cast" "$fake_bin/node"

    for label in v1 legacy; do
        calls="$temp_root/$label.calls"
        if [ "$label" = v1 ]; then
            script="$temp_root/v1/scripts/porep-market/v1/steps/11_deposit_and_approve_operator.sh"
        else
            script="$temp_root/legacy/scripts/porep-market/steps/11_deposit_and_approve_operator.sh"
        fi
        if output=$(CALLS="$calls" PATH="$fake_bin:$PATH" bash "$script" 2>&1); then
            fail "$label deposit script accepted the wrong chain"
        fi
        grep -Fq 'expected chain ID 31415926, got 1' <<<"$output" \
            || fail "$label deposit script did not reject the wrong chain first"
        ! grep -Eq '^cast (call|wallet|max-uint)' "$calls" \
            || fail "$label deposit script used cast after a chain mismatch"
        ! grep -q '^node ' "$calls" \
            || fail "$label deposit script signed a permit after a chain mismatch"
    done
}

assert_file_contains() {
    local path="$1" expected="$2"
    [ -f "$path" ] || fail "missing file: ${path#$REPO_ROOT/}"
    grep -Fxq "$expected" "$path" || fail "missing exact line in ${path#$REPO_ROOT/}: $expected"
}

assert_file_not_contains() {
    local path="$1" unexpected="$2"
    [ -f "$path" ] || fail "missing file: ${path#$REPO_ROOT/}"
    ! grep -Fqx "$unexpected" "$path" || fail "unexpected exact line in ${path#$REPO_ROOT/}: $unexpected"
}

assert_documented_versioned_targets_exist() {
    local target
    while IFS= read -r target; do
        assert_target_contains "$target" '.'
    done < <(rg --no-filename -o 'just porep-v[12]-[[:alnum:]-]+' "$@" | sed 's/^just //' | sort -u)
}

assert_dir "$ROOT/v2/manual/setup"
assert_dir "$ROOT/v2/manual/steps"
assert_dir "$ROOT/v2/manual/scenarios"
assert_no_shell_scripts "$ROOT/v2/steps"
assert_no_shell_scripts "$ROOT/v2/scenarios"

assert_versioned_state_defaults v1 .env.v1 .state.v1
assert_versioned_state_defaults v2 .env.v2 .state.v2
assert_default_porep_dir v1 porep-market-v1-62754c6ceafe
assert_default_porep_dir v2 porep-market-v2-803942a5f439
assert_new_pinned_checkout_is_detached
assert_explicit_checkout_rejects_wrong_head
assert_matching_checkout_rejects_source_changes
assert_deployment_json_only_changes_are_allowed
assert_chain_mismatch_stops_deposit_scripts_before_key_use
assert_untracked_foundry_lock_is_allowed
assert_tracked_foundry_lock_changes_are_rejected
assert_chain_mismatch_stops_before_key_extraction
assert_file_contains "$ROOT/.gitignore" 'porep-market-v1/'
assert_file_contains "$ROOT/.gitignore" 'porep-market-v1-*/'
assert_file_contains "$ROOT/.gitignore" 'porep-market-v2-*/'
assert_file_contains "$ROOT/env.v1.example" 'POREP_MARKET_V1_REF=62754c6ceafe0e9f6eae926297633029c95d2589'
assert_file_contains "$ROOT/env.v2.example" 'POREP_MARKET_V2_REF=803942a5f439e0a588da245727197ca22546bb1f'

assert_target_contains porep-v2-proposal-smoke 'scenario -- proposal-smoke'
assert_target_contains porep-v2-validator-rail-smoke 'scenario -- validator-rail-smoke'
assert_target_contains porep-v2-full-happy-path 'porep-v2-e2e-full-available'
assert_target_contains porep-v2-manual-proposal-smoke 'v2/manual/scenarios/proposal_smoke.sh'
assert_target_contains porep-v2-manual-validator-rail-smoke 'v2/manual/scenarios/validator_rail_smoke.sh'
assert_target_contains porep-v2-manual-full-happy-path 'v2/manual/scenarios/full_available_flow.sh'
assert_target_contains porep-script-check 'porep-v2-e2e-install'
assert_target_orders porep-script-check 'porep-v2-e2e-install' 'run typecheck'
assert_target_orders porep-script-check 'porep-v2-e2e-install' 'run test:unit'
assert_file_contains "$ROOT/v1/setup/00_setup.sh" '    require_pinned_repo "PoRep Market V1" "$POREP_DIR" "$REF"'
assert_file_contains "$ROOT/v2/setup/00_setup.sh" '    require_pinned_repo "PoRep Market V2" "$POREP_DIR" "$REF"'
assert_file_contains "$REPO_ROOT/README.md" '## SP Tools (V1 only)'
assert_file_contains "$REPO_ROOT/README.md" 'There is no V2 SP dashboard in this repository.'

for target in \
    porep-v1-devnet-up porep-v1-devnet-check porep-v1-devnet-reset porep-v1-devnet-down \
    porep-v2-e2e-install porep-v2-devnet-up porep-v2-devnet-check porep-v2-devnet-reset porep-v2-devnet-down; do
    assert_target_contains "$target" '.'
done

for target in porep-v1-devnet-up porep-v1-devnet-check porep-v1-devnet-reset porep-v1-devnet-down; do
    assert_target_contains "$target" 'POREP_MARKET_VERSION=v1'
done

for target in porep-v2-e2e-install porep-v2-devnet-up porep-v2-devnet-check porep-v2-devnet-reset porep-v2-devnet-down; do
    assert_target_contains "$target" 'POREP_MARKET_VERSION=v2'
done

assert_target_contains porep-v1-devnet-check 'shared/check_deployment.sh'
assert_target_contains porep-v2-devnet-check 'porep-v2-e2e-preflight'
assert_documented_versioned_targets_exist "$REPO_ROOT/README.md" "$ROOT/README.md"
assert_file_not_contains "$ROOT/README.md" 'just porep-v2-proposal-smoke'
assert_file_not_contains "$ROOT/README.md" 'just porep-v2-validator-rail-smoke'

echo "script layout test: ok"
