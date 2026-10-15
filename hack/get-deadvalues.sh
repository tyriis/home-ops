#!/usr/bin/env bash

# Download the pinned deadvalues release into hack/bin/ with sha256 verification.
#
# deadvalues is a single static Go binary (Helm values dead-code checker):
# https://github.com/guarnz/deadvalues
#
# Idempotent: exits early when hack/bin/deadvalues already reports the pinned
# version. Verification: the checksums.txt from the release is checked against
# a pinned sha256, and the tarball is checked against the entry inside it.

set -euo pipefail

VERSION="v0.1.4"
BASE_URL="https://github.com/guarnz/deadvalues/releases/download/${VERSION}"
CHECKSUMS_SHA256="1626fe3dc774cdbb37c95b54506f612126a494a9f9fda7c29455aa4e7d6c7824"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${script_dir}/bin"
target="${bin_dir}/deadvalues"

# Map the current platform to the release asset naming.
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "${os}" in
  linux) os="linux" ;;
  darwin) os="darwin" ;;
  *)
    echo "unsupported OS: ${os}" >&2
    exit 1
    ;;
esac

arch="$(uname -m)"
case "${arch}" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *)
    echo "unsupported architecture: ${arch}" >&2
    exit 1
    ;;
esac

asset="deadvalues_${os}_${arch}.tar.gz"

# Idempotency: reuse an already-installed binary of the pinned version.
if [[ -x "${target}" ]] && "${target}" --version 2>/dev/null | grep -qF "${VERSION}"; then
  echo "deadvalues ${VERSION} already installed at ${target}"
  exit 0
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256_cmd() { sha256sum "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_cmd() { shasum -a 256 "$@"; }
else
  echo "sha256sum or shasum is required" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "downloading ${BASE_URL}/checksums.txt"
# --proto/--proto-redir keep the transfer on HTTPS even across redirects (Sonar S6506).
curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' -o "${tmp_dir}/checksums.txt" "${BASE_URL}/checksums.txt"

expected="$(sha256_cmd "${tmp_dir}/checksums.txt" | awk '{print $1}')"
if [[ "${expected}" != "${CHECKSUMS_SHA256}" ]]; then
  echo "checksums.txt sha256 mismatch: got ${expected}, want ${CHECKSUMS_SHA256}" >&2
  exit 1
fi

asset_sha="$(awk -v asset="${asset}" '$2 == asset {print $1}' "${tmp_dir}/checksums.txt")"
if [[ -z "${asset_sha}" ]]; then
  echo "asset ${asset} not found in checksums.txt" >&2
  exit 1
fi

echo "downloading ${BASE_URL}/${asset}"
curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' -o "${tmp_dir}/${asset}" "${BASE_URL}/${asset}"

echo "${asset_sha}  ${tmp_dir}/${asset}" | sha256_cmd -c -

echo "extracting to ${bin_dir}"
mkdir -p "${bin_dir}"
tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"
mv "${tmp_dir}/deadvalues" "${target}"
chmod 0755 "${target}"

"${target}" --version
echo "deadvalues ${VERSION} installed at ${target}"
