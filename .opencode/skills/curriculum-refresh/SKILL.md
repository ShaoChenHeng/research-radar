---
name: Curriculum Refresh
description: 刷新课程队列——按现有主题补充更高层次的新主题，输出 JSON 提案
---

# Curriculum Refresh

输入：`data/state/raw/refresh/input.json`
- 每个队列：`existing_topics`（已有哪些主题）、`existing_levels`（现有难度）、`title`。
- `add_per_queue`：每个队列要补几条。

## 输出
按 prompt 指定的**精确路径**，用 write 工具写一个 JSON 对象：
```json
{
  "knowledge": [
    {"topic":"具体主题","gist":"1–2 句是什么","why":"1 句为什么重要","refs":["https://…"],"level":2}
  ],
  "linux": [ … ]
}
```
- 键＝输入里的队列 id。
- **level**：1=基础 / 2=进阶 / 3=前沿；相对现有水平**递进**。

## 约束
- 每个队列补 `add_per_queue` 条，**不要与 `existing_topics` 重复**。
- **refs 必须是真实、可访问的链接**（官方文档 / man / Arch Wiki / 优质博客或技术文章 / arXiv / 维基）；拿不准就**不写该条**，宁缺毋滥。
- 主题要**具体、可学**（不要空泛词）。
- 只写 JSON 到该文件；**不要调用子代理**，不要做别的事。
