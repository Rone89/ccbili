## 本版本修复

- 坚持使用 DASH 流式播放，不回退本地完整下载合流。
- mpv 流式路径调整为 `vo=avfoundation` + `hwdec=auto-safe`，避免上一版 `gpu/wid` 在 iOS 嵌入视图里黑屏。
- DASH 音频改回 `audio-add select`，视频先 `loadfile`，再挂载音频轨，兼容当前 libmpv 命令集。
- 诊断文本标记为 `DASH/mpv-stream-v2`，方便确认运行的是本次流式路径。

## 说明

PiliPlus 秒开的核心是 DASH 视频轨和音频轨交给播放器流式读取。本版本继续沿这个方向修 mpv 的 iOS 渲染/音频挂载方式。
