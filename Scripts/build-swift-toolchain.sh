#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SWIFT_SOURCE_DIR="${SWIFT_SOURCE_DIR:-${ROOT}/swift-source}"
SWIFT_BRANCH="${SWIFT_BRANCH:-swift-6.3-RELEASE}"
SWIFT_INSTALL_DIR="${SWIFT_INSTALL_DIR:-${ROOT}/SwiftToolchain-iphoneos}"
SWIFT_BUILD_DIR="${SWIFT_BUILD_DIR:-${ROOT}/swift-build}"
SWIFT_INSTALL_PREFIX="${SWIFT_INSTALL_PREFIX:-/usr}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-14.0}"
IOS_SDK_PATH="${IOS_SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}"
IOS_TARGET_TRIPLE="${IOS_TARGET_TRIPLE:-arm64-apple-ios${IOS_DEPLOYMENT_TARGET}}"
HOST_ARCH="${HOST_ARCH:-$(uname -m)}"
SWIFT_JOBS="${SWIFT_JOBS:-$(sysctl -n hw.ncpu)}"

log() {
    printf '\033[32m\033[1m[*]\033[0m\033[32m %s\033[0m\n' "$*"
}

die() {
    printf '\033[31m\033[1m[!]\033[0m\033[31m %s\033[0m\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  fetch         Clone/update swift-source using SWIFT_BRANCH.
  build         Build and install an iOS arm64 Swift compiler toolchain.
  package       Zip SwiftToolchain-iphoneos into SwiftToolchain.zip.
  install-nyxian
                Unpack SwiftToolchain.zip into ../Shared/SwiftToolchain.
  verify-host   Validate that the packaged toolchain shape exists.

Important environment:
  SWIFT_BRANCH=${SWIFT_BRANCH}
  SWIFT_SOURCE_DIR=${SWIFT_SOURCE_DIR}
  SWIFT_INSTALL_DIR=${SWIFT_INSTALL_DIR}
  SWIFT_BUILD_DIR=${SWIFT_BUILD_DIR}
  IOS_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET}
  IOS_SDK_PATH=${IOS_SDK_PATH}
EOF
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

fetch_swift() {
    require_tool git
    if [[ ! -d "${SWIFT_SOURCE_DIR}/.git" ]]; then
        log "cloning swift ${SWIFT_BRANCH}"
        git clone --branch "${SWIFT_BRANCH}" --depth 1 https://github.com/swiftlang/swift.git "${SWIFT_SOURCE_DIR}"
    else
        log "updating existing swift checkout"
        git -C "${SWIFT_SOURCE_DIR}" fetch --depth 1 origin "${SWIFT_BRANCH}"
        git -C "${SWIFT_SOURCE_DIR}" checkout FETCH_HEAD
    fi

    log "updating Swift sibling checkouts for ${SWIFT_BRANCH}"
    "${SWIFT_SOURCE_DIR}/utils/update-checkout" --clone --tag "${SWIFT_BRANCH}"
}

build_swift() {
    require_tool cmake
    require_tool ninja
    require_tool xcrun

    [[ -x "${SWIFT_SOURCE_DIR}/utils/build-script" ]] || die "missing ${SWIFT_SOURCE_DIR}/utils/build-script; run make swift-source first"
    [[ -d "${IOS_SDK_PATH}" ]] || die "missing iPhoneOS SDK at ${IOS_SDK_PATH}"

    rm -rf "${SWIFT_INSTALL_DIR}"
    mkdir -p "${SWIFT_INSTALL_DIR}" "${SWIFT_BUILD_DIR}"

    log "building Swift toolchain for ${IOS_TARGET_TRIPLE}"
    log "this invokes Swift's build system; expect a long build"

    (
        cd "${SWIFT_SOURCE_DIR}"
        utils/build-script \
            --release-debuginfo \
            --skip-build-benchmarks \
            --skip-test-swift \
            --skip-test-cmark \
            --skip-test-lldb \
            --skip-test-llbuild \
            --skip-test-swiftpm \
            --build-subdir "${SWIFT_BUILD_DIR}" \
            --install-destdir "${SWIFT_INSTALL_DIR}" \
            --install-prefix "${SWIFT_INSTALL_PREFIX}" \
            --install-swift \
            --install-llvm \
            --installable-package "${ROOT}/SwiftToolchain-iphoneos.tar.gz" \
            --ios \
            --swift-primary-variant-sdk IOS \
            --swift-darwin-supported-arch "${HOST_ARCH}" \
            --swift-darwin-supported-arch arm64 \
            --swift-stdlib-build-type Release \
            --llvm-targets-to-build "AArch64" \
            "--swift-install-components=compiler;stdlib;sdk-overlay;clang-resource-dir-symlink;license;toolchain-tools" \
            "--llvm-install-components=clang;clang-resource-headers;compiler-rt;LTO;llvm-ar;llvm-ranlib;llvm-nm;llvm-objdump;llvm-profdata" \
            -- \
            --build-ninja \
            --extra-cmake-options="-DCMAKE_OSX_SYSROOT=${IOS_SDK_PATH}" \
            --extra-cmake-options="-DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET}" \
            --extra-cmake-options="-DCMAKE_SYSTEM_NAME=iOS" \
            --extra-cmake-options="-DCMAKE_OSX_ARCHITECTURES=arm64"
    )

    normalize_install_layout
    verify_host
}

normalize_install_layout() {
    if [[ -d "${SWIFT_INSTALL_DIR}${SWIFT_INSTALL_PREFIX}" && "${SWIFT_INSTALL_PREFIX}" != "/" ]]; then
        rm -rf "${SWIFT_INSTALL_DIR}/.normalized"
        mkdir -p "${SWIFT_INSTALL_DIR}/.normalized"
        cp -a "${SWIFT_INSTALL_DIR}${SWIFT_INSTALL_PREFIX}/." "${SWIFT_INSTALL_DIR}/.normalized/"
        find "${SWIFT_INSTALL_DIR}" -mindepth 1 -maxdepth 1 ! -name .normalized -exec rm -rf {} +
        cp -a "${SWIFT_INSTALL_DIR}/.normalized/." "${SWIFT_INSTALL_DIR}/"
        rm -rf "${SWIFT_INSTALL_DIR}/.normalized"
    fi
}

verify_host() {
    [[ -x "${SWIFT_INSTALL_DIR}/bin/swiftc" ]] || die "missing ${SWIFT_INSTALL_DIR}/bin/swiftc"
    [[ -x "${SWIFT_INSTALL_DIR}/bin/swift-frontend" ]] || die "missing ${SWIFT_INSTALL_DIR}/bin/swift-frontend"
    [[ -d "${SWIFT_INSTALL_DIR}/lib/swift" ]] || die "missing ${SWIFT_INSTALL_DIR}/lib/swift"
    log "toolchain shape is valid"
}

package_swift() {
    require_tool zip
    verify_host

    rm -rf "${ROOT}/SwiftToolchain"
    mkdir -p "${ROOT}/SwiftToolchain/usr"
    cp -a "${SWIFT_INSTALL_DIR}/." "${ROOT}/SwiftToolchain/usr/"

    rm -f "${ROOT}/SwiftToolchain.zip"
    (
        cd "${ROOT}"
        zip -qry SwiftToolchain.zip SwiftToolchain
    )
    log "created ${ROOT}/SwiftToolchain.zip"
}

install_nyxian() {
    require_tool unzip
    [[ -f "${ROOT}/SwiftToolchain.zip" ]] || die "missing ${ROOT}/SwiftToolchain.zip; run make swift-toolchain first"

    local nyxian_shared="${NYXIAN_SHARED_DIR:-${ROOT}/../Shared}"
    [[ -d "${nyxian_shared}" ]] || die "missing Nyxian Shared directory at ${nyxian_shared}"

    rm -rf "${nyxian_shared}/SwiftToolchain"
    unzip -q "${ROOT}/SwiftToolchain.zip" -d "${nyxian_shared}"
    log "installed SwiftToolchain into ${nyxian_shared}/SwiftToolchain"
}

case "${1:-}" in
    fetch)
        fetch_swift
        ;;
    build)
        build_swift
        ;;
    package)
        package_swift
        ;;
    install-nyxian)
        install_nyxian
        ;;
    verify-host)
        verify_host
        ;;
    ""|-h|--help|help)
        usage
        ;;
    *)
        usage
        die "unknown command: $1"
        ;;
esac
