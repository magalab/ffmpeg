# FFmpeg / ffprobe macOS arm64 开发计划

## 1. 目标

通过 GitHub Actions 自动构建并分发适用于 Apple Silicon（arm64）的 `ffmpeg` 与 `ffprobe` 二进制，供 macOS 应用打包使用，并通过组织自有 Homebrew tap 提供安装入口。

- 最低支持系统：macOS 15.0（macOS 15 及以上）
- 构建平台：GitHub 标准托管 macOS arm64 runner，先固定 `macos-15`
- GitHub 仓库：`magalab/ffmpeg`
- 分发形式：`magalab/ffmpeg` 的 GitHub Release 提供压缩包、版本/构建信息、许可证/源码材料和 SHA-256；`magalab/homebrew-tap` 提供 Homebrew formula
- 仓库预期为公开仓库；标准 GitHub-hosted runner 的公开仓库用量免费。仍需遵守平台并发、存储和使用政策。

## 2. 范围与功能取舍

面向常见本地媒体转换与探测，不追求覆盖所有专业、广播、光盘及冷门格式。以 [OSXExperts 当前构建](https://osxexperts.net/) 展示的能力作为候选清单，再按常见本地媒体场景裁剪；不照搬其旧构建脚本或全部依赖。首版建议支持：

- MP4/MOV、MKV、WebM、MP3、WAV、M4A 等常见媒体的读取与 `ffprobe` 元数据探测
- H.264 视频解码及 `libx264` 软件编码和 VideoToolbox 硬件编码，AAC 编码/解码；MP3 使用 LAME 编码，Opus 使用 libopus 编码，并支持 MP3、Opus、Vorbis 解码和 PCM 等常见音频转换。内置 Opus/Vorbis 编码器仍处于 experimental 状态，需 `-strict -2`，且内置 Vorbis 编码仅支持双声道
- 常见字幕流探测、读取和封装/转封装；首版不承诺字幕烧录与复杂字体排版
- 常用缩放、裁剪、帧率、像素格式、音量、重采样等基础滤镜
- macOS VideoToolbox 能力仅在分别验证编码/解码场景后列入承诺功能

首版选择加入 x265、libvpx、libvorbis，并以 SVT-AV1 作为唯一外部 AV1 编码器；暂不同时加入 AOM。相对本机现有构建，仍未纳入 OpenJPEG、WebP、VVenc、Kvazaar、HAP 等外部编码器。蓝光/菜单、Theora、Vid.Stab、复杂字体字幕渲染和多数小众编解码器暂不纳入。最终支持清单以构建后的 encoder/decoder/filter 列表和代表性转码测试为准，并在文档中公布。

### H.264 编码路径与许可证决策

FFmpeg 的 `libx264` 和 `h264_videotoolbox` 是两条不同的 H.264 编码路径。x264 是随包链接的第三方软件编码器，侧重软件编码、可控参数和特定质量/速度行为；VideoToolbox 是 FFmpeg 调用 Apple 系统媒体 API 的路径，通常可利用设备硬件能力，但实际能力受设备、macOS 版本及编码参数影响。两者互不依赖，应分别查询并分别做真实转码验收。启用了 VideoToolbox 不代表构建中包含 x264，反之亦然。

首版提供 `h264_videotoolbox`、`libx264`、`libx265`、`libvpx` 与 `libsvtav1`，并用 LAME、libopus、libvorbis 处理常见音频编码。x264 和 x265 均为 GPL-2.0-or-later，本项目启用 GPL 构建并按 GPL 条件分发。每个 Release 必须附 FFmpeg 和所有链接依赖的对应源码、构建脚本/配置及许可证告知；SVT-AV1 的专利授权文本也随包提供。若应用把该二进制再打包进应用安装包，还须审查应用整体分发方式；把 CLI 放入 Homebrew tap 不会自动解决应用分发的 GPL 影响。

FFmpeg 和外部库的许可取决于实际构建配置。发布流程应由最终 configure 配置与依赖锁定清单生成许可证/源码归档清单并人工审查。不得把“静态链接”描述为完全没有系统依赖，macOS 系统框架仍可能动态链接。

OSXExperts 页面可用来对照其当前列出的 x264/x265、VPx/AOM、Opus、MP3、字幕滤镜等功能范围，以及独立分发 `ffmpeg`/`ffprobe` 的形式。它的旧脚本、旧依赖版本和宽泛功能集合仅作参考。首版先落实上面的常见容器、H.264/AAC、常见音频和基础滤镜。

## 3. 仓库交付结构

建议新增：

- `.github/workflows/build-ffmpeg-macos-arm64.yml`：CI 与发布入口
- `.github/workflows/check-ffmpeg-upstream.yml`：定期检查 FFmpeg 官方发行归档，只创建待审核 issue
- `scripts/build-ffmpeg-macos-arm64.sh`：按锁定版本/commit 构建 x264、x265、libvpx、libogg、libvorbis、SVT-AV1、LAME、Opus 和 FFmpeg，并整理二进制、元数据、许可证、各源码归档、压缩包和校验文件
- `scripts/publish-tap-formula.sh`：生成并提交 tap formula
- `README.md`：构建参数、功能清单、更新方式与许可证说明
- `magalab/homebrew-tap` 仓库中的 `Formula/ffmpeg.rb`；遵循该 tap 的 README 和现有 formula 约定

所有依赖版本固定到明确 tag/commit 并记录校验值，避免构建结果随上游漂移。

## 4. 分阶段实施

### 阶段 A：确认构建基线

1. 跟随 FFmpeg 官方稳定发布 tag。自动发现新 tag 后只创建待审核更新；审核确认后锁定官方 tag 对应的不可变 commit。不得从浮动分支或未审核第三方镜像构建。依赖同样固定 tag/commit 和校验值。
2. 首版启用 x264、x265、libvpx、libvorbis、SVT-AV1、LAME 和 Opus；构建使用 `--enable-gpl` 及相应 `--enable-lib*` 选项。分发前审查 GPL 条件并随二进制提供 FFmpeg 和全部外部依赖源码与构建材料。
3. 形成 configure 参数，并保留完整 configure 输出、`ffmpeg -buildconf` 和最终启用组件清单作为审计材料。
4. 设定 `MACOSX_DEPLOYMENT_TARGET=15.0`，确认 SDK、编译器和依赖不会意外提高最低系统版本。支持范围写明 macOS 15 及以上。

### 阶段 B：实现 arm64 构建脚本

1. 在干净目录下载并校验 FFmpeg 官方 tag 对应源码及固定版本依赖。
2. 从锁定的 x264 commit 和各固定版本源码构建 PIC 静态库；x265 生成 8/10/12-bit 合并库，libvorbis 依赖静态 libogg，SVT-AV1 使用官方 CMake 构建。再启用 `--pkg-config-flags=--static` 并显式设置 arm64、编译/链接参数和 pkg-config 搜索路径。
3. 配置并构建 FFmpeg，仅安装 `ffmpeg` 与 `ffprobe`（无需 `ffplay`）。
4. 脚本启用严格错误处理；任何下载、校验、配置或编译失败都立即退出。
5. 输出构建版本、上游 tag/commit、架构、部署目标、configure 参数、依赖版本/校验值、Xcode/SDK/clang 版本和完整构建日志；归档构建脚本、补丁及适用许可证/源码材料。

### 阶段 C：GitHub Actions 自动化与发布

1. `workflow_dispatch` 只要求输入精确官方 FFmpeg 版本；工作流核验官方签名后自行计算并记录源码归档 SHA-256。每周检查官方 release archive；发现比 `versions/current-ffmpeg-version.txt` 更新的稳定版本时只创建待审核 issue，不自动构建或发布。审核后更新版本基线，再手动运行发布工作流。
2. 使用 `macos-15` 标准 arm64 runner；工作流权限遵循最小权限原则。
3. 从干净 runner 构建；源码归档在校验 SHA-256 后才解压，不复用未经校验的构建产物。
4. 在 arm64 runner 上对产物实际执行 VideoToolbox H.264/AAC、libx264/libx265、VP8/VP9、SVT-AV1、LAME MP3、libopus 和 libvorbis 编码，以及 H.264 解码/缩放验收。验收通过后再创建 GitHub Release。
5. 发布到本仓库 GitHub Release：arm64 压缩包、FFmpeg 和全部外部依赖源码、SHA-256、构建元数据、许可证材料和构建日志。
6. 验收通过后自动更新 `magalab/homebrew-tap` 的 `Formula/ffmpeg.rb`。Formula 的固定版本下载 URL 指向 `magalab/ffmpeg` Release 资产，包含对应 SHA-256。tap 更新失败时将发布标为失败/待处理，避免 Release 与 formula 版本脱节。使用仅能更新目标 tap 的最小权限凭据。
7. Formula 明确仅支持 macOS 15+ arm64，并提供 `brew install magalab/homebrew-tap/ffmpeg` 使用方式。验证干净 macOS 15 arm64 环境可安装，并能调用 `ffmpeg`、`ffprobe` 和预期功能。

### 阶段 D：验证与许可证

1. `file` / `lipo -info` 确认两个程序均为 arm64。
2. `otool -l` 检查部署目标；`otool -L` 检查链接依赖，确认不存在意外的 Homebrew 路径或未打包动态库。
3. 执行 `ffmpeg -version`、`ffprobe -version`，检查构建配置和版本信息。
4. 用小型合成测试素材覆盖：MP4/MOV、MKV、WebM 与常见音频输入探测；VideoToolbox、libx264、libx265、VP8/VP9 和 SVT-AV1 编码；AAC、LAME MP3、libopus、libvorbis 编码；MP3/Opus/Vorbis 解码；缩放/裁剪/音量/重采样；字幕流探测或转封装；损坏/不支持输入的错误返回。
5. 在 macOS 15 arm64 环境验证运行和 tap 安装；文档注明支持 macOS 15 及以上。
6. 打包 FFmpeg 和全部外部依赖源码、许可证文本、SVT-AV1 专利许可、依赖版本/校验值、构建脚本与配置，并审查 GPL 要求；检查构建配置确认未启用 nonfree 组件。
7. 记录 Xcode、SDK、clang、runner 镜像、上游/依赖 commit 与校验值、构建日志及产物 SHA-256，保证版本更新可追溯。

## 5. 验收标准

- Actions 从干净 runner 可重复完成 arm64 构建并生成发布包。
- 包内只有预期的 `ffmpeg`、`ffprobe` 和说明/许可证文件，无构建临时文件；若启用 GPL，含对应源码与构建材料。
- 两个二进制均为 arm64，部署目标为 macOS 15.0，且没有 Homebrew 安装路径依赖。
- `ffmpeg -version` / `ffprobe -version` 成功；功能清单中的代表性场景通过验证。
- Release 包附带 SHA-256、构建版本、许可证材料；启用 GPL 时附带对应源码和构建材料。
- `magalab/homebrew-tap` 中的 formula 与 `magalab/ffmpeg` Release 版本、下载 URL、SHA-256 一致；在干净 macOS 15 arm64 runner 上安装和基本调用通过。
- 构建使用审核过的 FFmpeg 官方 tag 对应源码，并可从归档材料追溯依赖和构建环境。
- 文档清楚列出已启用与未承诺的功能、最低系统版本及版本更新步骤。

## 6. Codex 执行提示

先检查 `magalab/ffmpeg` 仓库结构、`AGENTS.md`、许可证、应用集成方式，以及 `magalab/homebrew-tap` 的 README/Formula 约定，再按阶段实施。不要复制 OSXExperts 的旧脚本；将其作为能力范围参考，重新实现适合现代 macOS runner 的自动化构建。按常见应用场景保持依赖精简，并记录功能取舍。Release 和 `magalab/homebrew-tap` 是预期交付渠道；更新 tap 时使用组织已配置的 GitHub 权限与凭据。
