# 数据源调研 — OpenDesign 订阅用量 API（已实测）

> 验证方式：用本机 Chrome 的登录态（复制 profile 到 /tmp、CDP 取会话 Cookie、跑完即删，未落盘），
> 对 `amr-api.open-design.ai` 发起只读 GET。原始响应（脱敏）存 `fixtures/captured/`。
> 抓取时间：2026-11-06 01:56 (+08:00)，账号：personal 工作区 / go 档 / 月付。

## 1. 结论

| 问题 | 实测答案 |
|---|---|
| 有没有可用 API | 有，`https://amr-api.open-design.ai/api`，只读 GET |
| 认证 | 浏览器会话 Cookie `__Secure-better-auth.session_token`（`amr-api.open-design.ai` 域），API Key 无效 |
| 能不能画满面板 | 能，4 个请求：`workspaces/current` + `billing/snapshot` + `coding-plan-usage` + `billing/usage?limit=20` |
| 近 7 天逐日用量 | **能，但贵**：没有服务端按日聚合，必须翻页（实测 7 天 ≈ 2400 条 / 24 页 / 24 次请求后被 503 限流） |
| `billing/usage.summary` | 存在，但是**全量累计**（不随 from/to 变），正好是原型"总计 522.32M"那组数 |
| 个人工作区能不能看 usage | 能 |
| `billing/ledger` | 个人成员 403（团队才有），面板不需要 |

## 2. 端点与真实响应

Base：`https://amr-api.open-design.ai/api`；请求头：`Accept: application/json`、`Cookie: <session>`、工作区级接口加 `X-Vela-Workspace-Id: <workspaceId>`。

### 2.1 `GET /v1/workspaces/current`

```jsonc
{
  "userId": "…", "appUserId": "…",
  "workspaceId": "czvhyl…", "workspaceName": "…", "workspaceIconKey": "…",
  "workspaceType": "personal", "workspaceMemberId": "mn8y0h…", "role": "owner",
  "memberStatus": "active", "lifecycleState": "active",
  "billingState": "active", "planId": "go", "personalMembershipTier": "go",
  "providerMode": "…", "billingRecovery": null,
  "permissions": { "…": true }, "memberCount": 1,
  "activeWorkspaceId": "…", "activeWorkspaceVersion": 1
}
```

### 2.2 `GET /v1/workspaces/{id}/billing/snapshot`（主数据源）

```jsonc
{
  "schemaVersion": 1, "billingScopeVersion": 2, "billingMode": "shared",
  "billing": { "billingState": "active", "planId": "go" },
  "plan": { "tier": "go", "interval": "month",
            "currentPeriodStart": "2026-10-20T13:09:21.000Z",
            "currentPeriodEnd":   "2026-11-20T13:09:21.000Z",
            "cancelAtPeriodEnd": false, "status": "active" },
  "owner": { "workspaceMemberId": "…", "displayName": "…" },
  "memberCount": 1,
  "wallet": { "balanceUsd": "1.0000", "expiresAt": "2026-11-20T13:09:21.000Z", "updatedAt": "…" },
  "walletBreakdown": [{ "kind": "plan_grant", "amountUsd": "1.0000", "expiresAt": "…", "restriction": null }],
  "designPlanWindows": [
    { "kind": "5h", "windowStart": "2026-11-05T14:09:21.000Z", "resetsAt": "2026-11-05T19:09:21.000Z",
      "remainingCredits": "44954", "limitCredits": "50000" },
    { "kind": "7d", "windowStart": "2026-11-03T13:09:21.000Z", "resetsAt": "2026-11-10T13:09:21.000Z",
      "remainingCredits": "129567", "limitCredits": "150000" }
  ],
  "permissions": { "canUpgrade": true, "canRecharge": true, "canManageSubscription": true },
  "revisions": { "billing": "subscription:v1:3", "wallet": "shared-wallet:1" },
  "revisionClocks": { "billing": { "epoch": "…", "counter": "3" }, "wallet": { "epoch": "…", "counter": "1" } }
}
```

要点：
- **额度是"信用点"不是百分比**：5h = 50000 点，7d = 150000 点；面板百分比 = `round(remaining*100/limit)` → 90% / 86%。
- `wallet.balanceUsd` 是 **4 位小数字符串**（`"1.0000"`），显示要格式化成 `$1.00`。
- `plan.interval` 取值是 **`month` / `year`**（`billing/summary` 里是 `monthly` / `yearly`，两处都要兼容）。
- 到期日 `plan.currentPeriodEnd` 与 `wallet.expiresAt` 是同一个时间点（本期结束）。

### 2.3 `GET /v1/workspaces/{id}/billing/coding-plan-usage`

```jsonc
{
  "workspaceId": "…", "generatedAt": "2026-11-06T…Z",
  "eligible": true, "tier": "go",
  "windows": [
    { "policyId": "model_limit_policy_…", "durationSeconds": 18000, "resetMode": "anchored_recurring",
      "usedCredits": "5046", "limitCredits": "50000", "remainingCredits": "44954",
      "windowStart": "2026-11-05T14:09:21.000Z", "resetsAt": "2026-11-05T19:09:21.000Z" },
    { "policyId": "model_limit_policy_…", "durationSeconds": 604800, "resetMode": "anchored_recurring",
      "usedCredits": "20433", "limitCredits": "150000", "remainingCredits": "129567",
      "windowStart": "2026-11-03T13:09:21.000Z", "resetsAt": "2026-11-10T13:09:21.000Z" }
  ]
}
```

- 本账号两个窗口都是 `anchored_recurring`（固定锚点），不是滑动窗口；倒计时只用 `resetsAt`。
- 该接口比 snapshot 多了 `usedCredits` 与 `resetMode`，百分比算出来与 snapshot 一致（可交叉校验）。

### 2.4 `GET /v1/workspaces/{id}/billing/usage`

参数（Zod 校验，非法值 400 并返回 issue 列表）：
- `limit`：**最大 100**（`101` → 400 `too_big`）
- `cursor`：上一页的 `nextCursor`
- `from` / `to`：**必须 ISO 8601 datetime**（`2026-10-30T00:00:00Z` ✅；`2026-10-30` ❌；epoch 数字 ❌）
- `initiator` / `runtime`：可选过滤

响应：

```jsonc
{
  "workspaceId": "…",
  "entries": [{
    "id": "workspace-usage:…", "type": "model_usage", "balanceImpact": "debit",
    "amountUsd": "-0.0000",                       // ⚠️ design_plan 抵扣后为 0，不能用来显示
    "listChargedUsd": "0.0022", "listChargeCredits": "22", "chargeCredits": "0",
    "detail": "deepseek-v4.1-flash", "initiator": "示例用户", "actorDisplayLabel": "示例用户",
    "runtime": "deepseek-v4.1-flash", "model": "deepseek-v4.1-flash",
    "createdAt": "…", "consumedAt": "…", "settledAt": "…",
    "inputTokens": 435, "outputTokens": 1731, "cacheReadTokens": 128, "cacheWriteTokens": null,
    "usageType": "design_plan",
    "designPlanContribution": { "multiplier": 0.5, "amountUsd": "0.0011" },
    "billingMultiplier": 1, "recordedBillingMultiplier": 1,
    "unitPrices": { "input": 0.3, "output": 1.2, "cacheRead": 0.006, "cacheWrite": 0.3 }
  }],
  "summary": { "inputTokens": 534662990, "outputTokens": 4729010,
               "cacheReadTokens": 526193087, "cacheWriteTokens": 30720 },
  "filterOptions": { "initiators": ["…"], "runtimes": ["claude-haiku-5.5", "deepseek-v4.1-flash", "glm-5.3-flash", "gpt-6-luna"] },
  "totalCount": 5211, "nextCursor": "eyJ2…", "hasMore": true
}
```

**关键实测**：
1. `summary` 与 `totalCount` **不随 from/to 变化**（全量累计）。原型的"总计 522.32M / 输入 517.91M / 缓存 509.8M / 缓存写入 30.72K"正是这组累计值（本账号 534.66M / 526.19M / 30.72K）。
2. 没有 `/billing/usage/daily`、`/billing/usage/summary`、`/billing/usage/aggregate`、`/billing/analytics/daily`（全部 404），也没有 `groupBy` / `bucket` 参数（200 但忽略）。
3. 7 天窗口实测：**2400+ 条、24 页、77 秒**（连续请求约 24 次后开始 `503`）。每日 Token 实测：11-03 84.88M / 11-04 72.34M / 11-05 54.08M / 11-06（未过完）22.71M。
4. `billing/ledger` 个人成员 403 `workspace_member_permission_denied`。
5. `/v1/workspaces/{id}/dashboard` 当前返回 **503 database_unavailable**，不可作为依赖。

### 2.5 `GET /v1/billing/summary`（个人订阅视角）

```jsonc
{
  "balanceUsd": "1.0000", "creditsPerUsd": 10000,
  "balances": { "subscriptionCredits": "10000", "rechargeCredits": "0", "totalAvailableCredits": "10000" },
  "membershipTier": "go", "billingInterval": "monthly",
  "subscriptionStatus": "active", "subscriptionEntitlementStatus": "active",
  "subscriptionCancelAtPeriodEnd": false,
  "subscriptionCurrentPeriodStart": "2026-10-20T13:09:21.000Z",
  "subscriptionCurrentPeriodEnd":   "2026-11-20T13:09:21.000Z",
  "firstMonthIntroEligible": false,
  "availableActions": ["subscription_checkout", "billing_portal", …]
}
```

## 3. UI ← 字段映射（按实测修正）

| 面板元素 | 取值 | 备注 |
|---|---|---|
| 套餐名 `Go` | `snapshot.billing.planId` / `codingPlan.tier` | 首字母大写 |
| `生效中` | `snapshot.billing.billingState == "active"`；`plan.cancelAtPeriodEnd` 为真时显示"期末取消" | |
| `$7 / 月` | 本地价目表 `go: {month: 7, year: 84}` × `snapshot.plan.interval` | 真实档位是**月付**，不是原型的年付 |
| `年付 $84 · 11月20日到期` | `plan.interval == "year"` ? "年付 $84" : "月付 $7"；+ `plan.currentPeriodEnd`（本地时区 MM月dd日） | 原型固定写年付，必须改成跟随 |
| 环形 `90% · 5 hour` | 5h 窗口 `round(remaining*100/limit)` | 全账号实测 90% |
| `5 小时额度剩余 90%` | 同上 | 剩余点数是 44954/50000（不要把点数当百分比） |
| `X 小时 Y 分后重置` | `resetsAt - now` | 5h 窗口实测还剩 1 小时 12 分 |
| `7 天额度剩余 86%` | 7d 窗口 | 129567/150000 |
| `按量额度 $1.00` | `snapshot.wallet.balanceUsd` → `$%.2f` | `"1.0000"` → `$1.00` |
| `总计 534.66M` | `usage.summary.inputTokens + outputTokens` | 全量累计（与原型同源） |
| `日均` | 总计 ÷ 7 | 与原型算法一致（原型就是这么算的） |
| 四类 Token | `summary` 的四个字段 | |
| `最近请求` | 第一页 `entries`，按 `createdAt` 倒序，取 3 条 | 模型名用 `model`/`runtime` |
| 单条金额 `−$0.0022` | **`listChargedUsd`**（design_plan 用列表价，官方前端同样 `listChargedUsd ?? amountUsd`） | `amountUsd` 是 `-0.0000`，显示会变成 −$0.0000 |
| `Design Plan` 标签 | `usageType == "design_plan"` | |
| 输入/输出 Token（行内） | `inputTokens` / `outputTokens`，千分位 | 实测 435 / 1,731 这种量级（不是原型里的 90,251） |
| 菜单栏 `90%` | 最短窗口（5h 优先） | |

## 4. 近 7 天柱状图：三种可行方案

没有服务端按日聚合，只能自己拼。实测代价：**7 天 ≈ 24 页 / 100 条一页 / 约 2400 条**，连续请求 24 次触发 503。

| 方案 | 做法 | 代价 | 风险 |
|---|---|---|---|
| A（默认建议） | 面板打开时先用缓存渲染；后台 **250ms 间隔**翻页到跨过 7 天（上限 30 页），结果缓存 15 分钟；未就绪时柱子显示骨架 + "统计中" chip | 首次 ~8s 后台、24–30 次请求 | 仍可能被限流；失败则保留上次缓存并标注 |
| B | 不画 7 天柱状图，卡片改成"累计 Token / 日均 / 四类明细" | 1 次请求、0 额外负担 | 偏离原型（少一组柱子） |
| C | 柱子改为"5h / 7d 窗口已用额度"两根大柱 | 0 额外请求 | 语义变了，但更贴"额度"主题 |

我的建议：**A 做默认，B 做降级**（限流或离线时自动退回 B 的文案，不显示假柱子）。

## 5. 刷新与失败策略（更新）

| 场景 | 行为 |
|---|---|
| 面板打开 | snapshot + coding-plan-usage + usage(limit=20) 三个请求并发，<500ms 出数 |
| 定时刷新 | 15 分钟只刷 snapshot（轻）；面板打开时才补 usage |
| 401 | "登录已过期 · 重新登录"，保留旧数据标灰 |
| 403 | "当前工作区无计费查看权限"（ledger 类接口会遇到） |
| 429/503 | 指数退避；7 天聚合任务单独退避，失败不重试超过 2 次 |
| 数据校验 | `workspaceId` 必须与 current 一致；窗口 `remaining > limit` 或 `limit == 0` → 该窗口不可用；`kind` 重复 → 整块不可用 |

## 6. 抓包存档

`fixtures/captured/`：`workspaces.current.json`、`billing.snapshot.json`、`billing.coding-plan-usage.json`、`billing.usage.json`、`billing.summary.json`、`wallet.balance.json`、`workspaces.dashboard.json`（503 现场）。
含 workspaceId / memberId / 显示名，属于本机私有数据，不要提交到公开仓库；写文档/截图时按需打码。

### 2.6 `GET /v1/billing/subscription/offers`（价格来源）

```jsonc
{ "offers": [
  { "membershipTier": "go", "billingInterval": "monthly", "currency": "usd",
    "originalPriceUsd": "10.00", "finalPriceUsd": "10.00" },
  { "membershipTier": "go", "billingInterval": "yearly", "currency": "usd",
    "originalPriceUsd": "84.00", "finalPriceUsd": "84.00" },
  { "membershipTier": "plus", "billingInterval": "monthly", "currency": "usd",
    "originalPriceUsd": "20.00", "finalPriceUsd": "20.00" }
] }
```

- 面板价格 = 按「当前档位 + 当前计费周期」匹配到的 `finalPriceUsd`；匹配不到就隐藏价格行。
- 团队档按席位计价（`/v1/billing/team-plans` → `seatUnitAmountCents` + `minSeats`），个人面板不套用这张表。
