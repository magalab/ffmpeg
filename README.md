# FFmpeg for macOS arm64

Build and distribute `ffmpeg` and `ffprobe` for Apple Silicon Macs running macOS 15 or later. The release workflow takes an exact official FFmpeg version, verifies its official source signature, and calculates the archive SHA-256 automatically.

## Build profile

- Apple Silicon (`arm64`) only; deployment target macOS 15.0.
- FFmpeg's built-in codecs and filters, plus Apple's VideoToolbox and AudioToolbox integrations.
- H.264 software encoding via `libx264` and hardware encoding via `h264_videotoolbox` are both included. HEVC software encoding uses `libx265` with 8-, 10-, and 12-bit support.
- VP8/VP9 software encoding uses libvpx. AV1 software encoding uses SVT-AV1 (`libsvtav1`).
- MP3 encoding uses LAME (`libmp3lame`), Opus uses `libopus`, and Vorbis uses `libvorbis`. The native Opus and Vorbis encoders remain experimental; use the external encoders for production output.
- The build enables GPL because x264 and x265 are GPL-2.0-or-later. Each release includes the exact FFmpeg and all linked library sources, checksums, build script, license texts, configure output, and build metadata.
- External libraries are disabled from auto-detection. Pinned x264, LAME, Opus, x265, libvpx, libogg, libvorbis, and SVT-AV1 sources are built as static libraries, so the binaries have no Homebrew runtime paths.

This profile follows common local conversion use, but does not yet match every external encoder in the existing system FFmpeg. It omits AOM AV1, OpenJPEG, WebP, VVenc, Kvazaar, HAP, and some specialist codecs. Availability and performance of Apple hardware encoders depend on the Mac model and macOS. Consult `ffmpeg -encoders`, `ffmpeg -decoders`, and `ffmpeg -filters` for the exact compiled lists.

## Local build

Use an Apple Silicon Mac running natively, with Xcode Command Line Tools, CMake, `pkg-config`, `curl`, `shasum`, `tar`, `make`, and GnuPG installed. The build script rejects Intel and Rosetta processes. Verify the official FFmpeg release archive signature before calculating the SHA-256 used by the build:

```sh
VERSION=9.0.2
curl -fLO "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
curl -fLO "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz.asc"
curl -fLo ffmpeg-devel.asc https://ffmpeg.org/ffmpeg-devel.asc
gpg --import ffmpeg-devel.asc
gpg --fingerprint FCF986EA15E6E293A5644F10B4322F04D67658D8
gpg --verify "ffmpeg-$VERSION.tar.xz.asc" "ffmpeg-$VERSION.tar.xz"
shasum -a 256 "ffmpeg-$VERSION.tar.xz"
```

Confirm the displayed key fingerprint matches the official FFmpeg release key before trusting the signature. Then build with the resulting 64-character hash:

```sh
FFMPEG_VERSION="$VERSION" \
FFMPEG_SHA256='<verified 64-character SHA-256>' \
./scripts/build-ffmpeg-macos-arm64.sh
```

The script downloads `https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz`, verifies the hash before extraction, builds in an isolated temporary directory, and writes the package under `dist/`.

## Releases

The `Build and release` workflow supports reviewed manual dispatch. First update `versions/current-ffmpeg-version.txt` after reviewing an official release, then enter that exact version. The workflow rejects versions that differ from this reviewed baseline or already have a Git tag, verifies the official signature, and computes the archive SHA-256 before compiling. It runs on GitHub's native arm64 `macos-15` runner and checks that Rosetta is not active. Before creating a Release, it smoke-tests the binaries and runs Homebrew formula style and audit checks. It then publishes the binary and source materials, and updates `magalab/homebrew-tap`; configure the `HOMEBREW_TAP_TOKEN` repository secret with write access to that repository before running a release. The weekly upstream check opens a review issue for a newer FFmpeg stable release and never publishes automatically.

The formula is arm64-only and declares macOS 15 as its minimum. The tap token should be limited to `magalab/homebrew-tap`.

## License

This FFmpeg build is distributed under GPL version 2 or later because it links x264 and x265, which are GPL-2.0-or-later. The release carries exact corresponding FFmpeg and linked library source materials, build script, configuration, and license notices, including SVT-AV1's patent license. Review the generated materials and the effect of GPL distribution on any application that bundles these binaries before each release.
