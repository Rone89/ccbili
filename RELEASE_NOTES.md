## 本版本修复

- 通过 Swift Package Manager 直接接入 `FFmpegKit`，app target 现在可以直接 `import FFmpegKit`。
- 保留现有 KSPlayer 播放链路，先验证 FFmpegKit SPM 在 Xcode 26 / GitHub Actions 下能否稳定解析和链接，避免一次性替换导致播放页不可用。
- GitHub Release 现在读取 `RELEASE_NOTES.md`，后续发布会包含本版本修复说明。

## 后续播放方案

`FFmpegKit` 是编解码/转封装库，不是播放器 UI。若本次 CI 验证通过，下一步可以基于它做 DASH 音视频合流/转封装，再交给播放器播放；如果目标是直接播放 1080P60+，更接近 PiliPlus 的方案是 `libmpv`/media-kit 类播放内核。
