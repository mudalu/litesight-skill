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

确认链接能在浏览器里打开，且视频是公开的。私密、已删除或需要登录才能看的视频无法解析。整段分享文案可以写入文件后用 `quote --file <路径>` 提交，服务端只提取其中的链接。不要把文案拼进命令行。

**`INSUFFICIENT_CREDITS`**

余额不足。询问用户是否需要充值入口，同意后调用 `recharge`。

**`DURATION_LIMIT_EXCEEDED`**

视频超出账户的单次时长上限（`account` 返回的 `max_duration_seconds`）。充值后上限会提高。

**`QUOTE_EXPIRED`**

报价过期，重新 `quote` 即可。

**提交超时，不确定是否成功**

先用 `list` 查看最新任务是否已经创建。已创建就直接查 `status`，不要再次提交。

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

**提示 `requires explicit user confirmation`**

`submit` 和 `recharge` 需要用户确认。先向用户说明本次操作和费用，按 `SKILL.md`“需要用户确认的操作”一节取得确认后再执行。

**提示 `no local record of this quote` 或 `this quote has expired`**

`submit` 只接受本机 10 分钟内报过价的 `quote_id`。重新执行 `quote`，把新的费用告诉用户并再次确认。

**提示 `only a plain URL may be passed as an argument`**

输入里有空格、引号或其他特殊字符。把原文写入文件，改用 `quote --file <路径>`。

**连接超时或无法解析域名**

本技能只需要访问 `https://www.litesight.cn`，这一点已在 `SKILL.md` 的元数据里声明，不需要其他域名。

连接失败时，把情况告诉用户：当前环境无法访问 `https://www.litesight.cn`，需要用户自己检查网络，或由用户在所用工具的设置里允许这个地址。

不要自行修改沙箱、防火墙、代理或网络白名单配置；不要使用 `*.litesight.cn` 之类的通配放行；不要关闭证书校验（例如 `curl -k`）；不要引入本地代理或换用其他地址来绕过限制。这些都应由用户决定并操作。

## 联系支持

- 官网：<https://www.litesight.cn>
- 网站内「意见反馈」
- 邮件：lite_sight@163.com

反馈时请提供错误信息原文和任务 ID。不要提供完整令牌。
