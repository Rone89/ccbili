## 本版本修复

- 继续对齐 PiliPlus 请求层：播放地址请求 `User-Agent` 改为 `Dart/3.6 (dart:io)`，并携带 `Accept-Encoding: br,gzip`。
- 黄色诊断文本新增 Cookie 状态：`sess/noSess`、`b3/noB3`、`b4/noB4`，用于判断是否缺少 `SESSDATA`、`buvid3`、`buvid4`。
- 保留 PiliPlus 同款 WBI playurl 参数与 legacy fallback。

## 说明

请反馈新版黄色诊断全文。重点看 `cookies=` 是否为 `sess,b3,b4`，以及 `dash` 是否出现 `112`。
