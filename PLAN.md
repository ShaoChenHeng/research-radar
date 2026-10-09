# Research Radar — 分阶段实施计划 (PLAN.md)

> 配套 [`ARCHITECTURE.md`](./ARCHITECTURE.md)。原则：**一次只做一个阶段**，每个阶段结束都是一个**能跑、可用**的系统，你验收后再进下一阶段。

---

## 0. 协作方式与全局原则

- **一次一个阶段**：我实现 → 你检查/试用 → 通过后再进下一阶段。中途不跨阶段改东西。
- **每阶段交付"可运行的系统 + 自测说明"**：你能亲自跑一遍验证。
- **复杂度递增、依赖前置**：先把"改了成本最高"的**契约**冻结，再叠功能；自动化放后面，等内容稳定。
- **安全**：不碰启动链/系统关键配置；动 systemd 前先备份并说明；每阶段可独立回退。
- **契约优先**（下面这些一旦定下尽量不改，改它们最贵）。

### 需尽早冻结的契约
| 契约 | 内容 |
|---|---|
| 日报路径 | `digest/YYYY/MM/YYYY-MM-DD.md` |
| 条目 ID | 当天顺序：`a1..aN`(①)、`b1..`(②)、`c1..`(③) |
| 状态文件 | `state/{seen,curriculum,linux,feedback,runs}.jsonl` |
| **配置文件** | **`config.toml`**（唯一可调文件：代理/主题/数量/模型/通知…） |
| 命令入口 | `radar run · fb · pdf · refresh · status` |

---

## 阶段总览（按依赖 + 复杂度排序）

| 阶段 | 目标 | 复杂度 | 依赖 | 估算 |
|---|---|---|---|---|
| **0** | 环境自检（报告） | ★ | — | 0.5 天 |
| **1** | 最小日报（仅板块①，手动） | ★★ | 0 | 1 天 |
| **2** | 状态 + 三板块（backlog 40×2、去重、间隔重复） | ★★★ | 1 | 2 天 |
| **2.5** | 栏目配置化 + 开源化（`[[sections]]`） | ★★★ | 2 | 1 天 |
| **3** | 反馈闭环（含 save 保存） | ★★★ | 2.5 | 2 天 |
| **4** | PDF 下载（手动 / save） | ★★ | 1（ID 规范） | 1 天 |
| **5** | 自动化（timer + 幂等 + KDE 通知） | ★★★ | 1–4 | 1.5 天 |
| **6** | 课程队列滚动更新（每周） | ★★★★ | 2 | 2 天 |
| **7** | 多主机同步 + 迁移 | ★★★★ | 全部 | 2 天 |

> 顺序理由：**契约（格式/ID/schema）先冻结** → 内容（①→①②③）→ 智能（反馈）→ 便利（PDF）→ 自动化 → 运维（滚动/同步）。把 systemd、git、模型判质这些"坑多"的环节放后面，避免返工。

---

## 阶段 0 · 环境自检（★，只读）—— ✅ 已完成（2026-10-06）
**结果**：见 [`docs/ENV-CHECK.md`](./docs/ENV-CHECK.md)。依赖/模型/通知/主源**均可用**；网络适配点：HF 用 `hf-mirror.com`、HN 用 Firebase API、语义学者加退避、可选代理 `127.0.0.1:<端口>`、`jq` 缺（用 python3 顶）。

**目标**：确认整套能落地，交一份报告，避免后面踩坑。

**检查项**
- `node` / `npx` 版本（MCP 依赖）
- 网络可达：`arxiv.org`、`news.ycombinator.com`、`huggingface.co`
- `opencode run --model <免费模型> "say ok"` 能返回
- `opencode run --model deepseek/deepseek-flash "say ok"` 能返回
- `notify-send` 在 **systemd user service** 里能发（最小测试）
- `git` / `flock` / `curl` / `date` 就绪

**交付**：`docs/ENV-CHECK.md`（逐项结论 + 缺口 + 需不需要装包）
**验收**：你能看到"哪些 OK、哪些缺、怎么补"
**回退**：无（只读）

---

## 阶段 1 · 最小日报（仅板块①，手动）—— ✅ 已完成（2026-10-06）
**结果**：`bin/radar run` 手动跑通，产出 `digest/2026/10/2026-10-06.md`（5 条，arXiv RSS）。
**实测调整**：arXiv API 会被限流 → 改用 **arXiv RSS 主源**；抓取改由 **runner curl 预抓**到 `state/raw/`，**agent 只读本地成文**。
**格式修订（按反馈）**：标题"细调→**微调**"、去掉板块序号、每篇用**小标题 `### [aN]` + 分点**（做了什么 / 结论 / 来源）、来源改 **Markdown 链接**、① 条数 **3–6**。

**目标**：打通 `opencode → 抓取 → 落盘` 的最短链路。

**交付**
- 目录骨架 + **`config.toml`（唯一可调文件：代理/主题/数量/模型…）** + `.opencode/opencode.jsonc`（模型 + **权限预授权**）+ `.gitignore`
- `bin/radar`（仅 `run`：**无锁/无 git/无通知**，直接从 `config.toml` 读参数，产出日报）
- skills：`daily-digest`、`paper-radar`（只做①）
- `references/digest-format.md`（格式规范，冻结契约）

**行为**：`radar run` → 抓 arXiv(`cs.CL,cs.LG,cs.IR`, 最近 2–3 天) + HN → 出 `digest/<date>.md`（仅①，≥3 条，带 `a1..` ID）。

**验收**：手动跑一次，得到一份格式正确的①日报。
**风险**：免费模型产出格式不稳 → 用 `references/digest-format.md` 收紧约束 + 校验。
**回退**：删目录即可，无系统改动。

---

## 阶段 2 · 状态 + 三板块（★★★）—— ✅ 已完成（2026-10-06）
**结果**：日报含三板块（① 5 篇 / ② 1 条 / ③ 2 条）；`seen` 去重与间隔重复生效（k01/l02/l04 已排期到次日）。
**交付**：`state/curriculum.jsonl`、`state/linux.jsonl`（各 40 条）、`state/seen.jsonl`、`bin/radar-state`、skills `curriculum`/`linux-tips`。

**目标**：补齐②③，实现"每日不同"。

**交付**
- 预制 `state/curriculum.jsonl`、`state/linux.jsonl`（**各 40 条**，含 `level/due`）
- `state/seen.jsonl` 去重台账
- 新 skills：`curriculum`、`linux-tips`；升级 `daily-digest`
- 间隔重复（SM-2-lite）算 `due`

**验收**
- 日报含①②③；
- **连跑两天**：①不重复、②③按 `due` 换不同条目。

**风险**：**schema 设计**——此阶段后尽量不改（改成本高）。会先把字段定死。
**回退**：状态文件可删/重建。

---

## 阶段 2.5 · 栏目配置化 + 开源化 —— ✅ 已完成（2026-10-06）
**结果**：栏目改由 `config.toml` 的 `[[sections]]` 驱动（`feed`/`queue` 两种 kind，可增删/改名/换主题）；新增 `config.example.toml`（开源模板）、`bin/radar-config`、`bin/radar-prompt`；skills 改为通用 `daily-digest`（原 feed-scan/queue-review 已合并进来）；数据下沉到**嵌套 `data/`**（独立私有仓），仓库定为「**代码公开 + 数据私有**」双仓。

**目标**：把写死的三栏改成可在 config 增删/改名/换主题；为开源做准备。

---

## 阶段 3 · 反馈闭环（★★★）—— ✅ 已完成（2026-10-06）
**结果**：`radar fb item/topic/mute/parse/list/prefs` 可用；`mute` 硬过滤、`topic`/`item` 加权、探索位、prompt 偏好简报均生效（实测：屏蔽词候选归零、`more lora` 后 LoRA 排最前、`parse` 读条目末尾的 `- **标记**：`）；`/feedback` 命令 + `feedback-ingest` skill 就绪（shell 白名单只放开 `radar fb`）。

**目标**：推荐不合口味可纠正。

**交付**
- `radar fb like|dislike|save|more|less|mute ...`
- 日报条目标记行解析（`- **标记**：`）
- `.opencode/commands/feedback.md`（`/feedback`）+ `feedback-ingest` skill
- 排序权重 / 硬过滤 / 提示注入 / 20–30% 探索位

**验收**：对某条 `like`/`dislike` 后，**次日**内容可见变化；`save` 能被记录。
**风险**：过拟合 → 探索位 + 衰减。
**回退**：`feedback.jsonl` 可清空。

---

## 阶段 4 · PDF 下载（★★）—— ✅ 已完成（2026-10-06）
**结果**：`radar pdf <id...>` / `--saved` / `--date D` 可用；识别 arXiv 与 hf-mirror 论文 id，下到 `data/papers/YYYY/MM/<id>.pdf`，并在日报该条下加 `- **本地**：[相对路径](…)`；`download=false` 的栏目（Linux）自动跳过（实测：a1、a2 下载有效 PDF，c1 正确跳过）。
**目标**：把 save/指定条目下成本地 PDF，供 Emacs 看。

**交付**
- `radar pdf <id...>` / `--saved` / `--date D`
- `papers/YYYY/MM/<key>.pdf` 布局 + 日报里的本地链接

**验收**：`radar pdf a1` 下到 PDF，Emacs 打开正常。
**风险**：arXiv 限速 → 加间隔/重试（低）。
**回退**：删 `papers/`（不入 git，无影响）。

---

## 阶段 5 · 自动化（★★★）—— ✅ 已完成（2026-10-07）
**结果**：systemd user `research-radar.timer`（`OnBootSec=90s` + 每日 09:00 + `Persistent`）已启用；`bin/radar run` 加 **flock 锁 + 当日幂等（`--force` 可覆盖）+ 网络等待 + 成功/失败通知**（`bin/notify.sh`，notify-send→kdialog 回退）。手动 `systemctl --user start` 实测跑通（48s，生成 2026-10-07 日报），timer 下次 **10-08 09:00**。
**目标**：开机自动、每日一次、桌面提示。

**交付**
- `~/.config/systemd/user/research-radar.{service,timer}`
- `flock` 锁 + 当日幂等；`bin/notify.sh`；网络等待轮询

**验收**：重启后 **90s 内自动**出日报、当天**只出一次**、KDE 提示 **`日报已生成`**。
**风险**：systemd 用户服务的 DBus 通知、`network-online` 依赖 → 有回退（kdialog/日志）。
**回退**：`systemctl --user disable --now research-radar.timer`。

---

## 阶段 6 · 课程队列滚动更新（每周）（★★★★）—— ✅ 已完成（2026-10-07）
**结果**：`radar refresh` 可用——**归档**（显式 `learned` 或 `times >= learned_after`）+ **补新**（模型按 level 递进提案，refs 逐条 `curl` 校验）；**到点先生成复习报告 `data/review/<日期>.md` 并通知**（`radar review new/apply`：打标+评语 → learned 归档/反馈/评语注入补新）；`radar run` 距上次 `>= refresh_days` 天自动触发。实测各队列 40→45。
**目标**：队列随学习进度滚动。

**交付**
- `curriculum-refresh` skill + `radar refresh`
- `radar run` 开头检查 `≥7 天` 触发
- `level` 递进（基础→进阶→前沿）、已学归档（`status=learned`）

**验收**：手动 `radar refresh` 后，队列有变化（归档 + 补新），且内容合理。
**风险**：模型判质不稳 → 结果落文件、你可手改。
**回退**：状态文件可回滚（git 历史）。

---

## 阶段 7 · 多主机同步 + 迁移（★★★★）—— ✅ 已完成（2026-10-10）
**结果**：`data/` 独立私有仓接上 GitHub remote；`bin/radar` 运行前后 `pull --rebase --autostash` / `push`，且**只提交白名单路径**（`digest/ review/ state/{seen,curriculum,linux,feedback,runs}.jsonl state/refresh.json state/sessions .gitignore`），`state/raw/`、PDF 等私人/大文件不参与；新增 `[general] generate_on` 主机判定（非主生成机只同步、不生成，可两台都装 timer）；`sync_pull` 遇残留 rebase 冲突自动 `abort`；修复 `bin/radar` 在无 `hostname` 命令的机器上取空主机名（改 `uname -n`）；迁移脚本 `bin/radar-setup-host` 修复「已在仓库内运行」路径 bug。迁移流程见 [`docs/PORTING.md`](./docs/PORTING.md)。

**目标**：换机一键、双机同步。

**交付**
- data 私有仓 remote；`bin/radar` 的 `pull --rebase` / **白名单** `commit push`
- `bin/radar-setup-host`（依赖检查、软链、可选装单元）替代原计划的 `bootstrap.sh`
- `.gitignore` 排除 `config.toml`/`profile.md`/`data/`/`*.bak-*`；`data/.gitignore` 排除 `state/raw/`、`*.pdf`、`state/.run.lock`

**验收**：新机 `git clone` 两仓 + `radar-setup-host` 后能跑；两机能同步 `digest/state`。
**风险**：双机同日冲突 → `generate_on` 单写者 + 运行前 pull + 白名单提交。
**回退**：git 可回滚；卸单元即可。

---

## 每阶段的"完成定义"（DoD）
1. 我能给出**可运行命令**，你亲自跑通；
2. 对下一阶段**契约无破坏**（格式/ID/schema 不变或向后兼容）；
3. 有**回退办法**；
4. 更新 `ARCHITECTURE.md`/本文件的相应状态。

## 进展
- **阶段 0 ✅ 完成** → [`docs/ENV-CHECK.md`](./docs/ENV-CHECK.md)
- **阶段 1 ✅ 完成** → 手动 `bin/radar run` 已产出 `digest/2026/10/2026-10-06.md`
- **阶段 7 ✅ 完成**（多主机同步 + 迁移：私有 data remote、白名单同步、`generate_on` 主机判定、`bin/radar-setup-host`）
- **8 个阶段全部完成** 🎉
