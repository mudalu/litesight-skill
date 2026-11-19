# 积分、报价与充值

LiteSight 按积分计费。具体需要多少积分、账户能解析多长的视频，都以接口返回为准，不要自行估算或向用户承诺价格。

## 查看账户

```bash
bash scripts/litesight.sh account
```

- `balance`：当前可用积分
- `gift_balance`：其中赠送积分的余额
- `max_duration_seconds`：当前账户单个视频的时长上限
- `trial_available`：是否仍在使用赠送积分（尚未充值且赠送积分有余额）

## 报价与确认

1. 调用 `quote`，不扣费。
2. 向用户展示：标题、来源、时长（`duration_seconds`）、所需积分（`required_credits`）、当前余额（`balance`）。
3. 明确询问是否提交。用户同意后调用 `submit`，此时扣积分。

报价有有效期（`expires_in` 秒）。过期后重新报价即可。

## 不能提交的情况

`can_submit` 为 `false` 时看 `reason`：

| reason | 说明 | 怎么做 |
|---|---|---|
| `INSUFFICIENT_CREDITS` | 余额少于所需积分 | 告知差额，调用 `recharge` |
| `DURATION_LIMIT_EXCEEDED` | 视频超出账户的单次时长上限 | 说明上限，充值后可解析更长的视频 |
| `TASK_ALREADY_PARSED` | 该链接已有结果 | 让用户选择查看已有结果（`existing_task_id`）或重新解析 |

重新解析会再次扣积分，必须先得到用户确认，再用同一个 `quote_id` 以 `force=true` 提交。

## 失败与退款

任务失败时，`status` 返回的 `credits_refunded` 表示积分是否已退回。如实转告用户即可。如果用户认为扣费有误，请用户联系 LiteSight 客服处理，不要代为承诺退款。

## 充值

```bash
bash scripts/litesight.sh recharge
```

返回 `url`、`expires_in` 和可直接展示的 `display_text`。向用户说明：

1. 链接 10 分钟内有效，需要在浏览器里打开。
2. 在 LiteSight 官方页面完成支付。
3. 支付完成后回到对话继续。

之后调用 `account` 确认余额。到账可能有一两分钟延迟。

不要修改充值链接里的参数，也不要声称已经在当前对话里完成了支付。

## 积分明细

本技能不提供积分流水查询。用户可以登录 LiteSight 网站查看完整明细。
