"use strict";

// 纯渲染：所有文案/数值来自 applySettings(state)，意图一律 postMessage 给原生。
const $ = (id) => document.getElementById(id);

const STATUS = {
  ok: { title: "工作区已连接", pill: "正常", tone: "ok", icon: '<path d="m5 12 4 4 10-10"/>' },
  expired: { title: "登录已过期", pill: "已过期", tone: "danger",
    icon: '<circle cx="12" cy="12" r="8.5"/><path d="M12 8v5"/><circle cx="12" cy="16.2" r="0.8" fill="currentColor" stroke="none"/>' },
  denied: { title: "无权访问", pill: "无权限", tone: "danger",
    icon: '<circle cx="12" cy="12" r="8.5"/><path d="M8 12h8"/>' },
  offline: { title: "无法连接服务", pill: "离线", tone: "idle",
    icon: '<circle cx="12" cy="12" r="8.5"/><path d="M8 12h8"/>' },
  unconfigured: { title: "未连接", pill: "未配置", tone: "idle",
    icon: '<circle cx="12" cy="12" r="8.5"/><path d="M8 12h8"/>' },
};

let state = null;
let pending = null;      // "save" | "update"
let lastMaskedToken = "";

function post(message) {
  window.webkit.messageHandlers.bridge.postMessage(message);
}

const initialsOf = (text) => ((text || "").replace(/[^0-9A-Za-z\u4e00-\u9fa5]/g, "").slice(0, 2) || "").toUpperCase();
const setPressed = (attr, value) => {
  for (const b of document.querySelectorAll("[" + attr + "]")) b.setAttribute("aria-pressed", String(b.getAttribute(attr) === value));
};
const setSwitch = (id, on) => $(id).setAttribute("aria-checked", String(!!on));
const isOn = (id) => $(id).getAttribute("aria-checked") === "true";

function syncAutoRefresh() {
  $("intervalSelect").disabled = !isOn("switchAutoRefresh");
}

function syncThreshold() {
  const off = $("switchUsageAlert").disabled || !isOn("switchUsageAlert");
  $("threshold").disabled = off;
  $("thresholdRow").classList.toggle("is-disabled", off);
}

function setPane(name) {
  for (const b of document.querySelectorAll(".nav-item")) {
    const on = b.dataset.pane === name;
    b.classList.toggle("is-active", on);
    if (on) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
  }
  for (const p of document.querySelectorAll(".pane")) p.hidden = p.id !== "pane-" + name;
  $("content").scrollTop = 0;
}

function applySettings(next) {
  state = next || {};
  const prefs = state.prefs || {};
  const acct = state.account || {};
  const about = state.about || {};
  const conn = state.connection || {};
  const busy = !!state.busy;

  document.documentElement.dataset.theme = state.theme === "light" ? "light" : "dark";

  // 侧栏用户块（initials/displayName 可选，缺失时从邮箱或工作区名截取）
  $("userInitials").textContent = acct.initials || initialsOf(acct.email || acct.workspaceName);
  $("userName").textContent = acct.displayName || acct.email || acct.workspaceName || "";
  $("userPlan").textContent = acct.planLabel || "";

  // 连接状态卡
  const st = STATUS[conn.state] || STATUS.unconfigured;
  $("statusCard").dataset.tone = st.tone;
  $("statusTitle").textContent = st.title;
  $("statusPill").textContent = st.pill;
  $("statusIcon").innerHTML = st.icon;
  const meta = conn.message || acct.workspaceName || "";
  $("statusMeta").textContent = meta;
  $("statusMeta").hidden = !meta;

  // 账户
  $("baseUrl").value = acct.baseUrl || "";
  $("accountEmail").value = acct.email || "";
  lastMaskedToken = acct.tokenMasked || "";
  if (document.activeElement !== $("accessToken")) $("accessToken").value = lastMaskedToken;
  $("formNote").textContent = acct.lastVerifiedLabel || "";

  var options = state.workspaceOptions || [];
  var wsRow = $("workspaceRow");
  if (wsRow) {
    wsRow.hidden = options.length < 2;
    if (options.length >= 2) {
      var sel = $("workspaceSelect");
      var want = state.workspaceId || "";
      sel.innerHTML = "";
      options.forEach(function (o) {
        var opt = document.createElement("option");
        opt.value = o.id;
        opt.textContent = o.name + (o.kind === "team" ? " · 团队" : "");
        sel.appendChild(opt);
      });
      if (want) { sel.value = want; }
    }
  }

  var notice = state.authNotice || "";
  var noticeEl = $("authNotice");
  noticeEl.hidden = !notice;
  noticeEl.textContent = notice;
  noticeEl.classList.toggle("is-error", state.authTone === "error");

  $("logoutBtn").disabled = busy || conn.state === "unconfigured";

  // 通用
  setPressed("data-theme-choice", prefs.theme);
  setPressed("data-display", prefs.display);
  setSwitch("switchLaunch", prefs.launchAtLogin);
  setSwitch("switchAutoRefresh", prefs.autoRefresh);
  $("intervalSelect").value = prefs.interval || "15";
  $("switchLaunch").disabled = acct.launchAtLoginSupported === false;
  syncAutoRefresh();

  // 通知
  const notifOff = acct.notificationsSupported === false;
  setSwitch("switchUsageAlert", prefs.usageAlert);
  setSwitch("switchRenewal", prefs.renewalReminder);
  setSwitch("switchWeekly", prefs.weeklyDigest);
  $("threshold").value = String(prefs.threshold ?? 80);
  $("thresholdOut").textContent = $("threshold").value + "%";
  syncRangeFill();
  $("notifNotice").hidden = !notifOff;
  $("switchUsageAlert").disabled = notifOff;
  $("switchRenewal").disabled = notifOff;
  $("switchWeekly").disabled = notifOff;
  syncThreshold();

  // 关于
  $("versionPill").hidden = !about.version;
  $("versionPill").textContent = about.version ? "版本 " + about.version + (about.build ? " (" + about.build + ")" : "") : "";
  $("updateStatus").textContent = about.updateStatus || "";

  // busy：原生回推的全局忙碌位，按最后触发的动作决定哪个按钮转圈
  $("saveAccount").disabled = busy;
  var pending = !!state.authPending;
  $("relogin").disabled = busy || pending;
  $("relogin").textContent = pending ? "等待登录…" : "用浏览器登录";
  $("syncSession").disabled = busy;
  $("checkUpdate").disabled = busy;
  const saving = busy && pending === "save";
  const updating = busy && pending === "update";
  $("saveSpinner").hidden = !saving;
  $("saveLabel").textContent = saving ? "正在验证…" : "保存并验证";
  $("updateSpinner").hidden = !updating;
  $("updateLabel").textContent = updating ? "检查中…" : "检查更新";

  if (pending === "save" && !busy) {
    pending = null;
    if (conn.state === "ok") $("accountSuccess").hidden = false;
  }
  if (pending === "update" && !busy) pending = null;
}

// —— 导航 ——
for (const b of document.querySelectorAll(".nav-item")) {
  b.addEventListener("click", () => setPane(b.dataset.pane));
}

// —— 账户 ——
$("toggleToken").addEventListener("click", () => {
  const show = $("accessToken").type === "password";
  $("accessToken").type = show ? "text" : "password";
  $("toggleToken").setAttribute("aria-pressed", String(show));
  $("toggleToken").setAttribute("aria-label", show ? "隐藏访问令牌" : "显示访问令牌");
  $("toggleToken").querySelector(".eye-open").hidden = show;
  $("toggleToken").querySelector(".eye-off").hidden = !show;
});

$("accountForm").addEventListener("submit", (e) => {
  e.preventDefault();
  const baseUrl = $("baseUrl").value.trim();
  if (!baseUrl) { $("baseUrl").focus(); return; }
  const typed = $("accessToken").value.trim();
  // 未改动令牌时发空串：由原生保留钥匙串里的现有值
  const token = typed === lastMaskedToken ? "" : typed;
  $("accountSuccess").hidden = true;
  pending = "save";
  post({ type: "saveAccount", baseUrl, token });
});

$("relogin").addEventListener("click", () => post({ type: "browserLogin" }));
$("syncSession").addEventListener("click", () => post({ type: "importSession" }));
$("logoutBtn").addEventListener("click", () => post({ type: "logout" }));
$("workspaceSelect")?.addEventListener("change", function () {
  post({ type: "setWorkspace", id: this.value });
});

// —— 通用 ——
for (const b of document.querySelectorAll("[data-theme-choice]")) {
  b.addEventListener("click", () => {
    setPressed("data-theme-choice", b.dataset.themeChoice);
    post({ type: "setPref", key: "theme", value: b.dataset.themeChoice });
  });
}

for (const b of document.querySelectorAll("[data-display]")) {
  b.addEventListener("click", () => {
    setPressed("data-display", b.dataset.display);
    post({ type: "setPref", key: "display", value: b.dataset.display });
  });
}

const bindSwitch = (id, key, after) => {
  $(id).addEventListener("click", () => {
    const on = !isOn(id);
    setSwitch(id, on);
    post({ type: "setPref", key, value: on });
    if (after) after();
  });
};
bindSwitch("switchLaunch", "launchAtLogin");
bindSwitch("switchAutoRefresh", "autoRefresh", syncAutoRefresh);
bindSwitch("switchUsageAlert", "usageAlert", syncThreshold);
bindSwitch("switchRenewal", "renewalReminder");
bindSwitch("switchWeekly", "weeklyDigest");

$("intervalSelect").addEventListener("change", () => {
  post({ type: "setPref", key: "interval", value: $("intervalSelect").value });
});

// —— 通知 ——
function syncRangeFill() {
  var el = $("threshold");
  var min = Number(el.min || 0), max = Number(el.max || 100);
  var pct = ((Number(el.value) - min) / (max - min)) * 100;
  el.style.setProperty("--range-pct", pct.toFixed(2) + "%");
}

$("threshold").addEventListener("input", () => {
  $("thresholdOut").textContent = $("threshold").value + "%";
  syncRangeFill();
});
$("threshold").addEventListener("change", () => {
  post({ type: "setPref", key: "threshold", value: Number($("threshold").value) });
});

// —— 关于 ——
$("checkUpdate").addEventListener("click", () => {
  pending = "update";
  post({ type: "checkUpdate" });
});

// —— dev：无 WKWebView 桥时自造一个，Chrome 里可直接点 ——
const SAMPLE = {
  theme: "dark",
  busy: false,
  version: "0.1.0",
  connection: { state: "ok", message: "" },
  prefs: { theme: "system", display: "percent", launchAtLogin: true, autoRefresh: true, interval: "15",
           usageAlert: true, threshold: 80, renewalReminder: true, weeklyDigest: false },
  account: { baseUrl: "https://amr-api.open-design.ai", email: "ryan@example.com",
             tokenMasked: "amr_ck_example000000", workspaceName: "示例工作区",
             planLabel: "Go · 正常", lastVerifiedLabel: "上次验证：2 分钟前",
             launchAtLoginSupported: true, notificationsSupported: true },
  about: { version: "0.1.0", build: "1001", mode: "仅菜单栏", intervalLabel: "15 分钟",
           credentialStorage: "本机钥匙串", updateStatus: "上次检查：1 小时前" },
};

function devRespond(message) {
  if (message.type === "setPref") {
    state.prefs[message.key] = message.value;
    if (message.key === "theme") state.theme = message.value === "light" ? "light" : "dark";
    applySettings(state);
  } else if (message.type === "saveAccount" && !state.busy) {
    state.busy = true;
    applySettings(state);
    setTimeout(() => {
      state.busy = false;
      state.connection.state = "ok";
      state.account.lastVerifiedLabel = "刚刚验证";
      if (message.token) state.account.tokenMasked = message.token;
      applySettings(state);
    }, 900);
  } else if (message.type === "checkUpdate" && !state.busy) {
    state.busy = true;
    applySettings(state);
    setTimeout(() => {
      state.busy = false;
      state.about.updateStatus = "已是最新版本 · " + state.about.version;
      applySettings(state);
    }, 1000);
  } else {
    console.log("[margin dev]", message);
  }
}

if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.bridge) {
  window.webkit = { messageHandlers: { bridge: { postMessage: devRespond } } };
  const query = new URLSearchParams(location.search);
  const sample = JSON.parse(JSON.stringify(SAMPLE));
  if (query.get("theme")) sample.theme = query.get("theme");
  applySettings(sample);
  setPane(query.get("pane") || "account");
}

// 原生侧入口（契约：window.margin.applySettings / showPane）
window.margin = { applySettings: applySettings, showPane: setPane };

post({ type: "ready" });
