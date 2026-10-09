---
name: Daily Digest
description: 生成 Research Radar 每日日报（按 prompt 里的栏目），读本地候选与队列成文
---

# Daily Digest

**栏目、标题、ID 前缀、条数、分点标签全部以 prompt 里的栏目为准，不要写死。**
数据已由 runner 预抓/预选到本地；你**只读本地文件**（不要联网、不要用 shell）。

## 输入
- **feed 候选**：`data/state/raw/<date>/candidates_unseen.jsonl`
  每行一条 JSON，字段：`source`(arxiv/hf_daily/hackernews/rss)、`title`、`link`、`id`、`date`、`abstract`(≤1200字)。
  **已按「相关度 + 新近度」排好序**（越靠前越相关），并已剔除历史重复。
- **queue 已选**：`data/state/raw/<date>/selected.json`
  `{"<栏目id>": [条目…]}`；条目字段：`topic`、`gist`、`why`、`refs`(数组)、`level`。

## 步骤
1. 按 prompt 的**栏目顺序**逐个生成，不要增删栏目。
2. **feed 栏目**：读候选文件 → 按该栏目 **`window_days`（时间窗）**、`keywords`/`categories` 过滤 → 去重 → **从前往后取** `min`–`max` 条（已排好序，不必反复 grep）。
3. **queue 栏目**：用 `selected.json` 里对应 id 的数组，**顺序与数量不变**。
4. 用 **write** 一次性写到 prompt 指定路径（Markdown 正文，不包代码块）。

## 排版
- 每个栏目一个 `## 标题`（用 prompt 给的，**不带序号**）。
- 每条一个 `### [前缀N] 标题`（前缀用 prompt 给的，如 `a` → `[a1]`）。
- 条目下**三个分点**，标签用 prompt 给的 `fields`：
  - feed：第1点＝基于 `abstract` 的方法/动机；第2点＝主要结果（尽量带数字）；第3点＝`[文字](link)`。
  - queue：第1点＝`gist`；第2点＝`why`；第3点＝`[文字](refs)`。
- **每条最后再加一行 `- **标记**：`**（留空，供用户填 `like`/`dislike`/`save`）。
- **链接分点必须是 Markdown 链接**（不要裸 URL）；篇与篇之间**空一行**。

## 效率要求（重要，直接决定快慢）
- **不要调用子代理**（subagent）。
- **每个文件最多读一次**，不要反复 grep/重读。
- 做完必要的 1–2 次读取后**直接 write**，不要来回试探。

## 约束
- feed 栏目**每条都必须有链接分点**，否则去重失效、次日会重复推荐。
- **宁缺毋滥**：相关条目不足时该栏可少给（低于 min），不要为凑数硬塞；兴趣类内容与主业无关时可省略。
- queue 栏目直接用给定 `gist`/`why`（可轻微润色），**不要编造、不要增删条目**。
- feed 基于 `abstract`，信息不足以支撑结论的条目不写。
