#!/bin/sh
set -eu

REPO="tontinton/maki"
BINARY="maki"
TARGET="aarch64-linux-android"

github_curl() {
    token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -n "${token}" ]; then
        curl -fsSL \
            -H "Authorization: Bearer ${token}" \
            -H "Accept: application/vnd.github+json" \
            -H "User-Agent: maki-termux-install" \
            "$@"
    else
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "User-Agent: maki-termux-install" \
            "$@"
    fi
}

latest_tag() {
    github_curl "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1
}

main() {
    need_cmd curl
    need_cmd tar
    need_cmd sha256sum

    [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}" ] || err "this installer must run inside Termux"

    case "$(uname -m)" in
        aarch64|arm64) ;;
        *) err "unsupported architecture: $(uname -m) (only ARM64 Termux is supported)" ;;
    esac

    install_dir="${MAKI_INSTALL_DIR:-${PREFIX}/bin}"
    tag="${1:-$(latest_tag)}"
    [ -n "${tag}" ] || err "failed to determine latest release tag"

    archive="${BINARY}-${tag}-${TARGET}.tar.gz"
    base_url="https://github.com/${REPO}/releases/download/${tag}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT HUP INT TERM

    echo "downloading ${BINARY} ${tag} for Termux..."
    github_curl "${base_url}/${archive}" -o "${tmp}/${archive}"
    github_curl "${base_url}/sha256sums.txt" -o "${tmp}/sha256sums.txt"

    expected="$(awk -v archive="${archive}" '$2 == archive || $2 == "*" archive { print $1; exit }' "${tmp}/sha256sums.txt")"
    [ -n "${expected}" ] || err "checksum for ${archive} not found"
    actual="$(sha256sum "${tmp}/${archive}" | awk '{ print $1 }')"
    [ "${actual}" = "${expected}" ] || err "checksum verification failed for ${archive}"

    tar xzf "${tmp}/${archive}" -C "${tmp}"
    [ -f "${tmp}/${BINARY}" ] || err "archive did not contain ${BINARY}"
    [ -f "${tmp}/libc++_shared.so" ] || err "archive did not contain libc++_shared.so"

    mkdir -p "${install_dir}"
    runtime_dir="${install_dir}/.${BINARY}"
    staged_runtime="${install_dir}/.${BINARY}.new.$$"
    staged_launcher="${install_dir}/.${BINARY}.launcher.$$"
    mkdir "${staged_runtime}"
    cp "${tmp}/${BINARY}" "${tmp}/libc++_shared.so" "${staged_runtime}/"
    chmod +x "${staged_runtime}/${BINARY}"
    cat > "${staged_launcher}" <<'EOF'
#!/bin/sh
install_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="${install_dir}/.maki${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${install_dir}/.maki/maki" "$@"
EOF
    chmod +x "${staged_launcher}"
    rm -rf "${runtime_dir}"
    mv "${staged_runtime}" "${runtime_dir}"
    mv "${staged_launcher}" "${install_dir}/${BINARY}"

    echo "${BINARY} ${tag} installed to ${install_dir}/${BINARY}"
}

need_cmd() {
    command -v "$1" > /dev/null 2>&1 || err "need '$1' (not found)"
}

err() {
    echo "error: $1" >&2
    exit 1
}

main "$@"
