# Hermes 桌面端 · Web 版（iOS 优先）

把 Hermes **桌面客户端自己的渲染层**（Electron 里的那套 React 界面）编译成 Web 版，挂在
`hermes dashboard` 的 `/app` 路径下，**手机（尤其 iOS）优先**，大屏上则是一个正常的桌面 Web 应用。

使用场景是"人在外面，用手机连回家里的网关干活"——所以这个版本**必须连网关在线**、
**不需要离线能力**。

- **代码分支**：`zswll2/hermes-agent` → `feat/desktop-web`
- **分支基线**：`ac0f4104c5`（本仓库 `patches/` 里的补丁基于此提交）
- **同步状态**：fork 的 `main` 已快进到上游 `main`（`dfc28b61a0cf`，2026-09-15）
- **改动范围**：`apps/desktop/**` + `hermes_cli/` 里 2 个文件（托管用），别无其它
- **上游意图**：**不谋求并入上游**（原因见下）

---

## 一、能获得什么

| 能力 | 说明 |
|---|---|
| 手机上跑真正的桌面界面 | 桌面应用自己的转写区、composer、面板、终端、会话侧栏——不是 dashboard 那套"嵌入式 TUI"的换皮 |
| 可安装到主屏 | `display: standalone`（无浏览器地址栏），适配刘海与状态栏 |
| 触屏正确 | ≥44px 触控目标、上下**双侧**安全区、抽屉 + 遮罩 + 显式关闭、长按排序且不抢滚动 |
| 更新安全 | 资源哈希化、HTML `no-store`、构建号自比对（服务端有新构建时提示/自动刷新一次） |
| 凭据安全 | **不使用 Service Worker**；启动时清理**属于本应用**的遗留 SW 与缓存（页面里带会话 token，缓存即凭据落盘风险） |

## 二、环境要求

- 一个可用的 `hermes dashboard`（本版本由 dashboard 的服务器托管）。
- 一个你自己的 **HTTPS** 域名（反向代理）。**HTTPS 是硬要求**：iOS 加主屏与 WebSocket 稳定性都依赖它。
- 建议 iOS 16+；Android / 桌面浏览器同样可用。

## 三、构建

```bash
cd apps/desktop
npm ci
npm run build:web          # 产物 → apps/desktop/dist-web/
```

## 四、部署（挂在 dashboard 的鉴权门之后）

`/app` 是**默认关闭**的可选面：不设 `HERMES_WEB_APP_DIST` 时，服务端行为与改动前完全一致。

```bash
# 1) 让 dashboard 指向构建产物
sudo mkdir -p /etc/systemd/system/hermes-dashboard.service.d
sudo tee /etc/systemd/system/hermes-dashboard.service.d/web-app.conf >/dev/null <<'EOF'
[Service]
Environment=HERMES_WEB_APP_DIST=/绝对路径/hermes-agent/apps/desktop/dist-web
EOF

# 2) 生效
sudo systemctl daemon-reload && sudo systemctl restart hermes-dashboard
```

然后访问 `https://<你的域名>/app`（未登录会 302 到 `/login`）。

**一行回滚：**

```bash
sudo rm -f /etc/systemd/system/hermes-dashboard.service.d/web-app.conf && \
sudo systemctl daemon-reload && sudo systemctl restart hermes-dashboard
```

> 注意：重启 dashboard 进程会**中断该进程正在承载的会话**，请挑空闲时做。反之，改了 Hermes 的
> **Python** 代码后必须重启进程，否则模型选择器接口会返回 `503 Restart required …`（stale-module 保护）。

## 五、iOS 添加到主屏

1. Safari 打开 `/app` 并登录。
2. 分享 → **添加到主屏幕**。
3. 从图标启动：standalone 全屏、状态栏透明、内容延伸到刘海之下——因为构建里带了
   `viewport-fit=cover`、`apple-mobile-web-app-capable=yes`、
   `apple-mobile-web-app-status-bar-style=black-translucent`、`<link rel="manifest">` 与 `apple-touch-icon`。
4. 没有注册 Service Worker，所以**没有离线模式**——这是设计（理由见第六节）。

## 六、手机行为契约

| 行为 | 规则 |
|---|---|
| 安全区 | `--safe-top` / `--safe-bottom` 驱动所有 fixed 面；外壳统一内衬一次，固定 chrome 用 `top: calc(基准 + var(--safe-top))` |
| 触控目标 | `(pointer: coarse)` 下按钮 ≥44×44px，输入框字号 ≥16px（避免 iOS 聚焦时自动放大） |
| 抽屉 | 左=会话；右=终端/文件/审查。两者都有全高遮罩（`z-30`，点击关闭）+ ≥44px 关闭按钮 + Escape |
| 排序 | 触屏**长按约 400ms（容差 5px）**才进入拖拽；快速上下滑动只滚动。鼠标拖拽仍是即时 |
| 边缘滑动 | **刻意移除**——会与 iOS 返回手势冲突；开侧栏请用标题栏按钮 |
| 底部堆叠 | `composer → 状态栏 → 安全区` 依次排布，永不重叠，且不进入 Home 指示条带 |
| 缩放 | 不做假的 `user-scalable=no`（iOS 会忽略）；改用 `touch-action: manipulation` + 16px 输入字号 |
| 冷启动 | 窄屏冷启动**不会**自动挂终端，给你的是聊天而非 shell |
| 更新 | 构建号在"首次加载"与 `visibilitychange` 两处比对；新构建只自动重载一次（防循环），另有手动提示 |

## 七、为什么不用 Service Worker

`/app` 的 HTML 里**注入了短时会话 token**。SW 一旦缓存这份 HTML（或接口响应），就等于把凭据写到
磁盘上，而且旧页面会带着过期 token 继续访问网关。而本产品的**离线不是需求**——每个操作都要连活着的
网关/WebSocket。

因此：① 不注册任何 SW；② 启动时**只清理属于本应用路径**的遗留 SW 与缓存——
- 只注销 `scope` 落在本应用路径（如 `/app/`）之下的注册，外来 scope 一律保留；
- 只删本应用命名前缀（`hermes-app-*`）的缓存，无法归属的一律保留。

第②条的边界很重要：`/app` 与 dashboard **同源**，上游若落地带 SW 的 PWA，粗暴"清所有"会把别人的
功能一起端掉。

## 八、代码在哪里

| | |
|---|---|
| **权威源（唯一）** | fork 分支 `zswll2/hermes-agent` → `feat/desktop-web`（32 个提交） |
| **本仓库** | 只放**说明文档** + `patches/`（从分支导出的 32 个补丁）+ `scripts/apply-patches.sh` |

这样分工的原因：fork 的 `main` 要能继续干净跟随上游；如果本仓库再放一份源码副本，立刻就是**两份代码漂移**。

## 九、如何应用补丁

**方式一（推荐）**：直接用分支

```bash
git clone -b feat/desktop-web https://github.com/zswll2/hermes-agent.git
```

**方式二**：把补丁打到上游某个基线上

```bash
bash scripts/apply-patches.sh          # 等价于下面的手动步骤
```

手动步骤：

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
git checkout -b feat/desktop-web ac0f4104c55d9de19bbe8ac431d2df97836d1865
git am /path/to/patches/*.patch
cd apps/desktop && npm ci && npm run build:web
```

> ⚠️ **补丁的基线是 `ac0f4104c5`**，而上游 `main` 已在此之后推进了 1,700+ 个提交。
> 直接把这些补丁 `am` 到最新 `main` 上**会有冲突**（新增文件部分通常能过，触碰既有文件的会失败）。
> 这也是"推荐方式一"的原因。

## 十、已知限制

- **没有离线**：无 SW、无缓存；网关不可达时应用也不可用。
- **iOS 部分行为未做自动化验证**：真实 `env(safe-area-inset-*)` 数值、键盘遮挡、后台恢复、iCloud 合并字符文件名。
- **不影响 Electron**：Web 模式是独立的 `vite --mode web` 产物 + 浏览器能力 shim，打包版行为不变。
- 无头环境看不到真实刘海：自动化测试用注入 `--safe-top/--safe-bottom` 的方式断言几何，所以真机测试仍然必要。

## 十一、长期维护

本 fork 的 `main` 跟随上游 `main`（用 GitHub 的 *merge-upstream* 快进）。分支属于"树外扩展"，
上游大幅前进后需要复核这几处接缝：

```
apps/desktop/src/lib/bridge/web-*.ts        # 浏览器能力 shim + 文件登记表
apps/desktop/src/api/client.ts              # REST 唯一出口
apps/desktop/src/styles.css                 # 安全区 + coarse-pointer 规则
apps/desktop/src/components/pane-shell/**   # 抽屉、遮罩、标签条
apps/desktop/src/app/chat/sidebar/**        # 排序传感器
hermes_cli/web_server*.py                   # /app 托管（鉴权门之后）
```

构建自检：`cd apps/desktop && npm run typecheck && npx vitest run src/lib/bridge src/lib src/store`

## 十二、为什么留在 fork（而不是上游）

上游 `web/AGENTS.md` 写得很明确：*"Do not re-implement the primary chat experience in React …
If you are rebuilding the transcript or composer for the dashboard, stop and extend Ink."*
本构建恰好就是那个"第二个聊天界面"，所以留在树外。两条相关决定方向一致：
[#70397](https://github.com/NousResearch/hermes-agent/issues/70397) 已关闭（"main already ships a
responsive drawer"），而 desktop-web 的 PR
[#98079](https://github.com/NousResearch/hermes-agent/pull/98079) 自 2026-08-29 起无人评论。

**上游唯一明确欢迎的是 PWA 安装面**（同一线程：*"genuinely valuable and still absent from main …
welcome as a standalone rebased PR"*）。它约 22 行——`web/public/manifest.webmanifest` +
`web/index.html` 里 6 行 meta + 3 个图标——按本文第七节的推理，**同样不需要 Service Worker**。

## 十三、许可

上游 Hermes Agent 为 MIT（Nous Research）。本仓库只含文档与补丁，不新增任何条款，见 `LICENSE`。
