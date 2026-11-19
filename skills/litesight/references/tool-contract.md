# 接口契约

基础地址：`https://www.litesight.cn/api/admin/skillhub`。脚本只向 `litesight.cn` 域名发送请求。

| 命令 | HTTP | 路径 | 用途 | 所需权限 |
|---|---|---|---|---|
| `account` | GET | `/account` | 余额与时长权益 | `litesight.account.read` |
| `list` | GET | `/tasks` | 历史任务列表 | `litesight.analysis.read` |
| `quote` | POST | `/quotes` | 报价，不扣费 | `litesight.billing.quote` |
| `submit` | POST | `/tasks` | 确认后提交并扣积分 | `litesight.analysis.create` |
| `status` | GET | `/tasks/{task_id}/status` | 任务进度 | `litesight.analysis.read` |
| `result` | GET | `/tasks/{task_id}` | 按分区取结果 | `litesight.analysis.read` |
| `media` | GET | `/tasks/{task_id}/media` | 短期媒体链接 | `litesight.media.read` |
| `recharge` | POST | `/recharge-link` | 充值入口 | `litesight.recharge.link` |

## 鉴权

每个请求都带 `Authorization: Bearer <PAT>`。PAT 以 `ls_sk_` 开头，在 LiteSight「账号设置 → 三方集成令牌」里生成，集成类型选择 SkillHub，并勾选需要的权限。令牌可以设置有效期，也可以随时撤销。过期或撤销后需要重新生成。

令牌缺少某项权限时，对应命令会被拒绝，需要重新生成一个包含该权限的令牌。只查询历史结果时，只勾选「查看任务」即可。

## 响应格式

成功时：

```json
{
  "code": 0,
  "data": {
    "schemaVersion": "…",
    "data": { }
  }
}
```

业务字段都在 `.data.data` 下，使用下划线命名（外层的 `schemaVersion` 除外）。失败时 `code` 不为 0，`msg` 是原因说明，HTTP 状态码通常为 4xx 或 5xx。

`task_id` 是很长的数字，请原样当作字符串使用，不要做数值运算或用会丢精度的工具转换。

## account

```json
{
  "balance": 50,
  "gift_balance": 2,
  "total_charged": 100,
  "trial_available": true,
  "max_duration_seconds": 7200
}
```

- `balance`：当前可用积分
- `gift_balance`：其中赠送积分的余额
- `total_charged`：累计充值积分
- `trial_available`：是否仍在使用赠送积分（尚未充值且赠送积分有余额）
- `max_duration_seconds`：当前账户单个视频的时长上限

## list

查询参数：`status`（可选）、`page`（默认 1）、`size`（默认 10）。

```json
{
  "items": [
    {
      "task_id": "2101588428760346625",
      "title": "视频标题",
      "source": "douyin",
      "status": "COMPLETED",
      "media_duration": 399,
      "credits_cost": 1,
      "credits_refunded": false,
      "created_at": "…",
      "error_message": null
    }
  ],
  "page": 1,
  "size": 10,
  "total": 42,
  "has_more": true
}
```

任务状态取值：`PENDING`、`PROBING`、`WAITING_CONFIRM`、`PROCESSING_ASR`、`PROCESSING_LLM`、`COMPLETED`、`FAILED`、`CANCELLED`。

## quote

请求体：`{"url": "<链接或整段分享文案>"}`

```json
{
  "quote_id": "…",
  "title": "视频标题",
  "source": "douyin",
  "duration_seconds": 180,
  "required_credits": 1,
  "balance": 50,
  "can_submit": true,
  "existing_task_id": null,
  "reason": null,
  "expires_at": "…",
  "expires_in": 600
}
```

- `required_credits`：本次解析需要的积分
- `can_submit`：为 `false` 时不能提交，原因见 `reason`
- `existing_task_id`：该链接已有解析结果时的任务 ID，此时 `reason` 为 `TASK_ALREADY_PARSED`
- `expires_in`：报价剩余有效秒数。过期后提交会返回 `QUOTE_EXPIRED`，需要重新报价

## submit

请求体：

```json
{
  "quoteId": "…",
  "idempotencyKey": "…",
  "force": false
}
```

响应：

```json
{
  "task_id": 2101588428760346625,
  "idempotency_key": "…",
  "status": "PENDING"
}
```

`status` 的特殊取值：

- `ALREADY_PARSED`：该链接已解析过，没有扣费，`task_id` 指向已有任务。要重新解析需以 `force=true` 再次提交。
- `REPLAYED`：同一个幂等键的重复请求，返回的是第一次提交的结果，没有重复扣费。

## status

```json
{
  "task_id": "2101588428760346625",
  "status": "PROCESSING_LLM",
  "stage": "PROCESSING_LLM",
  "progress_hint": "…",
  "error_code": null,
  "error_message": null,
  "credits_refunded": null
}
```

`progress_hint` 是可以直接展示给用户的进度说明。任务失败时 `error_message` 说明原因，`credits_refunded` 表示积分是否已退回。

## result

查询参数：

- `sections`（可选，逗号分隔）：`metadata`、`summary`、`cleaned_text`、`timestamped_transcript`、`mind_map`、`knowledge_doc`。不传时返回 `metadata`、`summary`、`mind_map`。不支持 `all`，需要全部内容时逐个列出。
- `cursor`（可选）：带时间戳文稿的翻页游标
- `limit`（可选，默认 50）：带时间戳文稿每页的片段数

```json
{
  "task_id": "2101588428760346625",
  "status": "COMPLETED",
  "sections": ["metadata", "summary", "mind_map"],
  "metadata": { "task_id": "…", "title": "…", "source": "douyin", "media_duration": 399 },
  "summary": "…",
  "cleaned_text": null,
  "timestamped_transcript": null,
  "mind_map": {
    "format": "markmap-markdown",
    "markdown": "# 主题\n\n## 分支\n\n- 要点",
    "viewer_url": "…"
  },
  "knowledge_doc": null,
  "next_cursor": null,
  "has_more": false,
  "viewer_url": "…"
}
```

没有请求的分区为 `null`。`viewer_url` 是在 LiteSight 网站查看完整结果的链接。

## media

查询参数：`refresh`（默认 `false`，为 `true` 时重新获取链接）。

```json
{
  "task_id": "2101588428760346625",
  "media_url": "…",
  "audio_url": "…",
  "expires_at": "…",
  "refreshable": true,
  "unavailable_reason": null
}
```

链接不可用时 `unavailable_reason` 给出原因。

## recharge

```json
{
  "url": "…",
  "expires_in": 600,
  "display_text": "打开 LiteSight 充值页（10分钟内有效）"
}
```

把 `url` 原样交给用户，不要修改其中的参数。

## 错误码

出现在报价的 `reason`、状态的 `error_code` 或错误信息里：

| 错误码 | 含义 | 处理 |
|---|---|---|
| `AUTH_REQUIRED` / `AUTH_EXPIRED` | 令牌缺失、无效或过期 | 让用户重新生成并配置令牌 |
| `SCOPE_INSUFFICIENT` | 令牌缺少所需权限 | 重新生成包含该权限的令牌 |
| `INSUFFICIENT_CREDITS` | 积分不足 | 调用 `recharge` |
| `DURATION_LIMIT_EXCEEDED` | 超出单次时长上限 | 说明上限，可调用 `recharge` |
| `TASK_ALREADY_PARSED` | 链接已有解析结果 | 查看已有结果，或确认后 `force=true` |
| `QUOTE_EXPIRED` | 报价过期 | 重新 `quote` |
| `IDEMPOTENCY_CONFLICT` / `REQUEST_IN_PROGRESS` | 同一幂等键的请求冲突或仍在处理 | 不要重复提交，改查 `status` |
| `TASK_NOT_FOUND` / `TASK_ACCESS_DENIED` | 任务不存在或不属于当前用户 | 用 `list` 确认任务 ID |
| `TASK_PROCESSING` | 任务还没完成 | 稍后再取结果 |
| `TASK_FAILED` / `SUBMISSION_FAILED` | 解析或提交失败 | 如实告知，可重新报价再试 |
| `MEDIA_LINK_EXPIRED` | 媒体链接过期 | `media <task_id> true` |
| `PROVIDER_UNAVAILABLE` | 上游解析服务暂时不可用 | 稍后重试 |
| `RATE_LIMITED` | 请求过于频繁 | 放慢后重试 |
| `INVALID_REQUEST` | 参数有误 | 检查参数 |
