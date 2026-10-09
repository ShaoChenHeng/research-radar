---
name: Feedback Ingest
description: 把自然语言反馈转成 radar fb 命令并执行（条目/主题/屏蔽）
---

# Feedback Ingest

把用户的自然语言反馈，转成对应命令并执行（项目根目录下）：

| 用户表达 | 执行 |
|---|---|
| 喜欢 / 点赞 a1 | `./bin/radar fb item like a1` |
| 不喜欢 a2 | `./bin/radar fb item dislike a2` |
| 想要更多 "agentic rag" | `./bin/radar fb topic more "agentic rag"` |
| 想要更少 "对齐" | `./bin/radar fb topic less "对齐"` |
| 屏蔽 "crypto" | `./bin/radar fb mute "crypto"` |
| 解析日报里的标记 | `./bin/radar fb parse` |
| 某条课程已学会 | 在日报该条写 `learned`，再 `./bin/radar fb parse`（该课程条目归档） |
| 某条课程没看懂 | 在日报该条写 `confused`，再 `./bin/radar fb parse`（尽快再出现） |
| 想**下载**某条 b1 | 在日报该条写 `save`，再 `./bin/radar pdf --saved`（**save 不进反馈**） |

- 条目 ID 形如 `a1`/`b1`/`c1`（见当天日报 `data/digest/<Y>/<M>/<date>/<date>.md`）。
- 日报每条末尾的 `- **标记**：` 可写**多个**信号（空格/逗号分隔），如 `like save`：
  - `like` = **多推荐**（加权）；`dislike` = **少推荐**（减权）；
  - `learned` = **已学会**（课程条目归档）；`confused`（/`没懂`/`again`）= **没看懂 → 尽快再来**；
  - `save` = 只是**下载标记**（`radar pdf --saved`，不进反馈）。
- 一次反馈可能对应多条命令，逐条执行。
- 执行后**简要复述**记录了什么。
- 只运行 `bin/radar fb` 相关命令，不要做别的。
