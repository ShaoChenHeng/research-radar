# Research Radar

> 免费优先、可迁移、多机同步、每日一次的科研雷达：自动汇总【① 微调/RAG 进展　② 领域知识　③ Linux】，按 `年/月/日` 归档，带反馈闭环与 KDE 通知。

- 设计：[`ARCHITECTURE.md`](./ARCHITECTURE.md)　计划：[`PLAN.md`](./PLAN.md)　环境：[`docs/ENV-CHECK.md`](./docs/ENV-CHECK.md)

## 当前状态
**阶段 6–7 已完成**：栏目由 `config.toml` 的 **`[[sections]]`** 驱动（含 **RSS** 源）；`profile.md` **画像**注入提示；`seen` 去重 + 课程间隔重复；反馈闭环；PDF 下载；自动化（systemd + 幂等 + KDE 通知）；课程队列每周滚动刷新 + 复习报告；**多主机同步**（私有 `data/` 仓 + 白名单推送 + `generate_on` 单写者）。

## 用法

先装一下命令（软链到 PATH，之后到处都能用；已解析软链，仓库位置无关）：

```bash
ln -sf "$PWD/bin/radar" ~/.local/bin/radar
```

然后：

```bash
radar                             # 直接打开界面（= radar tui）
radar run                         # 完整流程，生成今天的日报
radar run --date 2026-10-06       # 指定日期
radar run --dry-run               # 只打印"将要发给模型的 prompt"，不抓取、不调模型
radar run --no-fetch              # 跳过抓取，复用 state/raw/<date>/ 里已抓的数据
radar --help                      # 帮助
```

> 仓库内仍可用 `bin/radar ...`；装好后建议统一用 `radar ...`。

### 参数详解
| 命令 | 做什么 |
|---|---|
| `radar run` | 抓取（arXiv RSS / hf-mirror / HN）→ 解析候选 → 调模型 → 写到 `<日期>/<日期>.md` |
| `--date D` | 生成指定日期（默认今天），例如补跑昨天的 |
| `--dry-run` | **只看 prompt**：不联网、不调模型，用来检查会发给模型的内容 |
| `--no-fetch` | **复用已抓数据**：不再下载，直接用 `state/raw/<date>/`；改了格式/prompt 后快速重跑用它 |
| `--help` | 用法说明 |

**常用组合**
```bash
bin/radar run                # 平时
bin/radar run --dry-run      # 调试：先看看 prompt
bin/radar run --no-fetch     # 改了格式后重跑，不再联网
```

产出：`digest/YYYY/MM/YYYY-MM-DD/YYYY-MM-DD.md`（当天 PDF 也在这个日期文件夹里；Emacs 直接打开）。

### 内部细节
- **模型 fallback**：先用 `config.toml` 的 `[models].free`，全失败才用 `[models].fallback`。
- **中间文件**：`state/raw/<date>/`（原始抓取 + `candidates.jsonl` + `candidates_unseen.jsonl` + `selected.json`），已 gitignore。
- **`bin/radar-extract`**：把原始数据解析成候选（预筛）。**`bin/radar-state`**：`seen` 去重/记录 + 课程队列间隔重复（`queue-pick`）。

## 反馈
```bash
radar fb item like a1        # 喜欢某条（也可 dislike；save 见「下载 PDF」）
radar fb item learned b1     # 标记"已学会"（把该课程条目归档）
radar fb topic more "lora"   # 想要更多某主题（less 反之）
radar fb mute "crypto"       # 屏蔽某关键词
radar fb parse               # 解析日报的「- **标记**：」（like/dislike 反馈；learned 归档；confused 没懂；save 只下载）
radar fb list                # 看最近反馈
```
或在 opencode 里用 `/feedback 我喜欢 a1，别再来 crypto`。
反馈存 `data/state/feedback.jsonl`，会影响下一次的候选**筛选与排序**。

## 课程队列刷新
```bash
radar refresh                # 立即刷新（归档已学 + 模型补充新主题）
```
- `radar run` 会自动判断：距上次刷新 `>= refresh_days`（默认 7）天就先刷新；
- 归档规则：**显式标记**（在日报 `- **标记**：` 写 `learned`，`radar fb parse`）为主；`times >= learned_after`（默认 3）为兜底；
- 补新：模型按 `level` 递进提案，`refs` **逐条校验可访问**才收。

## 复习报告（周期复盘）
滚动更新到点时，`radar run` 会先生成一份复习报告并**KDE 通知**你：
```bash
radar review new     # 生成 data/review/<日期>.md（列本期展示过的条目）
radar review apply   # 应用你在报告里打的标记与评语
```
- 报告里每条有 `- **标记**：`（`learned`/`confused`/`like`/`dislike`）和 `- **评语**：`；
- `apply` 后：`learned` → 归档该课程条目；`like/dislike` → 反馈；**评语** → 反馈（并在下次刷新时注入提示，影响补新方向）。

## 画像访谈（完善 profile.md）
```bash
radar profile ask     # 模型针对画像缺口提问 → data/review/profile-<日期>.md
radar profile apply   # 把已作答的问题并入 profile.md
```

## 下载 PDF
```bash
radar pdf a1 a2        # 下指定条目（arXiv / hf-mirror 论文）
radar pdf --saved      # 下所有在日报里标了 save 的条目
```
> `save` **只是下载标记**（不进反馈）；反馈用 `like`/`dislike`。
- 存到**当天文件夹** `data/digest/YYYY/MM/<date>/`，**文件名 = 条目标题**；并在日报该条下加一行 `- **本地**：[相对路径](…)`；
- 只对 `[[sections]]` 里 `download = true` 的栏目生效（③ Linux 为 `false`，自动跳过）。

## 自动化（systemd，已启用）
```bash
bin/radar-install-units                         # 安装并启用 timer（本项目已装）
systemctl --user list-timers research-radar.timer
systemctl --user start research-radar.service    # 手动跑一次
journalctl --user -u research-radar.service -f   # 看日志
```
- **开机 90s 后** + **每日 09:00** 自动跑；同日已生成则**跳过**（`radar run --force` 强制重跑）。
- 进系统晚了也不漏（`OnBootSec` + `Persistent` 补跑）；生成前会等 **NTP 同步**，防切系统/时区错位。
- 跑完/失败会弹 **KDE 通知**（成功默认"日报已生成 · <日期>"）。
- 关闭：`systemctl --user disable --now research-radar.timer`。

## TUI（单栏读日报 + 就地打标）
```bash
radar                # 直接打开界面（默认最新一天）
radar tui            # 同上；[ / ] 切前一天/后一天，H 打开历史列表
```
- **单栏**、正文**渲染后**显示（去掉 `##/###/**`，字段转 `• 名称：值`、链接给文字+URL），整篇随宽度换行；**中文按双列宽对齐**。
- **窗口缩放会自动重排**（按新的宽度重新换行），不用退出重开。
- 光标**逐行在文档上移动**：移到 `标记：` 行**自动弹候选**；移到**含网址的行**，底部状态栏提示 `Enter 打开链接`。
- **`H` 打开「历史日报」列表**（像帮助那样浮层）：`j/k` 选日期、`Enter` 打开、`Esc`（或 `q`）取消。
- **`Enter` 只对「含网址的行」生效**：先把链接开在**你当前屏幕**的浏览器窗口里（不切屏），再把它置顶；arXiv 链接按编号精确匹配到新标签所在窗口。`Y` 复制链接（不开浏览器）。
- **`C` 与 opencode 细聊**：**直接进入对话**（不弹菜单）。默认接续「生成今天日报的那个 session」，模型已经读过候选、写过日报，上下文都在。若今天的日报是**别的主机**生成并同步过来的（本机没有那个 session），则用**本机固定的兜底 session**（`ses-radar-local-<日期>`，不存在即创建）并以一条预制 prompt 开场；**之后每次 `C` 都续同一个**。退出后界面自动恢复。
- 键位（Emacs 风）：`j/k` 或 `C-n/C-p` 逐行；`C-v/M-v` 翻页；`M-<`/`M->` 首尾；**`[` / `]` 前一天 / 后一天**；`H` 历史；`C` 对话；`l 喜欢 d 不喜欢 c 看不懂 s 收藏 e 学会`（或按数字）；`a` 应用；`o` 打开文件夹；`g` 重新读取文件；`?` 帮助；`q` 退出。
- 打标**直接写进当天 md 的 `- **标记**：` 行**；`a` 才生效（`radar fb parse`）。

## Emacs 侧（`emacs/radar.el`）
在 Emacs 里读日报、就地打标（结构化缓冲，**不是** markdown-mode）：
- **加载**：`~/.emacs.d/lisp/init-radar.el` 把仓库的 `emacs/` 加进 `load-path` 并 `(require 'radar)`；入口 **`C-c R`**（`C-u C-c R` 选日期）。
- **就地打标**：`标记：` 行渲染成**可点按钮**（like / dislike / confused / save|learned），点一下切换，**光标停在原按钮上不跳**；`l d c s e` 是等效快捷键；`a` 写回并应用（`radar fb parse`）。
- **键位**：`n` / `p`（或 `TAB` / `<backtab>`）跳条目；`RET` 打开链接；`[` / `]` 前 / 后一天；`g` 重读文件；`o` 打开当天文件夹；`?` 打开菜单（transient）；`C` 与 opencode 细聊（以仓库为工作目录启动 agent-shell，`session/load` **续当天那个 session**；本机没有该 session 时开新会话）。
- **打开链接**：统一走 `bin/radar-open`（Emacs 与 TUI 共用一套「当前屏打开 + 置顶」逻辑，arXiv 链接按编号精确匹配标签页）；本地 PDF 链接按**日报目录**解析成文件路径，先查存在性再打开（避免 KDE 弹 KIO 报错）。

## 配置
- **[`config.toml`](./config.toml)**：所有可调项。**日报有哪些栏目由 `[[sections]]` 决定**——增删/改名/换主题、每栏条数、关键词都在这里。
- **[`config.example.toml`](./config.example.toml)**：开源模板（新机 `cp config.example.toml config.toml` 再改）。
- **[`profile.md`](./profile.example.md)**：**用户画像**（`cp profile.example.md profile.md`）——写"我是谁、方向、偏好、不要什么"，会**注入选题与补新的提示**，让推荐更贴你。
- **`[rss] feeds`**：通用 RSS/Atom 源（博主/媒体）；某栏目 `sources=["rss"]` 即启用。
- **栏目级开关**：`require_keyword = false` → 该栏来源**不按关键词筛**（关键词仍用于排序），适合放轻松/有趣的综合源；`max_per_origin = 2` → **同一来源网站最多 N 条**（避免整栏来自同一个源；rss 候选带 `origin` 字段）；`groups = [{name,kw},…]` + `max_per_group = 2` → **同一子方向最多 N 条**（避免整栏全是同一个方向，如全是 LLM）；`note = "..."` → 给该栏加一句**自由提示**（会注入 prompt）。
- `.opencode/opencode.jsonc`：OpenCode 自身接线（模型/权限），与业务配置分开。
- **环境变量（可选）**：`RADAR_RSS_TIMEOUT`（抓 RSS 超时秒数，默认 120；planet.emacslife 这类 ~500KB 的大源需要）、`RADAR_TIMEOUT`（单次模型调用超时）、`RADAR_RETRIES` / `RADAR_RETRY_WAIT`（失败重试轮数 / 间隔秒）。

## 仓库结构（代码公开 + 数据私有）
```
research-radar/          # 公开代码仓（脚本/skills/文档/config.example.toml）
└── data/                # ★ 私有数据仓（独立 .git）：digest/<date>/{md,pdf} state/
```
- 日常只在 `research-radar/` 工作；`data/` 只管多机同步。
- 外层 `.gitignore` 掉 `config.toml` 与 `data/`。

## 多机同步
- **代码仓**公开（脚本/skills/文档/`config.example.toml`）；**`data/` 私有仓**（日报 + 状态），两者分开、同一个工作目录。
- `bin/radar run` 会**先 `pull` 后 `push`**，且只提交**白名单路径**（`digest/ review/ state/{seen,curriculum,linux,feedback,runs}.jsonl state/refresh.json state/sessions .gitignore`）——`state/raw/`、PDF、临时文件不会被瞎提交。
- **单写者**：`config.toml` 里 `[general] generate_on = "<主机名>"` 指定唯一主生成机；其它机器 `radar run` 只同步不生成，**两台都能装 timer**。
- 迁移/换机：`bin/radar-setup-host`；或直接 `git clone` 代码仓 + 私有 data 仓（`data/` 是嵌套仓，单独 clone）。详见 [`docs/PORTING.md`](./docs/PORTING.md)。

## 依赖
`opencode≥2` · `git` · `curl` · `python3`(≥3.11) · `flock` · `notify-send`/`kdialog`（后续阶段）。

TUI 可选增强（缺了会自动跳过，不影响使用）：
- **KDE/Wayland**：`qdbus6`（把浏览器窗口置顶用；非 KDE 或非 Wayland 时只打开链接）。
- `wl-clipboard`（`wl-copy`）：`Y` 复制链接。
