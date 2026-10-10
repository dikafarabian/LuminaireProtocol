#!/usr/bin/env bash

# ======================================================
# 🧰 SETUP — Clang Toolchain
# ======================================================

[ "$BUILD_SYSTEM" = "KLEAF" ] && return 0

CLANG_CACHE_DIR="${HOME}/clang-cache"
NEUTRON_HOME="${HOME}/.neutron-tc"
NEUTRON_CACHE_DIR="${CLANG_CACHE_DIR}/.neutron-tc-cache"
UBUNTU_POOL="https://archive.ubuntu.com/ubuntu"
UBUNTU_XML_SUITE="resolute"

clang_cache_usable() {
    [ "${USE_CLANG_CACHE}" = "true" ] && [ -d "${CLANG_CACHE_DIR}/bin" ]
}

restore_clang_cache() {
    log "Restoring Clang from cache (${CLANG_VARIANT})..."
    mkdir -p "$TOOL_CLANG_DIR"
    cp -a "${CLANG_CACHE_DIR}/." "${TOOL_CLANG_DIR}/"
    chmod +x "${TOOL_CLANG_DIR}/bin/"* 2>/dev/null || true
    if [ -d "$NEUTRON_CACHE_DIR" ] && [ ! -d "$NEUTRON_HOME" ]; then
        cp -a "$NEUTRON_CACHE_DIR" "$NEUTRON_HOME"
    fi
}

download_clang() {
    local variant_script="${ROOT_DIR}/setup/clang/${CLANG_VARIANT}.sh"
    [ -f "$variant_script" ] || error "Clang variant script not found: ${CLANG_VARIANT}"
    rm -rf "$TOOL_CLANG_DIR"
    mkdir -p "$TOOL_CLANG_DIR"
    source "$variant_script"
    [ -d "${TOOL_CLANG_DIR}/bin" ] || error "Clang binary missing after download — ${CLANG_VARIANT} script may have failed!"
}

save_clang_cache() {
    rm -rf "$CLANG_CACHE_DIR"
    mkdir -p "$CLANG_CACHE_DIR"
    cp -a "${TOOL_CLANG_DIR}/." "${CLANG_CACHE_DIR}/"
    if [ -d "$NEUTRON_HOME" ]; then
        cp -a "$NEUTRON_HOME" "$NEUTRON_CACHE_DIR"
    fi
}

provide_lld_runtime() {
    local lld_deps tmp stanza deb_path deb_sha
    lld_deps=$(ldd "${TOOL_CLANG_DIR}/bin/ld.lld" 2>&1 || true)
    grep -q "libxml2.so.16 => not found" <<< "$lld_deps" || return 0

    log "Providing libxml2.so.16 for clang..."
    tmp=$(mktemp -d)
    retry 3 run_quiet curl -fL "${UBUNTU_POOL}/dists/${UBUNTU_XML_SUITE}/main/binary-amd64/Packages.gz" \
        -o "${tmp}/Packages.gz" \
        || error "libxml2-16: failed to fetch package index!"
    stanza=$(zcat "${tmp}/Packages.gz" | awk -v RS= '/^Package: libxml2-16\n/')
    deb_path=$(sed -n 's/^Filename: //p' <<< "$stanza")
    deb_sha=$(sed -n 's/^SHA256: //p' <<< "$stanza")
    [ -n "$deb_path" ] && [ -n "$deb_sha" ] || error "libxml2-16: package not found in index!"

    retry 3 run_quiet curl -fL "${UBUNTU_POOL}/${deb_path}" -o "${tmp}/libxml2.deb" \
        || error "libxml2-16: download failed!"
    echo "${deb_sha}  ${tmp}/libxml2.deb" | sha256sum -c --quiet - \
        || error "libxml2-16: checksum mismatch!"
    dpkg -x "${tmp}/libxml2.deb" "${tmp}/root"
    mkdir -p "${TOOL_CLANG_DIR}/lib"
    cp -a "${tmp}"/root/usr/lib/*/libxml2.so.16* "${TOOL_CLANG_DIR}/lib/"
    rm -rf "$tmp"
    "${TOOL_CLANG_DIR}/bin/ld.lld" --version > /dev/null 2>&1 \
        || error "ld.lld still fails after libxml2-16 install!"
    log "libxml2.so.16 ready ✅"
}

CLANG_READY=false
if clang_cache_usable; then
    restore_clang_cache
    if "${TOOL_CLANG_DIR}/bin/clang" --version > /dev/null 2>&1; then
        CLANG_READY=true
        log "Clang restored ✅ ($(cache_freshness_note))"
    else
        warn "Clang binary not executable after cache restore — re-downloading..."
    fi
fi

if [ "$CLANG_READY" != "true" ]; then
    download_clang
    provide_lld_runtime
    save_clang_cache
    log "Clang downloaded and cached ✅"
fi

provide_lld_runtime

set +o pipefail
CLANG_VERSION=$("${TOOL_CLANG_DIR}/bin/clang" --version 2>&1 \
    | grep -oP 'clang version \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
set -o pipefail

case "$CLANG_VARIANT" in
    aosp)    CLANG_BRAND="AOSP Clang" ;;
    cirrus)  CLANG_BRAND="Cirrus Clang" ;;
    neutron) CLANG_BRAND="Neutron Clang" ;;
    weebx)   CLANG_BRAND="WeebX Clang" ;;
    zyc)     CLANG_BRAND="ZyC Clang" ;;
    *)       CLANG_BRAND="${CLANG_VARIANT} Clang" ;;
esac

if [ -n "$CLANG_VERSION" ]; then
    COMPILER_STRING="${CLANG_BRAND} ${CLANG_VERSION}"
else
    COMPILER_STRING="$CLANG_BRAND"
    warn "Could not parse Clang version from --version output"
fi

export COMPILER_STRING
echo "COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
export PATH="${TOOL_CLANG_DIR}/bin:${PATH}"

log "Setting up ccache wrappers..."
mkdir -p "$TOOL_CCACHE_WRAPPERS"

for tool in $(ls "${TOOL_CLANG_DIR}/bin/" | grep -E "^clang(\+\+)?(-[0-9]+)?$"); do
    REAL_BIN="${TOOL_CLANG_DIR}/bin/${tool}"
    WRAPPER="${TOOL_CCACHE_WRAPPERS}/${tool}"
    cat > "$WRAPPER" << WRAPPER_EOF
#!/usr/bin/env bash
exec "${TOOL_CCACHE_BIN}" "${REAL_BIN}" "\$@"
WRAPPER_EOF
    chmod +x "$WRAPPER"
done
export PATH="${TOOL_CCACHE_WRAPPERS}:${PATH}"
echo "${TOOL_CCACHE_WRAPPERS}" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
echo "${TOOL_CLANG_DIR}/bin" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
log "Clang ready | ${COMPILER_STRING} ✅"
