#!/usr/bin/env -S nix shell nixpkgs#bash nixpkgs#curl nixpkgs#gh nixpkgs#jq nixpkgs#nix nixpkgs#coreutils --command bash

# Pins pin.nix to a specific (or latest) code-server release and refreshes the per-platform tarball hashes. Run from the flake root:
#
#   nix run .#update-version              # latest GitHub release
#   nix run .#update-version -- 4.121.0   # specific version (no v prefix)
#
# Prefetches all 5 platform tarballs and rewrites pin.nix if anything changed.

set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-${PWD}}"
pin="${FLAKE_ROOT}/pin.nix"
repo_owner=coder
repo_name=code-server

if [[ ! -f "${pin}" ]]; then
  echo "error: no pin.nix in ${FLAKE_ROOT}" >&2
  exit 1
fi

if [[ $# -ge 1 && -n "${1}" ]]; then
  new_version="${1#[Vv]}"
  echo "Using requested version: ${new_version}"
else
  echo "Querying GitHub for latest release of ${repo_owner}/${repo_name}..."
  new_version=$(gh api "/repos/${repo_owner}/${repo_name}/releases/latest" --jq '.tag_name')
  new_version="${new_version#[Vv]}"
fi

cur_version=$(nix eval --raw --file "${pin}" version 2>/dev/null || echo "")
echo "  current: ${cur_version}"
echo "  target:  ${new_version}"

# nix-system => upstream tarball suffix (os-arch).
declare -A platforms=(
  [x86_64-linux]=linux-amd64
  [aarch64-linux]=linux-arm64
  [armv7l-linux]=linux-armv7l
  [x86_64-darwin]=macos-amd64
  [aarch64-darwin]=macos-arm64
)

declare -A new_hashes=()
for nix_system in "${!platforms[@]}"; do
  suffix="${platforms[$nix_system]}"
  url="https://github.com/${repo_owner}/${repo_name}/releases/download/v${new_version}/code-server-${new_version}-${suffix}.tar.gz"
  echo "Prefetching ${nix_system} (${suffix})..."
  # Upstream drops/adds prebuilt targets over time (e.g. linux-armv7l gone as of 4.123.0). A missing
  # asset (404) means this release doesn't ship that platform — skip it rather than failing the bump.
  if out=$(nix store prefetch-file --json --hash-type sha256 "${url}" 2>/dev/null); then
    new_hashes[$nix_system]=$(jq -r '.hash' <<<"${out}")
  else
    echo "  no ${suffix} asset for ${new_version}; dropping ${nix_system} from this release." >&2
  fi
done

if [[ -z "${new_hashes[x86_64-linux]:-}" ]]; then
  echo "error: no linux-amd64 asset for ${new_version}; aborting." >&2
  exit 1
fi

echo "Writing pin.nix..."
{
  echo "# Auto-managed by \`nix run .#update-version\`. Manual edits will be overwritten by the next bump."
  echo "{"
  echo "  version = \"${new_version}\";"
  echo "  hashes = {"
  # Stable platform order; emit only the platforms this release actually shipped.
  for nix_system in x86_64-linux aarch64-linux armv7l-linux x86_64-darwin aarch64-darwin; do
    if [[ -n "${new_hashes[$nix_system]:-}" ]]; then
      printf '    "%s" = "%s";\n' "${nix_system}" "${new_hashes[$nix_system]}"
    fi
  done
  echo "  };"
  echo "}"
} > "${pin}"

echo "Verifying flake evaluates..."
nix eval --raw --file "${pin}" version >/dev/null

echo
echo "Updated to ${new_version}."
echo "  pin.nix updated. Commit to capture."
