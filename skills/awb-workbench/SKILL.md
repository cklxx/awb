---
name: awb-workbench
description: tmux milestone board for many agents (awb). Use when running several agents in tmux (claude / codex / any CLI) and watching only each agent's goal and milestone progress, not its output; when gating deliverables with awb check (including Lean 4); when messaging agents; when deciding subagent topology from the project's module architecture; or when the user mentions an agent board, workbench, milestone board, multi-agent progress, 看板, 工作台, or awb. Output follows ASD-STE100.
---

# awb — tmux agent workbench

单个 POSIX sh 文件（依赖 `tmux`、`jq`；Lean 验收另需 elan）。仓库：https://github.com/cklxx/awb。
`.awb/events.jsonl` 是唯一的事实源（只追加）。`awb skill` 随时打印本手册。
安装或更新 awb 与本 skill：

```sh
curl -fsSL https://raw.githubusercontent.com/cklxx/awb/main/install.sh | sh
```

## 术语定义

| 术语 | 定义 |
|---|---|
| 看板 | 给目标负责人看的一屏视图。只放他要决策的事。 |
| 里程碑 | 一个可独立验收的交付单元。有唯一 ID、验收命令、完成标准。 |
| 验收门 | 主理人选定的检查命令。`awb check` 运行它，通过记 ⊢，不通过打回。 |
| 任务 | 目标下的一棵任务树上的节点。`awb task` 规划，`awb send` 派发。 |
| worker | 执行任务的 agent（claude / codex / 任意 CLI / subagent）。 |
| 主理人 | 唯一和用户对话的 agent。拆任务、写契约、跑验收门、做集成。 |
| 契约 | 主理人写的 `CONTRACT.md`。含目标、产出格式、验收标准、口径定义。组织间唯一的接口。 |
| 异步可 commit | 每个里程碑的产出能独立 commit；里程碑之间无阻塞等待；信息交互全部异步。 |

## 基础标准

- **S1 里程碑**：一个里程碑对应一个 commit 单元。产出必须能独立合并，不依赖其他里程碑的未完成部分。
- **S2 完成定义**：只有验收门通过才算完成。worker 自称 done 不算完成。
- **S3 异步**：信息交互全部异步。A 完成里程碑后把事件入队，B 在自己方便时取用。任何"等我一下"的设计都是错的，重画拓扑。
- **S4 事实源**：`.awb/events.jsonl` 只追加，不修改历史。看板每秒折叠事件重绘。
- **S5 看板纪律**：一行上看板，当且仅当它是负责人要做的决策，或目标进度发生变化。agent 之间的协调只在出异常时出现。

## 新建 Sub 决策逻辑

组织是任务的函数。按以下 7 步决定是否新建 subagent、建几个、怎么连。
完整方法论见 `docs/multi-agent-org-manual.md`（两轮对照实验沉淀）。

| 步骤 | 动作 | 输出 |
|---|---|---|
| 1 | 列出项目的模块分布与模块间依赖，画成 DAG | 模块清单 |
| 2 | 判定任务类型：模块并行型（无依赖，可独立交付）或阶段流水线型（强依赖，前阶段输出是后阶段输入） | 任务类型 |
| 3 | 映射拓扑。并行型：每个模块一个 Owner。流水线型：每阶段一个 role（例：Profiler → Reworker → Verifier） | 拓扑图 |
| 4 | 估算各阶段耗时。拆分当且仅当：预估总耗时 > 固定开销（上下文加载约 2 分钟 + 契约编写约 3 分钟）+ 协调成本（约 1 分钟/角色）。经验值：40 分钟 timebox 的任务值得拆；5 分钟任务不值得拆。验证阶段占比超 50% 时，优先拆出 Verifier | 拆分决策 |
| 5 | 写契约 `CONTRACT.md`。无契约不派发 | 契约 |
| 6 | 派发。每个 sub 只读契约加目标文件（信息节食），不读全量上下文 | 派发记录 |
| 7 | 验收门。每个里程碑 `awb check`；最终 Verifier 独立复核 | ⊢ 记录 |

Agent 特点决定以上参数：

- 生成便宜，验证贵。验证阶段实测占 58%，优先拆出 Verifier。
- 上下文是硬约束。信息节食后，Profiler 2.5 分钟完成单 agent 8 分钟的审计。
- 无长期记忆。CONTRACT.md 是唯一的组织资产，隐性知识必须写进去。
- 警惕自信的假阳性。Verifier 必须独立复现验收，不是"再检查一遍"。
- 主理人是单点瓶颈。跨角色消息全经主理人，限一句话事由；任务再大需拆分主理人。

## 异步可 commit 协议

1. 里程碑即 commit 单元。commit 信息写清里程碑 ID 与验收结果。
2. 异步交接。产出事件写入 `.awb/events.jsonl`，下游在自己节奏取用，不等待、不阻塞。
3. 合并规则。主理人做集成；冲突时以契约为准，不以口头约定为准。
4. 禁止同步等待。任何"等 B 做完 A 才能动"的安排，改成"A 先交付可 commit 的中间态"或重画拓扑。
5. 验收门内允许自主修正。小偏离由 role 自行修复，不升级成跨角色沟通。

## 主 agent 协议

用户只和一个 Claude（主理人）对话，看板只用来看。工作单元是任务。
主理人按以下流程走，不让用户敲命令：

| 步骤 | 命令 | 说明 |
|---|---|---|
| 1 | `awb up` | tmux 内在当前 pane 右侧开看板（已开则复用）；tmux 外建 session 并打印用户要执行的唯一命令 |
| 2 | `awb goal "<目标>"` | 首行是标题（短），后几行写定义、度量口径、范围。状态不进 goal，进 `awb news` 或任务 |
| 3 | `awb tui -g <组> <id> <名>` | 每个并行任务起一个 worker。等 worker 的 Claude 就绪，打印 `<id> session: <会话名>`。若提示回答目录信任问题，让用户在对应 pane 确认，awb 不代做这个决策 |
| 4 | `awb task <id> todo "<步骤>" [<父>]` | 排任务线。需要负责人决策的点记为 `ask` 任务 |
| 5 | `awb send [--under <父>] <id> "<一句话任务>"` | 派发。打印的消息带 key `[awb <id>#<key>]`，用 SendMessage 发给 worker 会话（`notify_when_idle: true`）。消息发出前 worker 收不到任何东西。已规划的任务用 `awb send <id> <task-id> ["<消息>"]` 发送。每个 worker 同时只开一个任务，收到回复再发下一个 |
| 6 | `awb reply <id> <key> "<一句话结果>"` | 收到 `[awb <id>#<key>]` 开头的回复，任务完成。带 key 的进度汇报不是结果：回它，任务保持 open。key 对不上的回复是过期或重复。带 key 的回复之后会话变 idle，看板记异常，直到主理人跑 `awb reply` |
| 7 | `awb idle <id>` | 收到 idle 通知。第一次打印 ask，把它 SendMessage 出去（同样 `notify_when_idle`）；第二次记 blocked，告诉用户（worker 会话大概率在等它的用户批消息）。绝不只凭 idle 通知记 done |
| 8 | `awb fail <id> "exited"` | worker 退出，它的 open 任务丢失。用同样 id `awb tui` 重启，再 `awb send` 重发（新 key，旧 key 的迟到回复算过期） |
| 9 | `awb block <id> "等 #N"` / `awb unblock <id>` | worker 等外部事项（PR、issue，记作 `#N`）。两个 worker 等同一个 `#N`，看板记瓶颈 |
| 10 | `awb check <id> -- <命令>` | 验收。worker 的自称不是结果，主理人选定命令并运行它。通过记 ⊢，不通过在 `.awb/check-ID.log` 留原因并通知 worker（`AWB_NOTIFY=0` 关通知）。验收文件（测试、ACCEPT.lean）放在 worker 目录之外 |
| 11 | `awb pr <id> -- <命令>` | 自己再跑一遍验收，通过才开 PR。`awb merge PR` 只认当前 head 的 approve 加 `AWB_REQUIRE_CHECKS` 指定的绿检查 |
| 12 | `awb view --json` / `awb view --once` | 读看板。JSON 含 goal、metric、need、anomalies、agents、tasks、checks |

看板还只读 worker 的 Claude 会话记录，记录每个 SendMessage，不替你关任务。
`▲ 待批准` 是权限对话框（告诉用户，awb 不代点）。会话自报与记录矛盾的，进"会话实况"。
重启或压缩后，`awb peers` 列出所有 agent 的会话、状态、open 任务 key 与静默时长，用 `awb idle` 逐个续上。

多看板：每个项目目录一个 `.awb`，或设 `AWB_DIR`。worker pane 继承所属看板的 `AWB_DIR`。
拿 awb 做实验的 worker，每条命令单独设 `AWB_DIR`。每次写入在 stderr 打印 `awb: recorded in <看板>`，核对是你想要的看板。

`awb-lark` 配好后（`awb-lark where` 打印群），在目录里跑一次 `awb-lark sync` 绑定；
之后看板运行时每分钟同步。测试用看板不绑定。

## 自报型 worker（`awb run`）

```sh
awb run -g build  a1 builder -- ./train.sh  # pane 里跑命令；exit 0 记 done，否则 failed
awb down                                    # 结束本看板 session（agent 的 pane 里拒绝执行）
```

另一个终端接入：`tmux -S .awb/sock attach -t awb`（深路径时 socket 在 `/tmp/awb-UID-HASH.sock`）。
pane 里的命令自带记录：exit 0 是 done，否则 failed。
agent CLI（codex 等）在 pane 里自己报里程碑，只报它自己的，open 任务未关时不报。把它
的 ID 写进 prompt：

```
You are on the awb board as agent <ID>. Before each stage run `awb now <ID> "<stage>"`,
after it `awb done <ID>`; if stuck `awb block <ID> "<reason>"`, then `awb unblock <ID>`;
when everything is done `awb finish <ID> "<result in one line>"`. Milestones state results,
not process, one per stage. Full rules: `awb skill`.
```

## 命令速查

`awb help` 按三组列出：任务循环（up、goal、tui、send、reply、idle、fail、
task、block/unblock、check、pr、merge、metric、news），自报型 worker
（run、start、now/done/finish），协调与读取
（peers、tell、nudge、hold/release、view、replay、down/reset）。

| 命令 | 要点 |
|---|---|
| `awb check ID -- CMD` | exit 0 记 ⊢。管道、`tail`、`ssh` 会丢 exit 状态，加 `--expect 正则` 要求输出里有一行匹配（例：pytest 用 `--expect '^=* ?[0-9]+ passed in'`）。`awb pr` 透传该参数 |
| `awb merge PR` | 只认当前 head 的 approve（review，或首行点名 head sha 且匹配 `AWB_APPROVE_RE` 的评论）加绿检查 |
| `awb peers` | `ID PANE SESSION STATUS [#KEY] [silent MINm]`。STATUS 取会话自报：busy/idle/waiting/shell。非 awb 起的会话，在 `.awb/panes` 里加 `ID PANE` 行 |
| `awb hold 资源 持有人` | 一个资源同时只一人持有。`awb hold` 列出持有表，怕互相干扰的脚本先读它 |
| `awb tell` | 往 pane 里打字。Claude worker 优先用 SendMessage |

设置：`AWB_STALE`（秒，默认 600）、`AWB_INTERVAL`（刷新秒数，默认 1）。
ID 字符集 `[A-Za-z0-9_-]`；先 `awb start` 注册 agent id，其他命令才能用它。
状态：◔ running · ✓ done · ▲ blocked · ✗ failed · ■ dead。

## 目标与指标

目标首行是看板与 Lark 卡片的标题（短），后几行写定义、度量口径、范围。
每次新的度量：`awb metric <名> <值> <目标> "<一句话备注>"`。
看板画历史曲线、相对首次读数的变化、按现有事件估算的达标时间。

| 参数 | 含义 |
|---|---|
| `--by <epoch>` | 工作截止（训练结束、deadline）。估算值落在其后显示"按当前趋势截止前达不到" |
| `--at <epoch>` | 历史读数的真实时间，不编造 |
| `--ref --step <步长>` | 对照基线，单独命名，按步长画在指标旁边，不进趋势线 |

`awb replay [步长]` 回放日志：异常按 episode 列出，然后是核心指标——
发出的任务及其结局（回复、`finish` 无回复、丢失、open）、每个"需要你"在看板上停留的时长、worker 重启次数。

## Lean 4 验收

`awb check <id> -- <awb 目录>/model/accept.sh <项目目录> ACCEPT.lean`：
跑 `lake build`，拒源码里的 `sorry`/`admit`，再检查 ACCEPT.lean。

1. ACCEPT.lean 只含顶层具名 `theorem`，且引用 worker 的定义：
   ```lean
   import Demo
   theorem acc_double (n : Nat) : double n = 2 * n := double_eq n
   ```
   `example`、`lemma`、`namespace` 或其他形式一律不通过（fail-closed）。
2. 拒收：`sorry`、自定义 `axiom`、`native_decide`、弱化重述。热机约 2 秒，不需 Mathlib。
3. 失败原因取 `.awb/check-ID.log` 最后一行，显示在看板该检查下方。
4. 只验 Lean 交付物。陈述弱，检查就弱。项目需 `lean-toolchain`（`~/.elan/bin` 的 elan 也认）。

## 验证链（Lean、TLA+）

| 项 | 内容 |
|---|---|
| 状态折叠 | `model/AwbModel.lean` 证明 4 条不变式；awb 里的 jq 折叠与编译后的 Lean 模型做差分测试（每次自检 200 条随机日志） |
| 审计 | 看板跑已证明的 Lean 监控器（`audit_iff_clean`：无报告当且仅当每个事件在其前缀下合规）。⊢ 与 PR 必须跟在通过的 check 后；check 被拒时不许 `done`。违规显示在"审计违规"下 |
| 模型构建 | 在 clone 里构建（`./install.sh` 在有 Lean 时跑 `lake build`）。没构建就没有审计，自检跳过差分测试 |
| 并发 | TLA+ 规约在 `model/tla/`，TLC 检查。`check`/`pr` 按 agent 串行；一个 check 只验它启动时的里程碑；同一 pane 的并发 `tell` 拿 pane 锁；`tell` 每次击键前重读会话注册表，不往已上报的对话框里打字 |
| 防伪造 | 门不信任 agent 能写的日志：`awb pr` 自己跑验收。伪造 check 事件最多在看板上放 ⊢，开不了 PR。有模型时看板取已证明折叠的 agent 状态，否则取 jq（测试已证等价） |
| 未送达 | 发给 idle worker 的任务，若发送前已 idle 且一直 idle，`AWB_UNDELIVERED` 秒（180）后标"消息可能没发出"。SendMessage 是你的步骤 |

## 给 awb 本体提问题：开 PR

修好再开 PR。不改正在用的安装副本，不推 main：

```sh
gh repo clone cklxx/awb /tmp/awb-fix-<slug> -- -q      # 无写权限：gh repo fork cklxx/awb --clone
cd /tmp/awb-fix-<slug> && git switch -c fix/<slug>
# 修好，加一条在该 bug 下失败的 selftest() 断言；改了折叠同步 model/AwbModel.lean，
# 改了协议同步 model/tla/（model/tla/tlc.sh 检查每个规约）
export AWB_DIR=$PWD/.awb                         # 本看板，绝不用你 pane 所属的看板
./awb start fix-<slug> fixer && ./awb now fix-<slug> "<一句话问题>"
git commit -am "<英文小结>"                      # 不加署名 trailer
./awb pr fix-<slug> -- ./awb selftest            # 验收通过才开 PR
```

PR 描述只写改动本身，不写 "Generated with ..."。PR 里不改 `VERSION`。
发版：每天至多一次，一个只 bump `VERSION` 的 PR，加对应的 `vX.Y.Z` tag，CI 发 release。
