# 常见问题

## 令牌

**提示 `LITESIGHT_TOKEN not set`**

还没有配置令牌。让用户在 LiteSight「账号设置 → 三方集成令牌」生成令牌（集成类型选 SkillHub），然后设置环境变量 `LITESIGHT_TOKEN`，或运行 `bash scripts/litesight.sh configure`。

**返回 401，或提示令牌无效、过期**

令牌已过期、已撤销，或复制不完整。让用户撤销旧令牌并重新生成。令牌应以 `ls_sk_` 开头；为 Obsidian 插件生成的令牌不能在这里使用。

**返回 403，或提示授权范围不足**

令牌没有勾选对应的权限。各命令需要的权限见 `tool-contract.md`。权限不能事后追加，需要重新生成一个勾选了所需权限的令牌。

访问别人的任务也会被拒绝。用 `list` 确认任务 ID 属于当前账户。

## 报价与提交

**链接无法识别或报价失败**

确认链接能在浏览器里打开，且视频是公开的。私密、已删除或需要登录才能看的视频无法解析。可以把整段分享文案直接传给 `quote`。

**`INSUFFICIENT_CREDITS`**

余额不足。调用 `recharge` 给出充值入口。

**`DURATION_LIMIT_EXCEEDED`**

视频超出账户的单次时长上限（`account` 返回的 `max_duration_seconds`）。充值后上限会提高。

**`QUOTE_EXPIRED`**

报价过期，重新 `quote` 即可。

**提交超时，不确定是否成功**

用同一个幂等键再提交一次，不会重复扣费；或用 `list` 查看最新任务。不要换一个新的幂等键重试。

## 任务处理

**任务长时间处于处理中**

长视频需要更久。每隔几秒调用一次 `status`，把 `progress_hint` 转告用户。不要重复提交。

**任务 `FAILED`**

把 `error_message` 如实告诉用户，并说明 `credits_refunded` 是否为 `true`。常见原因是视频已失效或上游服务暂时不可用，可以稍后重新报价再试。

**媒体链接打不开**

媒体链接是短期有效的。用 `media <task_id> true` 重新获取。

## 环境

**`curl: option --fail-with-body: is unknown`**

curl 版本过旧，需要 7.76 或更高版本。

**Windows 下脚本报错 `$'\r': command not found`**

脚本被转换成了 CRLF 换行。在 Git Bash 里执行：

```bash
sed -i 's/\r$//' scripts/litesight.sh
```

**提示 `LITESIGHT_API_URL must be an https://*.litesight.cn address`**

为了保护令牌，脚本只向 `litesight.cn` 域名的 HTTPS 地址发请求。正常使用不需要设置这个变量，取消设置即可。

**连接超时或无法解析域名**

检查网络能否访问 `https://www.litesight.cn`。在受限的沙箱环境里，需要把该域名加入允许访问的列表。

## 联系支持

- 官网：<https://www.litesight.cn>
- 网站内「意见反馈」
- 邮件：lite_sight@163.com

反馈时请提供错误信息原文和任务 ID。不要提供完整令牌。
