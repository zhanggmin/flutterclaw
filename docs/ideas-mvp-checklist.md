# Ideas MVP 验收 Checklist

> 范围：覆盖 PRD 第 15 节（MVP 完成标准）的落地检查项。

## 1) 列表筛选与检索

- [x] 支持状态筛选：`全部 / inbox / incubating / developing / archived`。
- [x] 支持标签筛选（按单标签精确匹配）。
- [x] 支持关键词检索（标题/描述/标签）。

## 2) 默认排序与可扩展排序

- [x] 默认排序策略为 `updatedAt` 倒序。
- [x] 预留 `lastBrainstormedAt` 排序能力。
- [x] 预留 `priority` 排序能力。

## 3) 埋点与参数规范（PRD 13.1）

- [x] 补全 Ideas 域核心事件：
  - `idea_created`
  - `idea_updated`
  - `idea_archived`
  - `idea_filter_applied`
- [x] 统一参数格式：`ideaId / sourceType / status`。

## 4) 数据完整性与最小测试集（静态）

- [x] 模型序列化/反序列化可逆。
- [x] repository 完成 CRUD。
- [x] repository 支持搜索与筛选。
- [x] 保存后 `sourceType` 字段写入并可读取。

## 5) V1.1 待办（下一阶段）

- [ ] 附件能力：语音 / 图片 / 链接附件（结构化挂载到 idea）。
- [ ] 今日下一步聚合：从 incubating/developing 自动汇总 “Today Next Steps”。
- [ ] 孵化提醒：按 `lastBrainstormedAt` 与优先级生成提醒策略。

## 6) 验收建议

- [ ] 对接 UI 层后补一轮端到端验收（筛选、排序、编辑、归档、恢复）。
- [ ] 对接真实埋点平台后校验事件名与参数上报一致性。
- [ ] 增加跨版本迁移测试（未来字段扩展时确保兼容历史数据）。
