#!/bin/bash
set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
: "${FFMPEG_VERSION:?Set FFMPEG_VERSION.}"
: "${PACKAGE_SHA256:?Set PACKAGE_SHA256 to the Release tarball SHA-256.}"
: "${TAP_DIRECTORY:?Set TAP_DIRECTORY to the checked-out Homebrew tap.}"
PUBLISH_TAP="${PUBLISH_TAP:-true}"

[[ "$FFMPEG_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "Invalid version."
[[ "$PACKAGE_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || fail "Invalid package SHA-256."
[[ "$PUBLISH_TAP" == true || "$PUBLISH_TAP" == false ]] || fail "PUBLISH_TAP must be true or false."

[[ -d "$TAP_DIRECTORY/.git" ]] || fail "TAP_DIRECTORY is not a checked-out Git repository: $TAP_DIRECTORY"

mkdir -p "$TAP_DIRECTORY/Formula"
cat > "$TAP_DIRECTORY/Formula/ffmpeg.rb" <<EOF
class Ffmpeg < Formula
  desc "FFmpeg and ffprobe for Apple Silicon Macs"
  homepage "https://github.com/magalab/ffmpeg"
  url "https://github.com/magalab/ffmpeg/releases/download/ffmpeg-v${FFMPEG_VERSION}/ffmpeg-${FFMPEG_VERSION}-macos15-arm64.tar.gz"
  sha256 "${PACKAGE_SHA256}"
  version "${FFMPEG_VERSION}"
  license "GPL-2.0-or-later"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  def install
    bin.install "bin/ffmpeg", "bin/ffprobe"
    pkgshare.install "share/ffmpeg-build"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ffmpeg -version")
    assert_match version.to_s, shell_output("#{bin}/ffprobe -version")
    output = shell_output("#{bin}/ffmpeg -hide_banner -encoders 2>&1")
    assert_match "libx264", output
    assert_match "h264_videotoolbox", output
    assert_match "aac", output
    assert_match "libmp3lame", output
    assert_match "libopus", output
    assert_match "libx265", output
    assert_match "libvpx", output
    assert_match "libvpx-vp9", output
    assert_match "libvorbis", output
    assert_match "libsvtav1", output

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "testsrc2=duration=1:size=320x240:rate=30", "-c:v",
           "libx264", "-preset", "ultrafast", "-b:v", "500k", "#{testpath}/smoke.mp4"
    assert_match "h264", shell_output("#{bin}/ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke.mp4")

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "sine=frequency=440:sample_rate=44100:duration=1", "-c:a",
           "libmp3lame", "#{testpath}/smoke.mp3"
    assert_match "mp3", shell_output("#{bin}/ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke.mp3")

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "sine=frequency=440:sample_rate=48000:duration=1", "-c:a",
           "libopus", "#{testpath}/smoke.opus"
    assert_match "opus", shell_output("#{bin}/ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke.opus")

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "testsrc2=duration=1:size=320x240:rate=24", "-c:v", "libx265",
           "-preset", "ultrafast", "-x265-params", "log-level=error", "#{testpath}/smoke-hevc.mp4"
    assert_match "hevc", shell_output("#{bin}/ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke-hevc.mp4")

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "testsrc2=duration=1:size=320x240:rate=24", "-c:v", "libvpx-vp9",
           "-deadline", "realtime", "-cpu-used", "8", "-b:v", "500k", "#{testpath}/smoke-vp9.webm"
    assert_match "vp9", shell_output("#{bin}/ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke-vp9.webm")

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "testsrc2=duration=1:size=320x240:rate=24", "-c:v", "libsvtav1",
           "-preset", "12", "-crf", "45", "#{testpath}/smoke-av1.mkv"
    assert_match "av1", shell_output("#{bin}/ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke-av1.mkv")

    system bin/"ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "lavfi",
           "-i", "sine=frequency=440:sample_rate=48000:duration=1", "-c:a",
           "libvorbis", "#{testpath}/smoke-vorbis.ogg"
    assert_match "vorbis", shell_output("#{bin}/ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{testpath}/smoke-vorbis.ogg")
  end
end
EOF

brew style --formula "$TAP_DIRECTORY/Formula/ffmpeg.rb"
brew audit --formula "$TAP_DIRECTORY/Formula/ffmpeg.rb"
if [[ "$PUBLISH_TAP" == false ]]; then
  printf 'Tap formula generated and checked; no tap commit or push requested.\n'
  exit 0
fi

git -C "$TAP_DIRECTORY" add Formula/ffmpeg.rb
if git -C "$TAP_DIRECTORY" diff --cached --quiet; then
  printf 'Tap formula is already current.\n'
  exit 0
fi
git -C "$TAP_DIRECTORY" -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -m "ffmpeg: update to $FFMPEG_VERSION"
git -C "$TAP_DIRECTORY" push origin HEAD
