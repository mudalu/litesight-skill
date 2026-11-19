# 轻析 LiteSight Agent Skill

让 AI 助手把抖音、B站、快手、小红书、微博等视频链接解析成文字稿、摘要、思维导图和知识笔记。

本仓库是 [LiteSight（轻析）](https://www.litesight.cn) 的官方 Agent Skill，采用通用的 `SKILL.md` 格式，可用于 Claude Code、Codex、Cursor、OpenClaw、WorkBuddy 等支持 Agent Skills 的工具。

## 能做什么

- 提取视频的完整文案和带时间戳的逐句文稿
- 生成内容摘要、思维导图和结构化知识笔记
- 查询历史解析任务和结果
- 提交前先报价，用户确认后才扣积分

对话示例：

- “帮我总结这个视频：https://v.douyin.com/xxxxxxx”
- “把这个 B 站视频的文案提取出来”
- “列出我最近解析过的视频”

## 安装

```bash
npx skills add mudalu/litesight-skill
```

也可以手动把 `skills/litesight` 目录复制到所用工具的技能目录，例如 `~/.claude/skills/litesight`。

环境要求：`bash` 和 `curl`（7.76 及以上）。Windows 用户可使用 Git Bash 或 WSL。

## 配置令牌

1. 在 [www.litesight.cn](https://www.litesight.cn) 注册并登录。
2. 进入「账号设置 → 三方集成令牌 → 生成令牌」，集成类型选择 **SkillHub**。这一类型的令牌适用于所有 AI 技能平台。
3. 勾选需要的权限并设置有效期。只查询历史结果时，只勾选「查看任务」即可。
4. 复制只显示一次的 `ls_sk_` 令牌，用下面任一方式配置：

```bash
# 方式一：环境变量
export LITESIGHT_TOKEN="ls_sk_your_token_here"

# 方式二：保存到本地文件（输入时不回显）
bash skills/litesight/scripts/litesight.sh configure
```

验证：

```bash
bash skills/litesight/scripts/litesight.sh account
```

能返回账户余额即配置成功。

## 计费

解析按 LiteSight 积分计费，积分记在你自己的 LiteSight 账户上。每次解析前技能都会先报价，展示所需积分和当前余额，你确认后才会扣费。充值在 LiteSight 官网完成。

## 安全说明

- 令牌只保存在本机的环境变量或 `~/.config/litesight/token`（权限 600）。
- 脚本只向 `https://www.litesight.cn` 发送请求；自定义地址必须是 HTTPS。
- 令牌可以在 LiteSight 账号设置里随时撤销。

## 目录结构

```
skills/litesight/
├── SKILL.md              # 技能说明
├── LICENSE               # MIT
├── scripts/litesight.sh  # 命令行客户端
└── references/           # 接口契约、结果分区、计费、常见问题
```

## 支持

- 官网：<https://www.litesight.cn>
- 邮件：lite_sight@163.com

## 许可证

本技能包（`SKILL.md`、客户端脚本和文档）以 [MIT](LICENSE) 协议开源。LiteSight 解析服务本身是在线服务，按账户积分计费，不在本协议范围内。

© 2026 LiteSight Team
