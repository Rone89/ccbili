## 本版本修复

- 修复 1080P+/4K `DASH-AVComposition` 黑屏且进度显示 `00:00/00:00` 的关键问题：合成时长不再只依赖 `AVURLAsset.duration`。
- `DASHAssetLoader` 现在优先使用 `videoTrack.timeRange.duration`，其次使用 `audioTrack.timeRange.duration`，最后使用 B 站接口返回的 `timelength` 作为兜底。
- 调用 `DASHAssetLoader.createPlayerItem` 时传入 `source.duration`，避免某些 DASH 远程 asset duration 为 0 导致 composition 空时长。
- 插入视频/音频轨道时保留各自有效 start time，减少远程 DASH track 时间范围异常导致的插入失败。

## 说明

截图里的 `00:00/00:00` 表明 AVPlayerItem 合成成功但时长为 0，本版本优先修复 composition 时长来源。
