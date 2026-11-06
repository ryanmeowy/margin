# 04 · Swift ⇄ Web 桥契约（唯一真相）

两个 Web 面（面板 popover / 设置 settings）都是**纯渲染**：不发网络请求、不写 localStorage、不读系统信息。
所有数据由 Swift 通过 `applyState` 推入；所有意图通过 `postMessage` 上报。

## 1. 消息（Web → Swift）

```js
window.webkit.messageHandlers.bridge.postMessage({ type: "refresh" })
```

| type | 载荷 | 含义 |
|---|---|---|
| `ready` | — | 页面脚本就绪，可以推首帧状态 |
| `height` | `height: number` | 面板内容高度（含顶部 10pt 箭头预留），每次布局变化都要报 |
| `refresh` | — | 点「刷新」/ ⌘R |
| `openSettings` | `pane?: "account"\|"general"\|"notifications"\|"about"` | 打开设置窗口 |
| `showDetail` | `show: boolean` | 概览 ↔ 明细 |
| `exportCSV` | — | 导出 |
| `relogin` | — | 登录已过期，重新登录 |
| `quit` | — | 退出 App |
| `setPref` | `key: string, value: any` | 设置页控件变更（仅 settings 面） |
| `saveAccount` | `baseUrl: string, token: string` | 账户页「保存并验证」（仅 settings 面） |
| `checkUpdate` | — | 仅 settings 面 |
| `openLink` | `url: string` | 用默认浏览器打开 |

## 2. 状态（Swift → Web）

面板：`window.margin.applyState(state)`
设置：`window.margin.applySettings(state)`

字段定义以 [fixtures/state.sample.json](../fixtures/state.sample.json) 为准（含真实数值量级）。要点：

- `theme`: `"light" | "dark"` —— 由 Swift 按 NSApp.effectiveAppearance 决定，页面只写 `document.documentElement.dataset.theme`。
- `windows[]`: 已算好 `remainingPercent`（整数）、`resetLabel`（如 `"1 小时 12 分后重置"`）；页面不做任何算术。
- `usage.dailyState`: `"ready" | "loading" | "unavailable"`
  - `loading` → 柱子画骨架 + chip「统计中」
  - `unavailable` → 隐藏柱子，改一行文案（见样例 `usage.dailyFallbackText`）
- `usage.recent[]`: 最多 3 条，字段已格式化（`costLabel: "−$0.0022"` 用 U+2212）。
- `connection.state`: `"ok" | "expired" | "denied" | "offline" | "unconfigured"`，非 ok 时面板顶部显示连接条（点击触发 `relogin`）。
- 所有数字/金额/时间**只在 Swift 侧格式化**，Web 端原样显示，避免两套格式化规则。

## 3. 硬规则

1. **不自算**：百分比、Token 缩写、金额、倒计时、相对时间全部来自 state。
2. **不持久化**：不碰 localStorage / sessionStorage / IndexedDB。
3. **高度**：内容变化后 `setTimeout(reportHeight, 30)` 上报（不要用 rAF，离屏 WebView 会节流）；`reportHeight` 用 `document.documentElement.getBoundingClientRect().height`。
4. **主题**：只认 `state.theme`，不读 prefers-color-scheme（WKWebView 的匹配可能滞后）。
5. **动效**：保留原型节奏，但把面板打开动画交给原生；页面内动画只在首帧之后播放（`applyState` 里带 `animate: true|false`）。
6. **可点区域**：设置页顶部 46pt 区域留空给原生拖拽（`-webkit-app-region` 等价物由 Swift 用覆盖视图处理，页面不要放交互元素）。
7. **dev 模式**：`file://` 打开且无 `window.webkit` 时，页面自己 stub 一个 `postMessage` 并套用 `state.sample`，方便 Chrome 里调样式。

## 5. 实现回填（写码之后补的约定）

- `window.margin.setConstrained(bool)`：原生在内容高于 760pt 时调用，页面切到「头部/底部固定、只滚 `.pop-body`」布局；此时 `reportHeight` 改为量 `.popover.scrollHeight + 10`，原生据此判断能否解除约束。
- 面板每次 `show()` 会额外发一个 `panelDidShow` 事件（不经 Web），原生用它触发 7 天聚合。
- 设置面必须导出 `window.margin.applySettings` 与 `window.margin.showPane`；面板面必须导出 `window.margin.applyState`。
