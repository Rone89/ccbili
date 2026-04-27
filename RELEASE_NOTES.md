## 本版本修复

- 参考 MiniBili 的取流方式，1080P+ 播放地址优先改用旧版 `/x/player/playurl` 接口获取。
- 保留 WBI `/x/player/wbi/playurl` 作为兜底：旧接口失败或只返回低清时自动回退。
- 继续显式携带桌面端 UA、Referer、Origin 和登录 Cookie，用于判断是否能真正拿到 1080P+ DASH URL。

## 说明

如果本版仍只能看到 720P，说明两个播放接口在当前登录态下都没有返回 1080P 及以上 URL；下一步需要把接口返回的 `accept_quality` 和选中视频流 id 直接显示在播放页，进一步定位账号权限或 Cookie 问题。
