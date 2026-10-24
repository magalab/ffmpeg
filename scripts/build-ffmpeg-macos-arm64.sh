#!/bin/bash
set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "This build must run on macOS."
[[ "$(uname -m)" == arm64 ]] || fail "This build must run on Apple Silicon (arm64)."
TRANSLATED="$(sysctl -in sysctl.proc_translated 2>/dev/null || printf '0')"
[[ "$TRANSLATED" != 1 ]] || fail "The build must run natively on Apple Silicon, not under Rosetta."
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ]] || fail "The build host must run macOS 15 or later."

: "${FFMPEG_VERSION:?Set FFMPEG_VERSION to an exact official release version (for example 9.0.2).}"
: "${FFMPEG_SHA256:?Set FFMPEG_SHA256 to the reviewed SHA-256 of the official source archive.}"
[[ "$FFMPEG_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "Invalid FFmpeg version: $FFMPEG_VERSION"
[[ "$FFMPEG_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || fail "FFMPEG_SHA256 must contain exactly 64 hexadecimal characters."
FFMPEG_SHA256="$(printf '%s' "$FFMPEG_SHA256" | tr '[:upper:]' '[:lower:]')"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-build.XXXXXX")}"
SOURCE_ARCHIVE="${FFMPEG_SOURCE_ARCHIVE:-$BUILD_ROOT/ffmpeg-$FFMPEG_VERSION.tar.xz}"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
SOURCE_SIGNATURE="${FFMPEG_SOURCE_SIGNATURE:-$SOURCE_ARCHIVE.asc}"
SOURCE_SIGNATURE_URL="$SOURCE_URL.asc"
X264_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/x264-version.txt")"
X264_COMMIT="$(tr -d '[:space:]' < "$ROOT_DIR/versions/x264-commit.txt")"
X264_REPOSITORY="https://code.videolan.org/videolan/x264.git"
X264_SOURCE_DIR="${X264_SOURCE_DIR:-$BUILD_ROOT/x264-$X264_VERSION}"
DEPS_PREFIX="$BUILD_ROOT/deps"
X264_PREFIX="$DEPS_PREFIX"
LAME_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/lame-version.txt")"
LAME_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/lame-sha256.txt")"
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
LAME_ARCHIVE="${LAME_SOURCE_ARCHIVE:-$BUILD_ROOT/lame-$LAME_VERSION.tar.gz}"
OPUS_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/opus-version.txt")"
OPUS_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/opus-sha256.txt")"
OPUS_URL="https://ftp.osuosl.org/pub/xiph/releases/opus/opus-$OPUS_VERSION.tar.gz"
OPUS_ARCHIVE="${OPUS_SOURCE_ARCHIVE:-$BUILD_ROOT/opus-$OPUS_VERSION.tar.gz}"
X265_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/x265-version.txt")"
X265_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/x265-sha256.txt")"
X265_URL="https://github.com/Multicorewareinc/x265/releases/download/$X265_VERSION/x265_$X265_VERSION.tar.gz"
X265_ARCHIVE="${X265_SOURCE_ARCHIVE:-$BUILD_ROOT/x265-$X265_VERSION.tar.gz}"
LIBVPX_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/libvpx-version.txt")"
LIBVPX_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/libvpx-sha256.txt")"
LIBVPX_URL="https://github.com/webmproject/libvpx/archive/refs/tags/v$LIBVPX_VERSION.tar.gz"
LIBVPX_ARCHIVE="${LIBVPX_SOURCE_ARCHIVE:-$BUILD_ROOT/libvpx-$LIBVPX_VERSION.tar.gz}"
LIBOGG_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/libogg-version.txt")"
LIBOGG_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/libogg-sha256.txt")"
LIBOGG_URL="https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-$LIBOGG_VERSION.tar.gz"
LIBOGG_ARCHIVE="${LIBOGG_SOURCE_ARCHIVE:-$BUILD_ROOT/libogg-$LIBOGG_VERSION.tar.gz}"
LIBVORBIS_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/libvorbis-version.txt")"
LIBVORBIS_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/libvorbis-sha256.txt")"
LIBVORBIS_URL="https://downloads.xiph.org/releases/vorbis/libvorbis-$LIBVORBIS_VERSION.tar.xz"
LIBVORBIS_ARCHIVE="${LIBVORBIS_SOURCE_ARCHIVE:-$BUILD_ROOT/libvorbis-$LIBVORBIS_VERSION.tar.xz}"
SVT_AV1_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/versions/svt-av1-version.txt")"
SVT_AV1_SHA256="$(tr -d '[:space:]' < "$ROOT_DIR/versions/svt-av1-sha256.txt")"
SVT_AV1_URL="https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVT_AV1_VERSION/SVT-AV1-v$SVT_AV1_VERSION.tar.bz2"
SVT_AV1_ARCHIVE="${SVT_AV1_SOURCE_ARCHIVE:-$BUILD_ROOT/SVT-AV1-v$SVT_AV1_VERSION.tar.bz2}"
JOBS="${JOBS:-4}"
INSTALL_ROOT="$BUILD_ROOT/stage"
PACKAGE_ROOT="$BUILD_ROOT/package"
DEPLOYMENT_TARGET="15.0"

mkdir -p "$BUILD_ROOT" "$INSTALL_ROOT" "$PACKAGE_ROOT" "$ROOT_DIR/dist"
printf 'Downloading FFmpeg %s from the official release host\n' "$FFMPEG_VERSION"
if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
  curl --fail --location --retry 3 --output "$SOURCE_ARCHIVE" "$SOURCE_URL"
fi
if [[ ! -f "$SOURCE_SIGNATURE" ]]; then
  curl --fail --location --retry 3 --output "$SOURCE_SIGNATURE" "$SOURCE_SIGNATURE_URL"
fi
printf '%s  %s\n' "$FFMPEG_SHA256" "$SOURCE_ARCHIVE" | shasum -a 256 --check --status \
  || fail "FFmpeg source archive SHA-256 mismatch."

tar -xJf "$SOURCE_ARCHIVE" -C "$BUILD_ROOT"
SOURCE_DIR="$BUILD_ROOT/ffmpeg-$FFMPEG_VERSION"
[[ -f "$SOURCE_DIR/configure" ]] || fail "Expected FFmpeg source directory was not found."

if [[ ! -d "$X264_SOURCE_DIR/.git" ]]; then
  [[ ! -e "$X264_SOURCE_DIR" ]] || fail "X264_SOURCE_DIR exists but is not a Git checkout: $X264_SOURCE_DIR"
  git init "$X264_SOURCE_DIR"
  git -C "$X264_SOURCE_DIR" remote add origin "$X264_REPOSITORY"
  git -C "$X264_SOURCE_DIR" fetch --depth 1 origin "$X264_COMMIT"
  git -C "$X264_SOURCE_DIR" checkout --detach FETCH_HEAD
fi
ACTUAL_X264_COMMIT="$(git -C "$X264_SOURCE_DIR" rev-parse HEAD)"
[[ "$ACTUAL_X264_COMMIT" == "$X264_COMMIT" ]] \
  || fail "x264 checkout is at $ACTUAL_X264_COMMIT, expected pinned commit $X264_COMMIT. Review X264_SOURCE_DIR or versions/x264-commit.txt."

export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
export CFLAGS="${CFLAGS:-} -O2 -mmacosx-version-min=$DEPLOYMENT_TARGET"
export LDFLAGS="${LDFLAGS:-} -mmacosx-version-min=$DEPLOYMENT_TARGET"

cd "$X264_SOURCE_DIR"
./configure \
  --prefix="$X264_PREFIX" \
  --enable-static \
  --enable-pic \
  --disable-cli \
  --disable-opencl \
  --bit-depth=all \
  2>&1 | tee "$BUILD_ROOT/x264-configure.log"
make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/x264-build.log"
make install-lib-static 2>&1 | tee "$BUILD_ROOT/x264-install.log"
[[ -f "$X264_PREFIX/lib/libx264.a" ]] || fail "Static x264 library was not produced."
[[ -f "$X264_PREFIX/lib/pkgconfig/x264.pc" ]] || fail "x264 pkg-config metadata was not installed."
export PKG_CONFIG_PATH="$X264_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
pkg-config --exists x264 || fail "FFmpeg cannot find the pinned x264 library through pkg-config."

X264_SOURCE_ARCHIVE="$BUILD_ROOT/x264-$X264_VERSION-$X264_COMMIT.tar.gz"
git -C "$X264_SOURCE_DIR" archive --format=tar --prefix="x264-$X264_VERSION/" "$X264_COMMIT" \
  | gzip -n > "$X264_SOURCE_ARCHIVE"
X264_SOURCE_SHA256="$(shasum -a 256 "$X264_SOURCE_ARCHIVE" | awk '{print $1}')"

verify_source_archive() {
  source_archive="$1"
  source_url="$2"
  source_sha="$3"
  if [[ ! -f "$source_archive" ]]; then
    curl --fail --location --retry 3 --output "$source_archive" "$source_url"
  fi
  printf '%s  %s\n' "$source_sha" "$source_archive" | shasum -a 256 --check --status \
    || fail "Source archive SHA-256 mismatch: $source_archive"
}
verify_source_archive "$LAME_ARCHIVE" "$LAME_URL" "$LAME_SHA256"
verify_source_archive "$OPUS_ARCHIVE" "$OPUS_URL" "$OPUS_SHA256"
verify_source_archive "$X265_ARCHIVE" "$X265_URL" "$X265_SHA256"
verify_source_archive "$LIBVPX_ARCHIVE" "$LIBVPX_URL" "$LIBVPX_SHA256"
verify_source_archive "$LIBOGG_ARCHIVE" "$LIBOGG_URL" "$LIBOGG_SHA256"
verify_source_archive "$LIBVORBIS_ARCHIVE" "$LIBVORBIS_URL" "$LIBVORBIS_SHA256"
verify_source_archive "$SVT_AV1_ARCHIVE" "$SVT_AV1_URL" "$SVT_AV1_SHA256"

tar -xzf "$LAME_ARCHIVE" -C "$BUILD_ROOT"
LAME_SOURCE_DIR="$BUILD_ROOT/lame-$LAME_VERSION"
cd "$LAME_SOURCE_DIR"
./configure \
  --prefix="$X264_PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-frontend \
  --disable-decoder \
  --with-pic \
  2>&1 | tee "$BUILD_ROOT/lame-configure.log"
make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/lame-build.log"
make install 2>&1 | tee "$BUILD_ROOT/lame-install.log"

tar -xzf "$OPUS_ARCHIVE" -C "$BUILD_ROOT"
OPUS_SOURCE_DIR="$BUILD_ROOT/opus-$OPUS_VERSION"
cd "$OPUS_SOURCE_DIR"
./configure \
  --prefix="$X264_PREFIX" \
  --enable-static \
  --disable-shared \
  --with-pic \
  --disable-doc \
  --disable-extra-programs \
  2>&1 | tee "$BUILD_ROOT/opus-configure.log"
make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/opus-build.log"
make install 2>&1 | tee "$BUILD_ROOT/opus-install.log"

tar -xzf "$LIBOGG_ARCHIVE" -C "$BUILD_ROOT"
LIBOGG_SOURCE_DIR="$BUILD_ROOT/libogg-$LIBOGG_VERSION"
cd "$LIBOGG_SOURCE_DIR"
./configure --prefix="$DEPS_PREFIX" --enable-static --disable-shared --with-pic \
  2>&1 | tee "$BUILD_ROOT/libogg-configure.log"
make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/libogg-build.log"
make install 2>&1 | tee "$BUILD_ROOT/libogg-install.log"

tar -xJf "$LIBVORBIS_ARCHIVE" -C "$BUILD_ROOT"
LIBVORBIS_SOURCE_DIR="$BUILD_ROOT/libvorbis-$LIBVORBIS_VERSION"
# libvorbis 1.3.7 hardcodes this legacy Darwin flag, which current Apple ld rejects.
sed -i '' 's/ -force_cpusubtype_ALL//g' "$LIBVORBIS_SOURCE_DIR/configure"
sed -i '' 's/ -force_cpusubtype_ALL//g' "$LIBVORBIS_SOURCE_DIR/configure.ac"
cd "$LIBVORBIS_SOURCE_DIR"
./configure --prefix="$DEPS_PREFIX" --enable-static --disable-shared --with-pic \
  2>&1 | tee "$BUILD_ROOT/libvorbis-configure.log"
make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/libvorbis-build.log"
make install 2>&1 | tee "$BUILD_ROOT/libvorbis-install.log"

tar -xzf "$LIBVPX_ARCHIVE" -C "$BUILD_ROOT"
LIBVPX_SOURCE_DIR="$BUILD_ROOT/libvpx-$LIBVPX_VERSION"
cd "$LIBVPX_SOURCE_DIR"
./configure \
  --prefix="$DEPS_PREFIX" \
  --enable-static --disable-shared --enable-pic \
  --enable-vp8 --enable-vp9 --enable-vp9-highbitdepth \
  --disable-examples --disable-tools --disable-docs --disable-unit-tests \
  2>&1 | tee "$BUILD_ROOT/libvpx-configure.log"
make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/libvpx-build.log"
make install 2>&1 | tee "$BUILD_ROOT/libvpx-install.log"

tar -xzf "$X265_ARCHIVE" -C "$BUILD_ROOT"
X265_SOURCE_DIR="$BUILD_ROOT/x265_$X265_VERSION/source"
X265_BUILD_DIR="$BUILD_ROOT/x265-build"
mkdir -p "$X265_BUILD_DIR/8bit"
cmake -S "$X265_SOURCE_DIR" -B "$X265_BUILD_DIR/10bit" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
  -DENABLE_PIC=ON -DENABLE_HDR10_PLUS=ON \
  2>&1 | tee "$BUILD_ROOT/x265-10bit-configure.log"
cmake --build "$X265_BUILD_DIR/10bit" --parallel "$JOBS" \
  2>&1 | tee "$BUILD_ROOT/x265-10bit-build.log"
mv "$X265_BUILD_DIR/10bit/libx265.a" "$X265_BUILD_DIR/8bit/libx265_main10.a"
cmake -S "$X265_SOURCE_DIR" -B "$X265_BUILD_DIR/12bit" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DMAIN12=ON -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF \
  -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_PIC=ON \
  2>&1 | tee "$BUILD_ROOT/x265-12bit-configure.log"
cmake --build "$X265_BUILD_DIR/12bit" --parallel "$JOBS" \
  2>&1 | tee "$BUILD_ROOT/x265-12bit-build.log"
mv "$X265_BUILD_DIR/12bit/libx265.a" "$X265_BUILD_DIR/8bit/libx265_main12.a"
cmake -S "$X265_SOURCE_DIR" -B "$X265_BUILD_DIR/8bit" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
  '-DEXTRA_LINK_FLAGS=-L.' '-DEXTRA_LIB=x265_main10.a;x265_main12.a' \
  -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_PIC=ON -DENABLE_HDR10_PLUS=ON \
  2>&1 | tee "$BUILD_ROOT/x265-configure.log"
cmake --build "$X265_BUILD_DIR/8bit" --parallel "$JOBS" \
  2>&1 | tee "$BUILD_ROOT/x265-build.log"
mv "$X265_BUILD_DIR/8bit/libx265.a" "$X265_BUILD_DIR/8bit/libx265_main.a"
libtool -static -o "$X265_BUILD_DIR/8bit/libx265.a" \
  "$X265_BUILD_DIR/8bit/libx265_main.a" \
  "$X265_BUILD_DIR/8bit/libx265_main10.a" \
  "$X265_BUILD_DIR/8bit/libx265_main12.a"
cmake --install "$X265_BUILD_DIR/8bit" 2>&1 | tee "$BUILD_ROOT/x265-install.log"

tar -xjf "$SVT_AV1_ARCHIVE" -C "$BUILD_ROOT"
SVT_AV1_SOURCE_DIR="$BUILD_ROOT/SVT-AV1-v$SVT_AV1_VERSION"
SVT_AV1_BUILD_DIR="$BUILD_ROOT/svt-av1-build"
cmake -S "$SVT_AV1_SOURCE_DIR" -B "$SVT_AV1_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DBUILD_APPS=OFF \
  2>&1 | tee "$BUILD_ROOT/svt-av1-configure.log"
cmake --build "$SVT_AV1_BUILD_DIR" --parallel "$JOBS" \
  2>&1 | tee "$BUILD_ROOT/svt-av1-build.log"
cmake --install "$SVT_AV1_BUILD_DIR" 2>&1 | tee "$BUILD_ROOT/svt-av1-install.log"

export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
pkg-config --exists x264 lame opus ogg vorbis vorbisenc vpx x265 SvtAv1Enc \
  || fail "FFmpeg cannot find all pinned static codec libraries through pkg-config."
for archive in libx264.a libmp3lame.a libopus.a libogg.a libvorbis.a libvpx.a libx265.a libSvtAv1Enc.a; do
  [[ -f "$DEPS_PREFIX/lib/$archive" ]] || fail "Expected static dependency archive is missing: $archive"
done
LAME_SOURCE_SHA256="$(shasum -a 256 "$LAME_ARCHIVE" | awk '{print $1}')"
OPUS_SOURCE_SHA256="$(shasum -a 256 "$OPUS_ARCHIVE" | awk '{print $1}')"
X265_SOURCE_SHA256="$(shasum -a 256 "$X265_ARCHIVE" | awk '{print $1}')"
LIBVPX_SOURCE_SHA256="$(shasum -a 256 "$LIBVPX_ARCHIVE" | awk '{print $1}')"
LIBOGG_SOURCE_SHA256="$(shasum -a 256 "$LIBOGG_ARCHIVE" | awk '{print $1}')"
LIBVORBIS_SOURCE_SHA256="$(shasum -a 256 "$LIBVORBIS_ARCHIVE" | awk '{print $1}')"
SVT_AV1_SOURCE_SHA256="$(shasum -a 256 "$SVT_AV1_ARCHIVE" | awk '{print $1}')"

cd "$SOURCE_DIR"
./configure \
  --prefix="$INSTALL_ROOT" \
  --arch=arm64 \
  --enable-static \
  --disable-shared \
  --disable-autodetect \
  --enable-gpl \
  --disable-version3 \
  --disable-nonfree \
  --enable-libx264 \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libvorbis \
  --enable-libsvtav1 \
  --enable-zlib \
  --enable-bzlib \
  --disable-ffplay \
  --disable-doc \
  --disable-debug \
  --enable-videotoolbox \
  --enable-audiotoolbox \
  --pkg-config-flags=--static \
  --extra-libs=-lc++ \
  --extra-cflags="-I$X264_PREFIX/include -mmacosx-version-min=$DEPLOYMENT_TARGET" \
  --extra-ldflags="-L$X264_PREFIX/lib -mmacosx-version-min=$DEPLOYMENT_TARGET" \
  2>&1 | tee "$BUILD_ROOT/configure.log"

make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/build.log"
make install 2>&1 | tee "$BUILD_ROOT/install.log"

for binary in ffmpeg ffprobe; do
  [[ -x "$INSTALL_ROOT/bin/$binary" ]] || fail "Build did not produce $binary."
done

mkdir -p "$PACKAGE_ROOT/bin" "$PACKAGE_ROOT/share/ffmpeg-build"
install -m 755 "$INSTALL_ROOT/bin/ffmpeg" "$PACKAGE_ROOT/bin/ffmpeg"
install -m 755 "$INSTALL_ROOT/bin/ffprobe" "$PACKAGE_ROOT/bin/ffprobe"
cp "$SOURCE_DIR/COPYING.LGPLv2.1" "$PACKAGE_ROOT/share/ffmpeg-build/" \
  || fail "FFmpeg LGPL license text is missing from the source archive."
cp "$SOURCE_DIR/COPYING.GPLv2" "$PACKAGE_ROOT/share/ffmpeg-build/" \
  || fail "FFmpeg GPL license text is missing from the source archive."
cp "$X264_SOURCE_DIR/COPYING" "$PACKAGE_ROOT/share/ffmpeg-build/x264-COPYING" \
  || fail "x264 license text is missing from the pinned source checkout."
cp "$LAME_SOURCE_DIR/COPYING" "$PACKAGE_ROOT/share/ffmpeg-build/lame-COPYING" \
  || fail "LAME license text is missing from the source archive."
cp "$OPUS_SOURCE_DIR/COPYING" "$PACKAGE_ROOT/share/ffmpeg-build/opus-COPYING" \
  || fail "Opus license text is missing from the source archive."
cp "$BUILD_ROOT/x265_$X265_VERSION/COPYING" "$PACKAGE_ROOT/share/ffmpeg-build/x265-COPYING" \
  || fail "x265 license text is missing from the source archive."
cp "$LIBVPX_SOURCE_DIR/LICENSE" "$PACKAGE_ROOT/share/ffmpeg-build/libvpx-LICENSE" \
  || fail "libvpx license text is missing from the source archive."
cp "$LIBOGG_SOURCE_DIR/COPYING" "$PACKAGE_ROOT/share/ffmpeg-build/libogg-COPYING" \
  || fail "libogg license text is missing from the source archive."
cp "$LIBVORBIS_SOURCE_DIR/COPYING" "$PACKAGE_ROOT/share/ffmpeg-build/libvorbis-COPYING" \
  || fail "libvorbis license text is missing from the source archive."
cp "$SVT_AV1_SOURCE_DIR/LICENSE.md" "$PACKAGE_ROOT/share/ffmpeg-build/svt-av1-LICENSE.md" \
  || fail "SVT-AV1 license text is missing from the source archive."
cp "$SVT_AV1_SOURCE_DIR/PATENTS.md" "$PACKAGE_ROOT/share/ffmpeg-build/svt-av1-PATENTS.md" \
  || fail "SVT-AV1 patent license text is missing from the source archive."
cp "$ROOT_DIR/README.md" "$PACKAGE_ROOT/share/ffmpeg-build/README.md"
cp "$ROOT_DIR/scripts/build-ffmpeg-macos-arm64.sh" "$PACKAGE_ROOT/share/ffmpeg-build/build-script.sh"
"$PACKAGE_ROOT/bin/ffmpeg" -version > "$PACKAGE_ROOT/share/ffmpeg-build/ffmpeg-version.txt"
"$PACKAGE_ROOT/bin/ffprobe" -version > "$PACKAGE_ROOT/share/ffmpeg-build/ffprobe-version.txt"
"$PACKAGE_ROOT/bin/ffmpeg" -buildconf > "$PACKAGE_ROOT/share/ffmpeg-build/buildconf.txt" 2>&1

{
  printf 'ffmpeg_version=%s\n' "$FFMPEG_VERSION"
  printf 'source_url=%s\n' "$SOURCE_URL"
  printf 'source_signature_url=%s\n' "$SOURCE_SIGNATURE_URL"
  printf 'source_sha256=%s\n' "$FFMPEG_SHA256"
  printf 'architecture=arm64\n'
  printf 'minimum_macos=%s\n' "$DEPLOYMENT_TARGET"
  printf 'license=GPL-2.0-or-later\n'
  printf 'x264=enabled\n'
  printf 'x264_version=%s\n' "$X264_VERSION"
  printf 'x264_commit=%s\n' "$X264_COMMIT"
  printf 'x264_source_sha256=%s\n' "$X264_SOURCE_SHA256"
  printf 'lame_version=%s\n' "$LAME_VERSION"
  printf 'lame_source_url=%s\n' "$LAME_URL"
  printf 'lame_source_sha256=%s\n' "$LAME_SOURCE_SHA256"
  printf 'opus_version=%s\n' "$OPUS_VERSION"
  printf 'opus_source_url=%s\n' "$OPUS_URL"
  printf 'opus_source_sha256=%s\n' "$OPUS_SOURCE_SHA256"
  printf 'x265_version=%s\n' "$X265_VERSION"
  printf 'x265_source_url=%s\n' "$X265_URL"
  printf 'x265_source_sha256=%s\n' "$X265_SOURCE_SHA256"
  printf 'libvpx_version=%s\n' "$LIBVPX_VERSION"
  printf 'libvpx_source_url=%s\n' "$LIBVPX_URL"
  printf 'libvpx_source_sha256=%s\n' "$LIBVPX_SOURCE_SHA256"
  printf 'libogg_version=%s\n' "$LIBOGG_VERSION"
  printf 'libogg_source_url=%s\n' "$LIBOGG_URL"
  printf 'libogg_source_sha256=%s\n' "$LIBOGG_SOURCE_SHA256"
  printf 'libvorbis_version=%s\n' "$LIBVORBIS_VERSION"
  printf 'libvorbis_source_url=%s\n' "$LIBVORBIS_URL"
  printf 'libvorbis_source_sha256=%s\n' "$LIBVORBIS_SOURCE_SHA256"
  printf 'libvorbis_macos_patch=removed unsupported -force_cpusubtype_ALL flag from configure and configure.ac\n'
  printf 'svt_av1_version=%s\n' "$SVT_AV1_VERSION"
  printf 'svt_av1_source_url=%s\n' "$SVT_AV1_URL"
  printf 'svt_av1_source_sha256=%s\n' "$SVT_AV1_SOURCE_SHA256"
  printf 'runner_macos=%s\n' "$(sw_vers -productVersion)"
  printf 'xcode=%s\n' "$(xcodebuild -version | tr '\n' ' ')"
  printf 'clang=%s\n' "$(clang --version | head -n 1)"
  printf 'sdk=%s\n' "$(xcrun --sdk macosx --show-sdk-version)"
  printf 'configure_log=configure.log\n'
} > "$PACKAGE_ROOT/share/ffmpeg-build/build-metadata.txt"

PACKAGE_NAME="ffmpeg-$FFMPEG_VERSION-macos15-arm64"
cp "$SOURCE_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-ffmpeg-source.tar.xz"
cp "$SOURCE_SIGNATURE" "$ROOT_DIR/dist/$PACKAGE_NAME-ffmpeg-source.tar.xz.asc"
cp "$X264_SOURCE_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-x264-source.tar.gz"
cp "$LAME_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-lame-source.tar.gz"
cp "$OPUS_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-opus-source.tar.gz"
cp "$X265_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-x265-source.tar.gz"
cp "$LIBVPX_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-libvpx-source.tar.gz"
cp "$LIBOGG_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-libogg-source.tar.gz"
cp "$LIBVORBIS_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-libvorbis-source.tar.xz"
cp "$SVT_AV1_ARCHIVE" "$ROOT_DIR/dist/$PACKAGE_NAME-svt-av1-source.tar.bz2"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-ffmpeg-source.tar.xz" > "$ROOT_DIR/dist/$PACKAGE_NAME-ffmpeg-source.tar.xz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-x264-source.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME-x264-source.tar.gz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-lame-source.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME-lame-source.tar.gz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-opus-source.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME-opus-source.tar.gz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-x265-source.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME-x265-source.tar.gz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-libvpx-source.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME-libvpx-source.tar.gz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-libogg-source.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME-libogg-source.tar.gz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-libvorbis-source.tar.xz" > "$ROOT_DIR/dist/$PACKAGE_NAME-libvorbis-source.tar.xz.sha256"
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME-svt-av1-source.tar.bz2" > "$ROOT_DIR/dist/$PACKAGE_NAME-svt-av1-source.tar.bz2.sha256"
cp "$BUILD_ROOT/x264-configure.log" "$ROOT_DIR/dist/$PACKAGE_NAME-x264-configure.log"
cp "$BUILD_ROOT/x264-build.log" "$ROOT_DIR/dist/$PACKAGE_NAME-x264-build.log"
cp "$BUILD_ROOT/x264-install.log" "$ROOT_DIR/dist/$PACKAGE_NAME-x264-install.log"
cp "$BUILD_ROOT/lame-configure.log" "$ROOT_DIR/dist/$PACKAGE_NAME-lame-configure.log"
cp "$BUILD_ROOT/lame-build.log" "$ROOT_DIR/dist/$PACKAGE_NAME-lame-build.log"
cp "$BUILD_ROOT/opus-configure.log" "$ROOT_DIR/dist/$PACKAGE_NAME-opus-configure.log"
cp "$BUILD_ROOT/opus-build.log" "$ROOT_DIR/dist/$PACKAGE_NAME-opus-build.log"
for dependency in libogg libvorbis libvpx x265 svt-av1; do
  for log_type in configure build install; do
    log="$BUILD_ROOT/$dependency-$log_type.log"
    [[ ! -f "$log" ]] || cp "$log" "$ROOT_DIR/dist/$PACKAGE_NAME-$dependency-$log_type.log"
  done
done
for depth in 10bit 12bit; do
  cp "$BUILD_ROOT/x265-$depth-configure.log" "$ROOT_DIR/dist/$PACKAGE_NAME-x265-$depth-configure.log"
  cp "$BUILD_ROOT/x265-$depth-build.log" "$ROOT_DIR/dist/$PACKAGE_NAME-x265-$depth-build.log"
done
tar -czf "$ROOT_DIR/dist/$PACKAGE_NAME.tar.gz" -C "$PACKAGE_ROOT" .
shasum -a 256 "$ROOT_DIR/dist/$PACKAGE_NAME.tar.gz" > "$ROOT_DIR/dist/$PACKAGE_NAME.tar.gz.sha256"
cp "$PACKAGE_ROOT/share/ffmpeg-build/build-metadata.txt" "$ROOT_DIR/dist/$PACKAGE_NAME-build-metadata.txt"
cp "$BUILD_ROOT/configure.log" "$ROOT_DIR/dist/$PACKAGE_NAME-configure.log"
if [[ -s "$BUILD_ROOT/build.log" ]]; then
  cp "$BUILD_ROOT/build.log" "$ROOT_DIR/dist/$PACKAGE_NAME-build.log"
else
  rm -f "$ROOT_DIR/dist/$PACKAGE_NAME-build.log"
fi
cp "$BUILD_ROOT/install.log" "$ROOT_DIR/dist/$PACKAGE_NAME-install.log"
printf 'Package created: %s/dist/%s.tar.gz\n' "$ROOT_DIR" "$PACKAGE_NAME"
