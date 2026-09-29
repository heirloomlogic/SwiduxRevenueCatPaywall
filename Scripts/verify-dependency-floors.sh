#!/bin/bash

set -euo pipefail

package_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
package_root="$(cd "$package_root" && pwd -P)"

if [[ ! -f "$package_root/Package.swift" ]]; then
    printf 'Package.swift not found in %s\n' "$package_root" >&2
    exit 64
fi

if ! git -C "$package_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s is not a Git working tree\n' "$package_root" >&2
    exit 64
fi

temporary_package="$(mktemp -d "${TMPDIR:-/tmp}/dependency-floor.XXXXXX")"
trap 'rm -rf "$temporary_package"' EXIT

while IFS= read -r -d '' relative_path; do
    mkdir -p "$temporary_package/$(dirname "$relative_path")"
    cp -p "$package_root/$relative_path" "$temporary_package/$relative_path"
done < <(git -C "$package_root" ls-files -z -- .)

perl -0pi -e '$count = s{(\.package\s*\(\s*url\s*:\s*"[^"]+"\s*,\s*)from(\s*:\s*"[^"]+"\s*\))}{$1exact$2}g; die "no from: dependency requirements found\n" unless $count;' "$temporary_package/Package.swift"

rm -f "$temporary_package/Package.resolved"

printf 'Testing exact dependency floors from Package.swift:\n'
perl -ne 'while (/\.package\s*\(\s*url\s*:\s*"([^"]+)"\s*,\s*exact\s*:\s*"([^"]+)"/g) { printf "  %s @ %s\n", $1, $2 }' "$temporary_package/Package.swift"

cd "$temporary_package"
swift package resolve
swift build --build-tests
