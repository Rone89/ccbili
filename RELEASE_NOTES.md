## 本版本修复

- 新增 DASH→HLS 诊断状态，用于定位 1080P+/4K 仍黑屏的问题。
- HLS 清单生成时记录 video/audio sidx 分片数量、target duration、video/audio index_range。
- 本地 HLS 代理记录 AVPlayer 实际请求次数、HTTP 状态码、请求 Range、响应 Content-Range、返回字节数。
- 播放诊断打开时，如果当前路径是 `DASH-to-HLS-local`，会动态追加 `manifest=... proxy=...` 信息。
- 每次加载高画质 HLS 前会重置诊断，避免旧请求状态干扰判断。

## 说明

请打开“我的 → 播放诊断”，重新播放 1080P+/4K 后把完整黄色诊断文本发我。重点看是否出现 `proxy#`：如果没有，说明 AVPlayer 没请求本地分片；如果有 403/416/502，就能继续针对 Range 或请求头修。
