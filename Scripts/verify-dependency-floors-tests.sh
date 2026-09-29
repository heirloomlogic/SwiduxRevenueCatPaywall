#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
floor_script="$repository_root/Scripts/verify-dependency-floors.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dependency-floor-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

fixture="$test_root/fixture"
mkdir -p "$fixture/Sources/Fixture" "$test_root/bin" "$test_root/observations" "$test_root/tmp"

printf 'public struct Fixture {}\n' > "$fixture/Sources/Fixture/Fixture.swift"
printf 'original lockfile\n' > "$fixture/Package.resolved"
printf 'ignored local tooling\n' > "$fixture/.dev-tooling"

cat > "$fixture/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Fixture",
    dependencies: [
        .package(url: "https://example.com/dependency", from: "1.2.3"),
    ],
    targets: [
        .target(name: "Fixture", dependencies: [.product(name: "Dependency", package: "dependency")]),
    ]
)
SWIFT

(
    cd "$fixture"
    git init -q
    git add Package.swift Package.resolved Sources
)

cat > "$test_root/bin/swift" <<'SH'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "$FLOOR_TEST_OBSERVATION_DIR/invocations"

case "$*" in
    "package resolve")
        grep -Fq '.package(url: "https://example.com/dependency", exact: "1.2.3")' Package.swift
        if grep -Fq 'from: "1.2.3"' Package.swift; then
            printf 'floor requirement was not replaced\n' >&2
            exit 1
        fi
        if [[ -e Package.resolved ]]; then
            printf 'the tracked lockfile was present before fresh resolution\n' >&2
            exit 1
        fi
        if [[ -e .dev-tooling ]]; then
            printf 'untracked dev tooling was copied\n' >&2
            exit 1
        fi
        cp Package.swift "$FLOOR_TEST_OBSERVATION_DIR/resolved-Package.swift"
        printf 'fresh lockfile\n' > Package.resolved
        ;;
    "build --build-tests")
        grep -Fq 'fresh lockfile' Package.resolved
        touch "$FLOOR_TEST_OBSERVATION_DIR/built"
        ;;
    *)
        printf 'unexpected swift invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
SH
chmod +x "$test_root/bin/swift"

manifest_before="$(shasum -a 256 "$fixture/Package.swift")"
lock_before="$(shasum -a 256 "$fixture/Package.resolved")"

FLOOR_TEST_OBSERVATION_DIR="$test_root/observations" PATH="$test_root/bin:$PATH" TMPDIR="$test_root/tmp" "$floor_script" "$fixture"

[[ -f "$test_root/observations/built" ]] || fail "the temporary package was not built with tests"
[[ "$(cat "$test_root/observations/invocations")" == $'package resolve\nbuild --build-tests' ]] || fail "resolve and build did not run in order"
[[ "$(shasum -a 256 "$fixture/Package.swift")" == "$manifest_before" ]] || fail "the source manifest changed"
[[ "$(shasum -a 256 "$fixture/Package.resolved")" == "$lock_before" ]] || fail "the source lockfile changed"
if find "$test_root/tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "the temporary package copy was not removed"
fi

exact_fixture="$test_root/exact-fixture"
mkdir -p "$exact_fixture"
sed 's/from: "1.2.3"/exact: "1.2.3"/' "$fixture/Package.swift" > "$exact_fixture/Package.swift"
(
    cd "$exact_fixture"
    git init -q
    git add Package.swift
)

if FLOOR_TEST_OBSERVATION_DIR="$test_root/observations" PATH="$test_root/bin:$PATH" TMPDIR="$test_root/tmp" "$floor_script" "$exact_fixture" > "$test_root/no-floor-output" 2>&1; then
    fail "a manifest without from requirements was accepted"
fi
grep -Fq 'no from: dependency requirements found' "$test_root/no-floor-output" || fail "the missing-floor error was unclear"

printf 'Dependency floor script tests passed.\n'
