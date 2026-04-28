## 本版本修复

- API 已确认能返回 1080P+/4K DASH URL 后，黑屏定位为播放器处理远程分离音视频的问题。
- 新增 AVFoundation DASH 播放器：分别加载远程视频轨和音频轨，使用 `AVMutableComposition` 组合后播放，绕开 libmpv/KSPlayer 当前黑屏路径。
- DASH 源切换到 AVFoundation 组合播放器，普通合流源仍走原 KSPlayer 路径。
- 播放诊断文本增加尾部截断，减少超出视频框。

## 说明

请测试 1080P+/1080P60 是否能出画并有声音。如果加载变慢但能播放，下一步会做缓存和加载提示优化。
