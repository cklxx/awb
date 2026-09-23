---
name: awb-workbench
description: tmux 多 agent 里程碑看板（awb）。当需要在 tmux 里同时跑多个 agent（claude / codex / 任意 CLI）并实时只看每个 agent 的目标与里程碑进展（不是过程输出）、用 awb check 做验收（含 Lean 4）、通知 agent，或用户提到 agent 工作台 / 看板 / workbench / 里程碑板 / 多 agent 进度 / awb 时使用。
---

# awb — tmux agent 工作台

单文件 POSIX sh（依赖 `tmux`、`jq`；Lean 验收另需 elan）。仓库 https://github.com/cklxx/awb 。
`.awb/events.jsonl` 是唯一事实源（append-only），看板每秒从事件折叠状态重绘。
本手册随时可用 `awb skill` 打印（codex 等没有 skill 机制的 agent 也用这个）。

安装 / 更新（awb + 本 skill）：

```sh
curl -fsSL https://raw.githubusercontent.com/cklxx/awb/main/install.sh | sh
```

## 快速开始

```sh
awb up                                      # tmux 会话：看板在上，work 区在下
awb goal "本次总目标"
awb run -g build  a1 builder -- claude      # work 区开 pane 跑一次性命令；-g 分组；退出码 0→done，否则 failed
awb run -g review a2 critic  -- codex
awb tui -g main helper 小助手 "首个任务"      # 常驻交互式 claude TUI（中文），自动注入工作规则
awb down
```

另一个终端 attach：`tmux -S .awb/sock attach -t awb`（项目路径很深时 socket 在 `/tmp/awb-UID-HASH.sock`）。

## 命令

| 命令 | 作用 |
|---|---|
| `awb goal TEXT` | 设置总目标 |
| `awb task ID STATE [TEXT] [PARENT] [OWNER]` | 任务树节点，STATE：todo/wip/review/blocked/done/drop/ask；重发同 ID 即更新；ask = 需要人拍板 |
| `awb news TEXT` | 一条进展动态，看板显示最近 5 条 |
| `awb run [-g G] ID NAME -- CMD...` | 开 pane 跑命令；pane 异常关闭 → ■ dead |
| `awb tui [-g G] ID NAME [TASK]` | 常驻 TUI，命令取 `AWB_TUI_CMD`（默认 claude-db，没有则 claude） |
| `awb start ID NAME [KIND] [G]` | 注册非 pane / 远端 agent |
| `awb now ID MILESTONE` / `awb done ID [TEXT]` | 开始 / 完成一个里程碑（计时） |
| `awb block ID REASON` / `awb unblock ID` | 阻塞 / 恢复 |
| `awb fail ID REASON` / `awb finish ID [NOTE]` | 失败 / 完成最后里程碑并标记 done |
| `awb check ID -- CMD...` | 验收门：CMD 退出 0 → 里程碑记为 `⊢` 已验收；否则 agent 转 ✗，原因上板，日志 `.awb/check-ID.log` |
| `awb check ID --lean DIR [ACCEPT.lean]` | Lean 4 验收：`lake build`、源码无 sorry/admit、ACCEPT.lean 的定理对构建产物通过类型检查且只用标准公理 |
| `awb pr ID [gh 参数]` | 推当前分支并开 PR；该 agent 最近一次验收未通过则拒绝；正文自动列里程碑和验收步骤 |
| `awb tell ID MSG` | 把消息打进 agent 的 TUI pane 并回车（claude/codex 通用；Claude 忙时排队） |
| `awb peers` | agent 对应的 Claude 会话名与 busy/idle |
| `awb stale` / `awb nudge` | 列出静默 ≥ `AWB_STALE` 秒的 agent / 循环提醒它们 |
| `awb audit` / `awb state` | Lean 监控器报告协议违规（退出码 1 表示有）/ jq 折叠出的每个 agent 状态 |
| `awb render` / `awb reset` | 一次性渲染（tmux 外可用）/ 清空事件 |
| `awb skill` / `awb version` / `awb selftest` | 本手册 / 版本 / 端到端自检 |

看板参数：`AWB_VIEW=brief|full`（默认 brief）、`AWB_STALE`（秒，默认 600）、`AWB_INTERVAL`（刷新秒数，默认 1）。
ID 只能用 `[A-Za-z0-9_-]`。状态：◔ running · ✓ done · ▲ blocked · ✗ failed · ■ dead；分组标题 `◆ 组名`。

## 主 agent 协议

1. `awb goal` 写清目标，按职责 `awb run -g` / `awb tui` 拉起子 agent。
2. 子 agent 不知道自己的 ID：提示词里必须写明，并要求每个阶段 `awb now` / `awb done`（模板见下）。
3. 用 `awb render` 或读 `.awb/events.jsonl` 看进展。
4. agent 自报的 done 只是声明。交付物由你定验收命令，`awb check` 执行；验收被拒后 agent 无法变成 done，直到下一次验收通过。
5. 验收文件（测试、ACCEPT.lean）放在子 agent 工作目录之外，防止被改。

子 agent 提示词模板：

```
你在 awb 工作台上，agent ID 是 <ID>。开始每个阶段先 `awb now <ID> "<阶段>"`，
完成 `awb done <ID>`；卡住 `awb block <ID> "<原因>"`，恢复 `awb unblock <ID>`；
全部完成 `awb finish <ID> "<一句话成果>"`。里程碑写结果不写过程，每阶段一条。完整规则：`awb skill`。
```

## Lean 4 验收

1. ACCEPT.lean 只写顶层具名 `theorem`，引用子 agent 交付的定义/定理：
   ```lean
   import Demo
   theorem acc_double (n : Nat) : double n = 2 * n := double_eq n
   ```
   出现 `example`、`lemma`、`namespace` 或识别不了的写法直接判不过（fail-closed）。
2. 拦截：`sorry`、自造 `axiom`、`native_decide`、把命题换成更弱的版本。热启动约 2s，不依赖 Mathlib。
3. 看板「验收」区实时显示 `build → sorry → types → axioms`，失败步骤下方写原因。
4. 边界：只能验收 Lean 交付物；命题写得弱，验收就弱。其他语言用 `awb check ID -- <测试命令>`。
5. 项目需带 `lean-toolchain`；elan 装在 `~/.elan/bin` 也能找到。

## 全链路验证（Lean）

- 状态计算：`model/AwbModel.lean` 证明四条不变量；awb 里的 jq 实现与编译出的 Lean 模型在随机日志上做差分测试（selftest 每次 200 份）。
- 过程审计：`awb audit` 跑经过证明的 Lean 监控器（`audit_iff_clean`：报告为空 ⇔ 每个事件相对其前缀都合规）。规则：`⊢` 已验收标记前必须有通过的验收（抓伪造）；开 PR 前必须有通过的验收；验收被拒后不得报完成。违规显示在看板「审计违规」区。
- `awb pr` 在验收未通过或审计有违规时拒绝，并把 PR 记入事件日志供审计。
- 需要在克隆里构建模型（`./install.sh` 有 Lean 时自动 `lake build`）；没有模型时 audit 不可用、selftest 跳过差分测试。
- 边界：事件由 agent 追加，审计能发现伪造的 `verified`，但拦不住连验收事件一起伪造；jq 与模型是测试等价，不是证明等价。

## 通知 agent

- 验收被拒自动 `tell` 该 agent 原因和日志路径（agent 在自己 pane 里跑的验收不重复通知；`AWB_NOTIFY=0` 关闭）。
- 非 awb 启动的已有会话：在 `.awb/panes` 写 `ID PANE`，tell / peers / nudge 都读它。
- 主 agent 是 Claude 时：`awb peers` 查到会话名后用 SendMessage 发消息，走 Claude 自己的会话 socket，对方 turn 中途也能送达，还可 `notify_when_idle` 订阅空闲。

## 发现 awb 自身的问题：自动提 PR

使用中发现 awb 的 bug 或缺口，直接修并提 PR，不要改正在用的安装副本，不要推 main：

```sh
gh repo clone cklxx/awb /tmp/awb-fix-<slug> -- -q      # 没有写权限用：gh repo fork cklxx/awb --clone
cd /tmp/awb-fix-<slug> && git switch -c fix/<slug>
# 修复，并在 selftest() 里加一条会因该 bug 失败的断言；改到状态计算时同步 model/AwbModel.lean
export AWB_DIR=$PWD/.awb
./awb start fix-<slug> fixer && ./awb now fix-<slug> "<一句话问题>"
git commit -am "<English summary>"              # 不加任何署名 trailer
./awb check fix-<slug> -- ./awb selftest
./awb pr fix-<slug>                              # 验收未通过会拒绝
```

PR 描述只写改动，不加 "Generated with ..." 之类署名。合并由人决定；CI 只负责发版：推与 `VERSION` 一致的 `vX.Y.Z` tag 即发布 release。
