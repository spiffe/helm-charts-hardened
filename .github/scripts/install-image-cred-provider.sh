#!/usr/bin/env bash
# Stage the SPIRE Identity Exchange kubelet image credential provider for kind.
#
# .github/kind/conf/kind-config.yaml points kubelet at this binary with
# --image-credential-provider-bin-dir and --image-credential-provider-config. Kubelet
# refuses to start when the bin dir, or any provider binary named in the config, is
# missing. That makes this a prerequisite for EVERY cluster built from that config, not
# just the ones that pull from the bottom-turtle-ha test registry, so run it before
# `kind create cluster`.

set -euo pipefail

VERSION="${IMAGE_CRED_PROVIDER_VERSION:-v0.5.0}"
BIN_NAME="k8s-image-cred-spire-identity-exchange"

SCRIPTPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPTPATH}/../kind/conf/credential-providers"

case "$(uname -m)" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ -x "${BIN_DIR}/${BIN_NAME}" ]; then
  echo "${BIN_NAME} already staged in ${BIN_DIR}"
  exit 0
fi

BASE_URL="https://github.com/spiffe/spire-identity-exchange/releases/download/${VERSION}"
ARCHIVE="${BIN_NAME}_Linux_${ARCH}.tar.gz"
# goreleaser drops the leading v from the checksums file name
CHECKSUMS="spire-identity-exchange_${VERSION#v}_checksums.txt"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

curl -fsSL --retry 5 --retry-all-errors -o "${WORKDIR}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"
curl -fsSL --retry 5 --retry-all-errors -o "${WORKDIR}/${CHECKSUMS}" "${BASE_URL}/${CHECKSUMS}"
(cd "${WORKDIR}" && grep " ${ARCHIVE}\$" "${CHECKSUMS}" | sha256sum -c -)

tar -xzf "${WORKDIR}/${ARCHIVE}" -C "${WORKDIR}" "${BIN_NAME}"
mkdir -p "${BIN_DIR}"
install -m 0755 "${WORKDIR}/${BIN_NAME}" "${BIN_DIR}/${BIN_NAME}"

echo "Staged ${BIN_NAME} ${VERSION} in ${BIN_DIR}"
