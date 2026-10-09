# 阶段 0 · 环境自检报告（ENV-CHECK.md）

- 主机：Arch + KDE（opencode v2.0.20）
- 日期：2026-10-06
- 结论：**可行 ✅**。有 4 个需要适配的点（见末尾"对设计的调整"）。

---

## 1. 本地依赖

| 依赖 | 状态 | 版本/备注 |
|---|---|---|
| node | ✅ | v20.19.3（MCP 用） |
| npx | ✅ | 10.8.2 |
| git | ✅ | 2.55.0 |
| flock | ✅ | util-linux 2.42.4 |
| curl / wget | ✅ | 8.22.0 / 1.25.0 |
| date | ✅ | coreutils 9.12 |
| python3 | ✅ | 3.14.7（可替代 jq 解析 JSON） |
| sqlite3 | ✅ | 3.53.4（备用） |
| notify-send | ✅ | libnotify 0.8.8 |
| kdialog | ✅ | 26.08.1（通知回退） |
| **jq** | ❌ **缺** | 用 `python3` 解析 JSON，或 `sudo pacman -S jq` |

## 2. 模型（`opencode run` 无头）

| 模型 | 结果 |
|---|---|
| `opencode/nemotron-3.5-lightning-free`（免费） | ✅ 返回 `OK`，exit 0 |
| `deepseek/deepseek-flash`（兜底，当前会话同款） | ✅ 返回 `OK`，exit 0 |

- 关键参数：**`--auto`**（无头自动批准未显式 deny 的权限）——自动化必须带它。
- `--model provider/model`、`--agent <id>` 均可用。

## 3. 桌面通知（systemd user service 发信）

| 测试 | 结果 |
|---|---|
| `systemd --user` default.target | ✅ active |
| `systemd-run --user … notify-send …` | ✅ success（exit 0，43ms） |

→ 阶段 5 的 KDE 通知方案**可用**，无需回退 kdialog。

## 4. 网络可达性

| 目标 | 直连 | 备注 |
|---|---|---|
| `arxiv.org` / `export.arxiv.org` | ✅ 200 | **主源**，API 实抓成功 |
| `hacker-news.firebaseio.com`（HN API） | ✅ 200（3/3，~1–2s） | 偶发超时，需重试 |
| `news.ycombinator.com`（HN 网页） | ❌ 000 | **不用网页**，用 API |
| `hf-mirror.com`（含 `/api/daily_papers`） | ✅ 200 | **HF 替代源** |
| `huggingface.co` | ❌ 连接被重置 | 被墙；改用 hf-mirror 或代理 |
| `api.semanticscholar.org` | ⚠️ **429** | 共享 IP 限流；需退避/加间隔，或可选免费 key |
| `127.0.0.1:<端口>`（本地代理） | ✅ | 走它 HF=200、HN=200 |

> 本机可选一个本地代理（混合端口，示例 `127.0.0.1:<端口>`），但**不作为依赖**。

---

## 5. 对设计的调整（据此更新 ARCHITECTURE §8）

1. **HF 源改用 `hf-mirror.com`**（直连可用），不再依赖 `huggingface.co`。
2. **HN 只用 Firebase API**（`hacker-news.firebaseio.com`），不用网页；并加**重试**。
3. **Semantic Scholar 作为"加分项"而非必需**：它常返回 429 → 加**限速 + 退避**；无 key 也能用，但只偶尔取引用数。
4. **代理作为可选兜底（非必需）**：需要访问被墙站点时，可在 service 里设 `HTTPS_PROXY=http://127.0.0.1:<端口>`；但**不能作为依赖**（代理不一定在线），所以主力仍走"直连可用源"。
5. **jq 缺失** → 全部 JSON 解析用 `python3`（或阶段 1 顺手装 jq）。
6. **自动化命令固定带 `--auto`**。

## 6. 主源清单（阶段 1 采用）

| 板块 | 源 | 地址 |
|---|---|---|
| ① | arXiv API | `https://export.arxiv.org/api/query`（`cat:cs.CL,cs.LG,cs.IR`，最近 2–3 天） |
| ① | HF Daily Papers | `https://hf-mirror.com/api/daily_papers` |
| ① | HN（工程动态） | `https://hacker-news.firebaseio.com/v0/topstories.json` |
| ①（加分） | Semantic Scholar | `https://api.semanticscholar.org/graph/v1/...`（限速/退避） |

---

## 7. 阶段 0 判定

- ✅ 依赖、模型、通知、主源**均可用** → **可以进入阶段 1**。
- 唯一小缺口：**jq**（非阻塞，用 python3 顶上）。
- 网络适配点已在 §5 记录，阶段 1 直接按 §6 实现。

---

## 8. 阶段 1 实测补充（2026-10-06）

- **arXiv API 会被限流**：短时间内多次请求 → `429` / 超时（首次测 OK，被 agent 狂刷后失败）。
- **解决办法（已采用）**：
  1. **arXiv RSS** `https://rss.arxiv.org/rss/<cat>` —— 直连**稳定**（每分类 **427 条/天**），作为**主源**；
  2. arXiv API 仅作**备用**，需要时走代理 `127.0.0.1:<端口>`。
- **架构调整**：抓取改由 **runner 用 curl 预抓**到 `state/raw/<date>/`，**agent 只读本地文件成文**（不联网、不狂刷、更快更稳更省 token）。
- 实测：`hf-mirror.com/api/daily_papers` 直连稳定（**50 篇**）；HN API 直连稳定（**20 条详情**）。
- 首次成功产出日报：`digest/2026/10/2026-10-06.md`。
- **HF Daily 镜像可能滞后**：`hf-mirror.com/api/daily_papers` 当前最新批次为 2026-10-01，在 3 天窗口下会被过滤 → 主力仍是 **arXiv RSS**。
- **HN 常 0 命中**：Firebase 里多为链接帖、标题不含研究关键词；若要 HN 参与，需在 `config.toml` 加工程类关键词或单列。
- **最终形态**：runner `curl` 预抓 → `bin/radar-extract` 按关键词/时间窗预筛成 `candidates.jsonl`（**每源配额**：arxiv 80 / hf 25 / hn 20）→ agent 只读该文件成文。单次约 **40–90s**。
- **模型（2026-10 实测）**：免费模型里**只有 `space-bunny-free` 能在 CLI 用**，其余报 `free tier can only be used from within OpenCode`；已在 `config.toml` 只保留它 + 兜底 `deepseek/deepseek-flash`。
