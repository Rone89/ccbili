# v0.1.135 - 深度优化 DASH/HLS 起播链路

## 更新内容

- AVPlayer 起播策略按快启+预缓存优化：关闭 `automaticallyWaitsToMinimizeStalling`，同时把 `preferredForwardBufferDuration` 提升到 30 秒。
- DASH/HLS 播放改为通过 `AVURLAsset` 创建播放项，并在替换播放器前预热 `playable`，最多等待 1.2 秒，避免异常网络卡住。
- 注入 `Referer`、`User-Agent`、Cookie、`Connection: keep-alive` 和 `Accept-Encoding: identity` 到 AVURLAsset，减少 B 站 CDN 限速和 Range 响应异常。
- 本地 HLS Server 支持 Keep-Alive，同一个连接可连续返回 Master、音频清单、视频清单。
- 媒体数据请求默认返回 302 Redirect 到 B 站真实 CDN，避免 App 侧搬运视频数据，降低 CPU、内存拷贝和发热。
- 启动阶段预取的 init/首片仍优先命中本地缓存，未命中才走 302，兼顾首屏速度和后续直连效率。
- M3U8 增加 `#EXT-X-START:TIME-OFFSET=0,PRECISE=YES`，并保留 `#EXT-X-INDEPENDENT-SEGMENTS`。

## 性能说明

- 首屏阶段：本地清单快速返回，AVURLAsset 先预热，播放器更早进入 ready。
- 数据阶段：音视频媒体片段不再经过 App 本地代理中转，系统直接从 CDN 拉流。
- Seek 阶段：独立片段标签和精准起点标签减少播放器对流稳定性的保守判断。

## 验证建议

- 打开 DASH 分离流视频，观察首屏出画是否更快。
- 播放 4K/HEVC/HDR 视频，确认 302 后仍能带上必要 Header 并正常起播。
- 暂停 10 秒后继续播放，观察是否已经继续预缓存。
- 拖动进度条，确认音画同步且不会频繁卡住。
- 连续切换多个视频，确认本地代理没有 404/502，且手机发热低于上一版。

## 打包说明

- GitHub Actions 会构建 Release 配置的未签名 IPA。
- 生成的 `ccbili-unsigned.ipa` 会作为 Release 附件上传。
- 未签名 IPA 需要自行重签名后安装到真机。
