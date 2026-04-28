## 本版本修复

- 按要求移除 KSPlayer、FFmpegKit、libmpv 等第三方播放/解码依赖，播放层统一收敛为原生 AVPlayer。
- 普通单 URL 视频改为 `AVURLAsset + AVPlayerItem + AVPlayerLayer` 播放，并注入 Referer/User-Agent/Cookie 等请求头。
- 1080P+/1080P60/4K DASH 音画分离视频继续使用 `DASHAssetLoader + AVMutableComposition` 合成远程视频轨和音频轨后交给 AVPlayer。
- 移除之前实验性的 DASH→HLS、本地 HTTP 代理、mpv 流式和 FFmpeg 合流代码，降低包体和复杂度。
- 诊断文本仍显示 `DASH-AVComposition`，用于确认高画质跑的是原生 AVComposition 路径。

## 说明

这个版本是纯原生 AVPlayer 版本：单流直接播放，音画分离 DASH 通过 AVMutableComposition 合成后播放。
