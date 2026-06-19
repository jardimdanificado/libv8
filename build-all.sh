#!/usr/bin/env bash
# Build all Wagnostic dependency archives for every supported platform.
#
# Requires: Docker (for cross-compilation containers), zip, curl
# Usage: ./build-all.sh [output_dir]
#   output_dir: where to place the archives (default: build-output)

set -euo pipefail
OUTDIR="${1:-build-output}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUTDIR"

PLATFORMS=(
    linux-x86_64
    linux-i686
    linux-aarch64
    linux-armv7
    # macos-x86_64    # Uncomment on macOS or Docker with osxcross
    # macos-arm64     # Uncomment on Apple Silicon or Docker with osxcross
    windows-x86_64
    windows-i686
)

echo "============================================"
echo " Wagnostic - Build All Library Archives"
echo " Output: $OUTDIR"
echo " Platforms: ${PLATFORMS[*]}"
echo "============================================"
echo ""

for platform in "${PLATFORMS[@]}"; do
    echo ""
    echo "============================================"
    echo " Building: $platform"
    echo "============================================"

    case "$platform" in
        linux-x86_64)
            # Native
            bash "$SCRIPT_DIR/build.sh" "$platform" "$OUTDIR"
            ;;
        linux-i686)
            # 32-bit cross
            docker run --rm -v "$(pwd):/build" -w /build \
                multiarch/ubuntu-debootstrap:i386-jammy \
                bash -c "apt-get update -qq && apt-get install -y -qq curl zip ca-certificates gcc libc6-dev && bash build-libs/build.sh linux-i686 /build/build-output" \
                2>&1 | tail -5 || echo "  ⚠ Cross-build failed for $platform"
            ;;
        linux-aarch64)
            docker run --rm -v "$(pwd):/build" -w /build \
                multiarch/ubuntu-debootstrap:arm64-jammy \
                bash -c "apt-get update -qq && apt-get install -y -qq curl zip ca-certificates gcc libc6-dev && bash build-libs/build.sh linux-aarch64 /build/build-output" \
                2>&1 | tail -5 || echo "  ⚠ Cross-build failed for $platform"
            ;;
        linux-armv7)
            docker run --rm -v "$(pwd):/build" -w /build \
                multiarch/ubuntu-debootstrap:armhf-jammy \
                bash -c "apt-get update -qq && apt-get install -y -qq curl zip ca-certificates gcc libc6-dev && bash build-libs/build.sh linux-armv7 /build/build-output" \
                2>&1 | tail -5 || echo "  ⚠ Cross-build failed for $platform"
            ;;
        windows-x86_64 | windows-i686)
            # Windows cross via mingw
            docker run --rm -v "$(pwd):/build" -w /build \
                archlinux:latest \
                bash -c "pacman -Sy --noconfirm curl zip ca-certificates mingw-w64-gcc && bash build-libs/build.sh $platform /build/build-output" \
                2>&1 | tail -5 || echo "  ⚠ Cross-build failed for $platform"
            ;;
        macos-*)
            echo "  ⚠ macOS builds require a macOS runner (osxcross or native)"
            ;;
    esac
done

echo ""
echo "============================================"
echo " All builds complete!"
echo " Archives in: $OUTDIR/"
ls -lh "$OUTDIR"/wagnostic-libs-*.zip "$OUTDIR"/wagnostic-libs-*.tar.gz 2>/dev/null || echo "   (no archives found)"
echo "============================================"
