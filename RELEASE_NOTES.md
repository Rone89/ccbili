## 本版本修复

- 回退上一版的 Dart UA：验证后发现它会让接口降级到 720P。
- 对齐 PiliPlus 的 `try_look` 逻辑：只有未登录时才携带 `try_look=1`，已登录请求不再携带该参数。
- 保留 Cookie 诊断与 PiliPlus WBI 参数，继续观察 `dash` 是否返回 `112`。

## 说明

请测试后反馈黄色诊断。重点看登录态下不带 `try_look` 后，`accept`/`dash` 是否恢复 `112`。
