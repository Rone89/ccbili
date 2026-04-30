# v0.1.133 - Bilibili DASH 音视频分离转 HLS Master

## 更新内容

- 新增 `generateBilibiliDASHMasterManifest(...)`，把 Bilibili DASH 分离的音频 URL 和视频 URL 转成 AVPlayer 可直接加载的 HLS Master Playlist。
- Master Playlist 使用 `#EXT-X-MEDIA` 声明音频轨，并通过 `AUDIO="audio_group"` 在 `#EXT-X-STREAM-INF` 中关联视频轨，交给 AVPlayer 自动同步音视频。
- 视频和音频子清单都保留 `#EXT-X-MAP`，分别指向各自的 fMP4 初始化片段，解决初始化头缺失导致无法加载的问题。
- 支持 `#EXT-X-BYTERANGE`，继续适配 Bilibili SegmentBase/sidx 这种单文件多 range 的 DASH 形态。
- `CODECS` 会合并视频 codec 和音频 codec，避免只声明 `hev1` 时 AVPlayer 对音频轨识别不稳定。
- Master 和媒体清单全部走本地 HLS 代理的绝对 URL，避免相对路径解析失败。

## 性能说明

- 仍然只解析 sidx 并生成轻量字符串，不在主线程做复杂转换。
- 子清单 URL 会先预留，再一次性生成 Master/Video/Audio 三份清单，减少 AVPlayer 首屏加载时的清单依赖等待。
- fMP4 初始化片段和切片都复用同一个本地代理通道，保留请求头、Cookie、Range 请求能力。

## 验证建议

- 播放 DASH 分离流视频，确认能正常起播且有声音。
- 切换 4K/HDR 或 HEVC 清晰度，确认 `hev1`/HDR 内容能起播。
- 拖动进度条，确认音画同步且不会重新从头播放。
- 观察诊断信息，确认 Master、音频清单、视频清单都能被本地代理返回 200。

## 打包说明

- GitHub Actions 会构建 Release 配置的未签名 IPA。
- 生成的 `ccbili-unsigned.ipa` 会作为 Release 附件上传。
- 未签名 IPA 需要自行重签名后安装到真机。
