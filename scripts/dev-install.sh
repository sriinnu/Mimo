#!/usr/bin/env bash
# dev-install.sh — Build Mimo locally and install to /Applications.
#
# Single-command dev loop: regenerate the Xcode project, build a fresh Debug
# binary, kill any running Mimo, swap /Applications/Mimo.app, relaunch.
# Singleton enforcement in AppDelegate guarantees only one Mimo survives the swap.
#
# Usage:
#   scripts/dev-install.sh             # Debug build (default)
#   scripts/dev-install.sh --release   # Release build (unsigned — for local perf testing only)
#   scripts/dev-install.sh --no-launch # Build + install, don't open the app
#
# This is for local development. Real shipped releases go through .github/workflows/release.yml
# (sign + notarize + DMG attached to a GitHub Release).

set -euo pipefail

CONFIGURATION="Debug"
LAUNCH_AFTER_INSTALL=true

for arg in "$@"; do
    case "$arg" in
        --release)   CONFIGURATION="Release" ;;
        --no-launch) LAUNCH_AFTER_INSTALL=false ;;
        --help|-h)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Run with --help for usage." >&2
            exit 64
            ;;
    esac
done

# ─── Resolve repo root regardless of where this is invoked from ─────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ─── Sanity-check the toolchain ─────────────────────────────────────────
command -v tuist >/dev/null 2>&1 || {
    echo "ERROR: tuist not on PATH. Install: brew install tuist" >&2
    exit 2
}
command -v xcodebuild >/dev/null 2>&1 || {
    echo "ERROR: xcodebuild not on PATH. Install Xcode + Command Line Tools." >&2
    exit 2
}

# ─── 1. Generate Xcode project ──────────────────────────────────────────
echo "==> tuist generate"
tuist generate --no-open >/dev/null

# ─── 2. Build ───────────────────────────────────────────────────────────
echo "==> xcodebuild (${CONFIGURATION})"
xcodebuild \
    -workspace Mimo.xcworkspace \
    -scheme Mimo \
    -configuration "${CONFIGURATION}" \
    -destination 'platform=macOS' \
    -quiet \
    build \
    CODE_SIGNING_ALLOWED=NO \
    >/dev/null

# ─── 3. Locate the built .app ───────────────────────────────────────────
BUILT_APP=$(
    find ~/Library/Developer/Xcode/DerivedData \
        -path "*Build/Products/${CONFIGURATION}/Mimo.app" \
        -type d \
        2>/dev/null | head -1
)
if [[ -z "${BUILT_APP}" ]]; then
    echo "ERROR: couldn't find built Mimo.app in DerivedData." >&2
    exit 3
fi
echo "==> built at: ${BUILT_APP}"

# ─── 4. Kill running Mimo (singleton enforcement will block a duplicate anyway) ─
pkill -f "Mimo.app/Contents/MacOS/Mimo" 2>/dev/null && {
    echo "==> killed running Mimo"
    sleep 1
} || true

# ─── 5. Swap /Applications/Mimo.app ─────────────────────────────────────
INSTALL_PATH="/Applications/Mimo.app"
if [[ -e "${INSTALL_PATH}" ]]; then
    rm -rf "${INSTALL_PATH}"
fi
cp -R "${BUILT_APP}" "${INSTALL_PATH}"
xattr -dr com.apple.quarantine "${INSTALL_PATH}" 2>/dev/null || true
echo "==> installed at: ${INSTALL_PATH}"

# ─── 6. Launch (optional) ───────────────────────────────────────────────
if [[ "${LAUNCH_AFTER_INSTALL}" == "true" ]]; then
    open "${INSTALL_PATH}"
    sleep 1
    VERSION=$(defaults read "${INSTALL_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
    BUILD=$(defaults read "${INSTALL_PATH}/Contents/Info" CFBundleVersion 2>/dev/null || echo "?")
    echo "==> Mimo v${VERSION} (build ${BUILD}) launched"
else
    echo "==> launch skipped (--no-launch)"
fi
