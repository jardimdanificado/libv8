#!/usr/bin/env bash
# Wagnostic - Build Runtime Dependencies
# Downloads/compiles all libraries needed by Wagnostic runners
# and packs them into per-platform archives.
#
# Usage: ./build.sh <platform> [output_dir]
#   platform: linux-x86_64 | linux-i686 | linux-aarch64 | linux-armv7 |
#             macos-x86_64 | macos-arm64 |
#             windows-x86_64 | windows-i686
#
# Output: a zip file with the following structure:
#   wagnostic-libs-<platform>.zip
#   ├── wasmtime/
#   │   ├── include/      # wasmtime.h, wasm.h, wasi.h
#   │   └── lib/          # libwasmtime.so / .dll / .dylib
#   ├── v8/
#   │   ├── include/      # v8.h, v8-*.h, libplatform/
#   │   └── lib/          # libv8_monolith.a
#   ├── sdl2/
#   │   ├── include/      # SDL.h, SDL_*.h
#   │   └── lib/          # libSDL2.so / SDL2.lib / SDL2.dll
#   └── wasm3/
#       ├── include/      # wasm3.h, m3_*.h
#       └── lib/          # libwasm3.a

set -euo pipefail

PLATFORM="${1:?Usage: ./build.sh <platform> [output_dir]}"
OUTDIR="${2:-build-output}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$OUTDIR/work-$PLATFORM"
DISTDIR="$OUTDIR/wagnostic-libs-$PLATFORM"

# ---------- platform map ----------
case "$PLATFORM" in
    linux-x86_64)
        WASMTIME_ARCH="x86_64-linux"
        V8_TARGET="x64"
        V8_OS="linux"
        SDL_PLATFORM="linux-x86_64"; SDL_EXT="tar.gz"
        BUILD_CC="gcc"; BUILD_CXX="g++"
        ;;
    linux-i686)
        WASMTIME_ARCH="x86_64-linux"  # no i686 prebuilt
        V8_TARGET="x86"
        V8_OS="linux"
        SDL_PLATFORM="linux-i686"; SDL_EXT="tar.gz"
        BUILD_CC="gcc -m32"; BUILD_CXX="g++ -m32"
        ;;
    linux-aarch64)
        WASMTIME_ARCH="aarch64-linux"
        V8_TARGET="arm64"
        V8_OS="linux"
        SDL_PLATFORM="linux-aarch64"; SDL_EXT="tar.gz"
        BUILD_CC="aarch64-linux-gnu-gcc"; BUILD_CXX="aarch64-linux-gnu-g++"
        ;;
    linux-armv7)
        WASMTIME_ARCH="armv7-linux"   # may not exist
        V8_TARGET="arm"
        V8_OS="linux"
        SDL_PLATFORM="linux-armv7"; SDL_EXT="tar.gz"
        BUILD_CC="arm-linux-gnueabihf-gcc"; BUILD_CXX="arm-linux-gnueabihf-g++"
        ;;
    macos-x86_64)
        WASMTIME_ARCH="x86_64-macos"
        V8_TARGET="x64"
        V8_OS="mac"
        SDL_PLATFORM="macos-x86_64"; SDL_EXT="dmg"
        BUILD_CC="clang"; BUILD_CXX="clang++"
        ;;
    macos-arm64)
        WASMTIME_ARCH="aarch64-macos"
        V8_TARGET="arm64"
        V8_OS="mac"
        SDL_PLATFORM="macos-arm64"; SDL_EXT="dmg"
        BUILD_CC="clang"; BUILD_CXX="clang++"
        ;;
    windows-x86_64)
        WASMTIME_ARCH="x86_64-windows"
        V8_TARGET="x64"
        V8_OS="win"
        SDL_PLATFORM="windows-x86_64"; SDL_EXT="zip"
        BUILD_CC="x86_64-w64-mingw32-gcc"; BUILD_CXX="x86_64-w64-mingw32-g++"
        ;;
    windows-i686)
        WASMTIME_ARCH="x86_64-windows"  # no i686 prebuilt
        V8_TARGET="x86"
        V8_OS="win"
        SDL_PLATFORM="windows-i686"; SDL_EXT="zip"
        BUILD_CC="i686-w64-mingw32-gcc"; BUILD_CXX="i686-w64-mingw32-g++"
        ;;
    *)
        echo "ERROR: Unknown platform '$PLATFORM'"
        echo "Valid: linux-x86_64, linux-i686, linux-aarch64, linux-armv7, macos-x86_64, macos-arm64, windows-x86_64, windows-i686"
        exit 1
        ;;
esac

WASMTIME_VERSION="30.0.1"
SDL_VERSION="2.30.9"
WASM3_VERSION="0.5.0"
V8_VERSION="13.5.0"  # must match depot_tools tag

echo "============================================"
echo " Wagnostic Build Libs"
echo " Platform:    $PLATFORM"
echo " Output:      $DISTDIR"
echo "============================================"

rm -rf "$WORKDIR" "$DISTDIR"
mkdir -p "$WORKDIR" "$DISTDIR"/{wasmtime/{include,lib},v8/{include,lib},sdl2/{include,lib},wasm3/{include,lib}}

# ============================================================
# 1. Wasm3 — build from upstream source (manual compile)
# ============================================================
echo "[1/4] Building wasm3 v$WASM3_VERSION..."
WASM3_REPO="$WORKDIR/wasm3-source"
if [ ! -d "$WASM3_REPO" ]; then
    git clone --depth 1 --branch "v${WASM3_VERSION}" \
        https://github.com/wasm3/wasm3.git "$WASM3_REPO" 2>&1 | tail -1
fi

# Compile wasm3 manually (no cmake needed)
WASM3_BUILD="$WORKDIR/wasm3-build"
mkdir -p "$WASM3_BUILD"

# Compile all wasm3 source files
WASM3_SRCS=(
    m3_api_libc.c
    m3_bind.c
    m3_code.c
    m3_compile.c
    m3_core.c
    m3_env.c
    m3_exec.c
    m3_function.c
    m3_info.c
    m3_module.c
    m3_parse.c
)

cd "$WASM3_BUILD"
for src in "${WASM3_SRCS[@]}"; do
    $BUILD_CC -c -O2 -I"$WASM3_REPO/source" "$WASM3_REPO/source/$src" -o "${src%.c}.o" 2>&1 | grep -v "^$" || true
done

# Create static library
ar rcs libwasm3.a *.o 2>&1 | tail -1

# Copy artifacts
cp "$WASM3_REPO/source/"*.h "$DISTDIR/wasm3/include/"
cp "$WASM3_REPO/source/m3_config.h" "$DISTDIR/wasm3/include/" 2>/dev/null || true
cp libwasm3.a "$DISTDIR/wasm3/lib/"
echo "  ✓ wasm3 $(ls "$DISTDIR/wasm3/lib/" 2>/dev/null)"

# ============================================================
# 2. Wasmtime C API — prebuilt download
# ============================================================
echo "[2/4] Downloading Wasmtime C API v$WASMTIME_VERSION..."
WASMTIME_URL="https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/wasmtime-v${WASMTIME_VERSION}-${WASMTIME_ARCH}-c-api"
case "$PLATFORM" in
    linux-*|macos-*)  WASMTIME_URL="${WASMTIME_URL}.tar.xz"; WASMTIME_FILE="wasmtime.tar.xz" ;;
    windows-*)        WASMTIME_URL="${WASMTIME_URL}.zip";   WASMTIME_FILE="wasmtime.zip" ;;
esac

if curl -sL "$WASMTIME_URL" --max-time 120 -o "$WORKDIR/$WASMTIME_FILE" 2>/dev/null; then
    case "$PLATFORM" in
        linux-*|macos-*) tar xf "$WORKDIR/$WASMTIME_FILE" -C "$WORKDIR" ;;
        windows-*)       unzip -q "$WORKDIR/$WASMTIME_FILE" -d "$WORKDIR" ;;
    esac
    WT_DIR=$(find "$WORKDIR" -maxdepth 1 -type d -name "wasmtime*" | head -1)
    if [ -n "$WT_DIR" ]; then
        cp -r "$WT_DIR/include/"* "$DISTDIR/wasmtime/include/"
        cp "$WT_DIR/lib/"* "$DISTDIR/wasmtime/lib/" 2>/dev/null || true
        echo "  ✓ Wasmtime ($(ls "$DISTDIR/wasmtime/lib/" | tr '\n' ' '))"
    fi
else
    echo "  ⚠ Wasmtime download failed for $WASMTIME_ARCH"
    echo "not available" > "$DISTDIR/wasmtime/NOT_AVAILABLE"
fi

# ============================================================
# 3. V8 — build from source
# ============================================================
echo "[3/4] Building V8 v$V8_VERSION from source..."

V8_SRC="$WORKDIR/v8"
install_depot_tools() {
    if [ ! -d "$WORKDIR/depot_tools" ]; then
        git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git \
            "$WORKDIR/depot_tools" 2>&1 | tail -1
    fi
    export PATH="$WORKDIR/depot_tools:$PATH"
}

fetch_v8() {
    cd "$WORKDIR"
    if [ ! -d "$V8_SRC/.git" ]; then
        fetch v8 2>&1 | tail -3
    fi
    cd "$V8_SRC"
    git checkout "refs/tags/${V8_VERSION}" 2>/dev/null || \
        git checkout "refs/tags/${V8_VERSION}.0" 2>/dev/null || \
        echo "  ⚠ V8 tag $V8_VERSION not found, using HEAD"
    gclient sync 2>&1 | tail -2
}

build_v8() {
    cd "$V8_SRC"
    gn gen "out/Release" --args="
        is_debug=false
        target_cpu=\"$V8_TARGET\"
        target_os=\"$V8_OS\"
        v8_monolithic=true
        v8_use_external_startup_data=false
        use_custom_libcxx=false
        treat_warnings_as_errors=false
        use_sysroot=false
    " 2>&1 | tail -2

    ninja -C "out/Release" v8_monolith 2>&1 | tail -3
}

if command -v fetch &>/dev/null || command -v gclient &>/dev/null; then
    # depot_tools already in PATH
    :
else
    install_depot_tools
fi

if command -v fetch &>/dev/null; then
    fetch_v8
    build_v8

    # Copy artifacts
    cp -r "$V8_SRC/include/"* "$DISTDIR/v8/include/"
    cp "$V8_SRC/out/Release/obj/libv8_monolith.a" "$DISTDIR/v8/lib/" 2>/dev/null || \
    cp "$V8_SRC/out/Release/obj/v8_monolith/libv8_monolith.a" "$DISTDIR/v8/lib/" 2>/dev/null || true
    find "$V8_SRC/out/Release" -name "libv8_monolith*" -exec cp {} "$DISTDIR/v8/lib/" \; 2>/dev/null || true

    if [ -f "$DISTDIR/v8/lib/libv8_monolith.a" ]; then
        echo "  ✓ V8 monolith ($(du -h "$DISTDIR/v8/lib/libv8_monolith.a" | cut -f1))"
    else
        echo "  ⚠ V8 build produced no libv8_monolith.a"
        echo "build failed" > "$DISTDIR/v8/NOT_AVAILABLE"
    fi
else
    echo "  ⚠ depot_tools not available — V8 build requires"
    echo "    1. apt install python3 curl git"
    echo "    2. fetch v8 (depot_tools)"
    echo "    3. gn gen + ninja v8_monolith"
    echo "  Skipping V8 for this platform."
    echo "depot_tools not installed" > "$DISTDIR/v8/NOT_AVAILABLE"
fi

# ============================================================
# 4. SDL2 — prebuilt download
# ============================================================
echo "[4/4] Downloading SDL2 v$SDL_VERSION..."
SDL_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL2-devel-${SDL_VERSION}-${SDL_PLATFORM}.${SDL_EXT}"

if curl -sL "$SDL_URL" --max-time 120 -o "$WORKDIR/sdl.$SDL_EXT" 2>/dev/null; then
    case "$SDL_EXT" in
        tar.gz)
            tar xf "$WORKDIR/sdl.$SDL_EXT" -C "$WORKDIR"
            SDL_DIR=$(find "$WORKDIR" -maxdepth 1 -type d -name "SDL2*" | head -1)
            [ -n "$SDL_DIR" ] && cp -r "$SDL_DIR/include/"* "$DISTDIR/sdl2/include/" 2>/dev/null || true
            [ -n "$SDL_DIR" ] && cp -r "$SDL_DIR/lib/"* "$DISTDIR/sdl2/lib/" 2>/dev/null || true
            ;;
        zip)
            unzip -q "$WORKDIR/sdl.$SDL_EXT" -d "$WORKDIR/sdl-extract"
            SDL_DIR=$(find "$WORKDIR/sdl-extract" -maxdepth 2 -type d -name "SDL2*" | head -1)
            if [ -n "$SDL_DIR" ]; then
                cp -r "$SDL_DIR/include/"* "$DISTDIR/sdl2/include/" 2>/dev/null || true
                find "$SDL_DIR" \( -name "*.lib" -o -name "*.dll" -o -name "*.a" \) -exec cp {} "$DISTDIR/sdl2/lib/" \; 2>/dev/null
            fi
            ;;
        dmg)
            hdiutil attach "$WORKDIR/sdl.$SDL_EXT" -mountpoint "$WORKDIR/sdl-mnt" 2>/dev/null || true
            if [ -d "$WORKDIR/sdl-mnt/SDL2.framework" ]; then
                cp -r "$WORKDIR/sdl-mnt/SDL2.framework/Headers/"* "$DISTDIR/sdl2/include/" 2>/dev/null || true
                cp "$WORKDIR/sdl-mnt/SDL2.framework/SDL2" "$DISTDIR/sdl2/lib/libSDL2.dylib" 2>/dev/null || true
            fi
            hdiutil detach "$WORKDIR/sdl-mnt" 2>/dev/null || true
            ;;
    esac
    echo "  ✓ SDL2"
else
    echo "  ⚠ SDL2 download failed"
    echo "not available" > "$DISTDIR/sdl2/NOT_AVAILABLE"
fi

# ============================================================
# Package
# ============================================================
echo ""
echo "Creating archive..."
cd "$OUTDIR"
ZIP_NAME="wagnostic-libs-${PLATFORM}.zip"

if command -v zip &>/dev/null; then
    zip -r "$ZIP_NAME" "wagnostic-libs-$PLATFORM/" 2>&1 | tail -1
else
    tar czf "${ZIP_NAME%.zip}.tar.gz" "wagnostic-libs-$PLATFORM/"
    ZIP_NAME="${ZIP_NAME%.zip}.tar.gz"
fi

echo ""
echo "============================================"
echo " Build complete!"
echo " Platform:    $PLATFORM"
echo " Archive:     $OUTDIR/$ZIP_NAME"
echo " Size:        $(du -h "$OUTDIR/$ZIP_NAME" | cut -f1)"
echo " Contents:"
find "$DISTDIR" -type f | sed 's|.*wagnostic-libs-[^/]*/|  |' | sort
echo "============================================"
