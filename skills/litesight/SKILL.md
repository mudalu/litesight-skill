---
name: litesight
description: 用 LiteSight（轻析）把抖音、B站、快手、小红书、微博等视频链接解析成文字稿、摘要、思维导图和知识笔记。当用户发来视频链接或分享文案，想要提取文案、总结内容、生成脑图或笔记，或想查询之前的解析任务时使用。需要用户先配置 LiteSight 个人访问令牌。
version: 0.2.4
license: MIT
homepage: https://www.litesight.cn
metadata:
  author: LiteSight Team
  displayName: 轻析 LiteSight 视频内容解析
  requires: bash, curl
---

# 轻析 LiteSight 视频内容解析

通过 `scripts/litesight.sh` 调用 LiteSight 开放接口。解析任务和积分都记在用户自己的 LiteSight 账户上。

## 前提条件

用户必须先配置个人访问令牌（PAT）：

1. 登录 <https://www.litesight.cn>，进入「账号设置 → 三方集成令牌 → 生成令牌」。
2. 集成类型选择 **SkillHub**。这一类型的令牌（以 `ls_sk_` 开头）适用于所有 AI 技能平台。
3. 把令牌设置为环境变量 `LITESIGHT_TOKEN`，或运行 `bash scripts/litesight.sh configure` 保存到 `~/.config/litesight/token`。

没有令牌时命令会报错。此时把上面的步骤告诉用户，不要向用户索要令牌并写进对话。

## 命令

```bash
bash scripts/litesight.sh account                      # 余额与时长权益
bash scripts/litesight.sh list [status] [page] [size]  # 历史任务
bash scripts/litesight.sh quote "<链接或分享文案>"       # 报价，不扣费
bash scripts/litesight.sh submit <quote_id> [幂等键] [force]  # 确认后提交，扣积分
bash scripts/litesight.sh status <task_id>             # 任务进度
bash scripts/litesight.sh result <task_id> [--sections a,b] [--cursor c] [--limit n]
bash scripts/litesight.sh media <task_id> [refresh]    # 短期媒体链接
bash scripts/litesight.sh recharge                     # 充值入口
```

所有响应都是 JSON，业务数据在 `.data.data` 下，字段为下划线命名。字段说明见 `references/tool-contract.md`。

## 使用规则

1. **先报价、后确认、再提交**：用户给出新链接时先调用 `quote`，向用户展示标题、时长、所需积分（`required_credits`）和当前余额（`balance`）。只有用户明确同意后才调用 `submit`。
2. **已解析过的链接**：报价里带 `existing_task_id` 或 `reason` 为 `TASK_ALREADY_PARSED` 时，告诉用户该链接已有结果，让用户选择查看已有结果还是重新解析。重新解析要再次扣积分，需用户确认后以 `force=true` 提交。
3. **不能提交的情况**：`can_submit` 为 `false` 时按 `reason` 说明原因。`INSUFFICIENT_CREDITS` 是余额不足，`DURATION_LIMIT_EXCEEDED` 是超出当前账户的单次时长上限。两种情况都可以调用 `recharge` 给出充值入口。
4. **幂等键**：每次新的提交使用新的幂等键；不传时脚本自动生成。同一次提交因超时重试时要复用原来的幂等键，避免重复扣费。
5. **异步轮询**：提交后只调用 `status` 查询，不要重复提交。`PENDING`、`PROBING`、`PROCESSING_ASR`、`PROCESSING_LLM` 表示仍在处理，间隔几秒再查；`COMPLETED` 后再取结果。
6. **按需取结果**：`result` 不传 `--sections` 时只返回 `metadata`、`summary` 和 `mind_map`。用户要完整文案、知识笔记或带时间戳的文稿时，再请求 `cleaned_text`、`knowledge_doc` 或 `timestamped_transcript`。详见 `references/result-sections.md`。
7. **脑图展示**：`mind_map.markdown` 可直接在对话里展示为层级大纲；完整的交互式脑图和播放器请给出返回的 `viewer_url`。
8. **媒体链接**：只有用户明确要求下载或播放时才调用 `media`。链接是短期有效的，不要长期保存或公开转发。
9. **充值**：`recharge` 返回的链接 10 分钟内有效，用户需在浏览器里完成支付。不要声称已经在当前对话里完成了支付。
10. **失败处理**：任务 `FAILED` 时如实说明 `error_message`，并根据 `credits_refunded` 告知积分是否已退回。不要把处理中的任务说成已完成。
11. **安全**：不要输出令牌、签名链接里的密钥参数或任何内部标识。

## 支持的来源

抖音、B站、快手、小红书、微博等平台的分享链接，以及音视频直链。用户粘贴整段分享文案时可以直接把原文传给 `quote`，服务端会提取其中的链接。

## 参考文档

- `references/tool-contract.md`：接口、字段和错误码
- `references/result-sections.md`：结果分区与分页
- `references/billing.md`：积分、报价和充值
- `references/troubleshooting.md`：常见问题
