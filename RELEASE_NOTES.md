# 本版本说明

## 继续优化播放器旋转一致性

- 全屏时不再把内联 `AVPlayerLayer` 迁移到全屏窗口，避免图层被移除/重挂导致瞬间黑屏或跳变。
- 全屏窗口改用独立镜像 `AVPlayerLayer` 绑定同一个 `AVPlayer`，内联层保持稳定。
- 对方向通知增加去抖，避免同一次旋转中重复触发横屏/竖屏状态切换。
- 保留系统方向转场和 `viewWillTransition(to:with:)` 的统一动画路径。
- 继续使用 `CATransaction` 管理图层隐式动画，减少和系统旋转动画冲突。

## 打包说明

- GitHub Actions 会构建 Release 配置的未签名 IPA。
- 生成的 `ccbili-unsigned.ipa` 会作为 Release 附件上传。