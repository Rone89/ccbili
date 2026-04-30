# 本版本说明

## 修复横屏退竖屏动画

- 全屏播放器不再使用独立 `UIWindow` 承载，改为从当前控制器 `present` 原生全屏播放器控制器。
- 横屏转竖屏时先让全屏控制器跟随系统旋转回竖屏，系统转场完成后再无动画 dismiss。
- 避免“全屏窗口淡出”和“系统方向旋转”两个动画同时抢控制权，改善横屏退竖屏跳变。
- 保留独立镜像 `AVPlayerLayer`，避免内联播放器图层迁移造成闪烁。
- 保留方向去抖和 `CATransaction` 图层事务控制。

## 打包说明

- GitHub Actions 会构建 Release 配置的未签名 IPA。
- 生成的 `ccbili-unsigned.ipa` 会作为 Release 附件上传。