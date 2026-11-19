#!/usr/bin/env bash
#
# LiteSight CLI for AI agent skills
# 通过 HTTPS 调用 LiteSight 开放接口，使用个人访问令牌（PAT）鉴权。
# 依赖：bash、curl。
#
# 安全约定：
#   - 接口地址固定为 LiteSight 官方域名，不能通过环境变量或参数修改。
#   - 令牌通过标准输入交给 curl，不出现在命令行参数里。
#   - 会扣积分或生成支付入口的命令（submit、recharge）必须带 --yes，
#     表示用户已经明确确认；不带时脚本不会发出任何请求。
#

set -euo pipefail

readonly LITESIGHT_API_BASE="https://www.litesight.cn/api/admin/skillhub"
readonly LITESIGHT_TOKEN_FILE="${HOME}/.config/litesight/token"

die() {
    echo "Error: $*" >&2
    exit 1
}

# 从环境变量或配置文件读取 Token，并校验字符集
get_token() {
    local token
    if [[ -n "${LITESIGHT_TOKEN:-}" ]]; then
        token=$LITESIGHT_TOKEN
    elif [[ -f "$LITESIGHT_TOKEN_FILE" ]]; then
        token=$(tr -d '\r\n' < "$LITESIGHT_TOKEN_FILE")
    else
        echo "Error: LITESIGHT_TOKEN not set and $LITESIGHT_TOKEN_FILE not found" >&2
        echo "Please set LITESIGHT_TOKEN environment variable or save token to $LITESIGHT_TOKEN_FILE" >&2
        exit 1
    fi
    [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || die "token contains invalid characters"
    printf '%s' "$token"
}

# 把任意文本转成 JSON 字符串内容（不含外层引号）
json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    # 去掉其余控制字符
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
    printf '%s' "$s"
}

require_task_id() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] || die "task_id must be a number. $2"
}

require_bool() {
    [[ "$1" == "true" || "$1" == "false" ]] || die "$2 must be true or false"
}

# 高代价操作的强制确认：没有 --yes 就中止，不发请求
require_confirmation() {
    local confirmed=$1 what=$2
    if [[ "$confirmed" != "true" ]]; then
        echo "Error: $what requires explicit user confirmation." >&2
        echo "Ask the user first. Only after the user clearly agrees, run the command again with --yes." >&2
        exit 2
    fi
}

# HTTP 请求包装
api_call() {
    local method=$1
    local path=$2
    local data=${3:-}

    local token
    token=$(get_token)

    local curl_opts=(
        --config -
        -X "$method"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        --proto "=https"
        --silent
        --show-error
        --fail-with-body
        --max-time 60
    )

    if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
    fi

    # 令牌经标准输入传入（printf 是 shell 内建命令），不会出现在进程参数里
    printf 'header = "Authorization: Bearer %s"\n' "$token" \
        | curl "${curl_opts[@]}" "${LITESIGHT_API_BASE}${path}"
}

# 命令：配置 Token
cmd_configure() {
    echo "Enter your LiteSight Personal Access Token (input hidden):"
    local token
    read -rs token
    echo
    token=$(printf '%s' "$token" | tr -d '\r\n ')

    [[ -n "$token" ]] || die "empty token"
    [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || die "token contains invalid characters"

    if [[ ! "$token" =~ ^ls_sk_ ]]; then
        echo "Warning: Token does not start with 'ls_sk_'. Please verify it is a valid LiteSight PAT." >&2
    fi

    mkdir -p "$(dirname "$LITESIGHT_TOKEN_FILE")"
    (umask 077 && printf '%s\n' "$token" > "$LITESIGHT_TOKEN_FILE")
    chmod 600 "$LITESIGHT_TOKEN_FILE"

    echo "Token saved to $LITESIGHT_TOKEN_FILE"
}

# 命令：账户状态
cmd_account() {
    api_call GET "/account"
}

# 命令：任务列表
cmd_list() {
    local status=${1:-}
    local page=${2:-1}
    local size=${3:-10}

    [[ "$page" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ ]] || die "page and size must be numbers"

    local query="?page=$page&size=$size"
    if [[ -n "$status" ]]; then
        [[ "$status" =~ ^[A-Za-z_]+$ ]] || die "invalid status: $status"
        query="${query}&status=$status"
    fi

    api_call GET "/tasks$query"
}

# 命令：报价（不扣费；可传入整段分享文案，服务端只提取其中的链接）
cmd_quote() {
    local url=${1:-}

    if [[ -z "$url" ]]; then
        echo "Usage: litesight quote <url-or-share-text>" >&2
        exit 1
    fi

    api_call POST "/quotes" "{\"url\":\"$(json_escape "$url")\"}"
}

# 命令：提交任务（扣积分，必须带 --yes）
cmd_submit() {
    local usage="Usage: litesight submit <quote_id> --yes [--idempotency-key <key>] [--force]"
    local quote_id="" idempotency_key="" force=false confirmed=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes) confirmed=true; shift ;;
            --force) force=true; shift ;;
            --idempotency-key)
                [[ $# -ge 2 ]] || die "option $1 needs a value"
                idempotency_key=$2; shift 2 ;;
            --*) die "Unknown option: $1. $usage" ;;
            *)
                [[ -z "$quote_id" ]] || die "unexpected argument: $1. $usage"
                quote_id=$1; shift ;;
        esac
    done

    [[ -n "$quote_id" ]] || die "$usage"
    [[ "$quote_id" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "invalid quote_id"
    if [[ -n "$idempotency_key" ]]; then
        [[ "$idempotency_key" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "invalid idempotency key"
    fi

    require_confirmation "$confirmed" "submit (it spends the user's credits)"

    [[ -n "$idempotency_key" ]] || idempotency_key="$(date +%s)-${RANDOM}${RANDOM}"

    api_call POST "/tasks" "{\"quoteId\":\"$quote_id\",\"idempotencyKey\":\"$idempotency_key\",\"force\":$force}"
}

# 命令：任务状态
cmd_status() {
    require_task_id "${1:-}" "Usage: litesight status <task_id>"
    api_call GET "/tasks/$1/status"
}

# 命令：任务结果
cmd_result() {
    require_task_id "${1:-}" "Usage: litesight result <task_id> [--sections <s>] [--cursor <c>] [--limit <n>]"
    local task_id=$1
    shift

    local query=""
    while [[ $# -gt 0 ]]; do
        [[ $# -ge 2 ]] || die "option $1 needs a value"
        case $1 in
            --sections)
                [[ "$2" =~ ^[a-z_,]+$ ]] || die "invalid sections: $2"
                query="${query}&sections=$2"
                ;;
            --cursor)
                [[ "$2" =~ ^[A-Za-z0-9_=.:-]+$ ]] || die "invalid cursor: $2"
                query="${query}&cursor=$2"
                ;;
            --limit)
                [[ "$2" =~ ^[0-9]+$ ]] || die "limit must be a number"
                query="${query}&limit=$2"
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift 2
    done

    api_call GET "/tasks/$task_id${query:+?${query:1}}"
}

# 命令：媒体链接
cmd_media() {
    require_task_id "${1:-}" "Usage: litesight media <task_id> [refresh]"
    local refresh=${2:-false}
    require_bool "$refresh" "refresh"

    api_call GET "/tasks/$1/media?refresh=$refresh"
}

# 命令：充值链接（生成支付入口，必须带 --yes）
cmd_recharge() {
    local confirmed=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes) confirmed=true; shift ;;
            *) die "Unknown option: $1. Usage: litesight recharge --yes" ;;
        esac
    done

    require_confirmation "$confirmed" "recharge (it creates a payment link)"

    api_call POST "/recharge-link"
}

usage() {
    cat <<EOF
LiteSight CLI

Usage:
  litesight configure              Configure Personal Access Token
  litesight account                Get account status and credits
  litesight list [status] [page] [size]  List analysis tasks
  litesight quote <url-or-share-text>    Quote analysis for a video link (free)
  litesight submit <quote_id> --yes [--idempotency-key <key>] [--force]
                                   Submit analysis task (spends credits)
  litesight status <task_id>       Get task status
  litesight result <task_id> [--sections <s>] [--cursor <c>] [--limit <n>]  Get task result
  litesight media <task_id> [refresh]  Get media links
  litesight recharge --yes         Create recharge link

  --yes means the user has explicitly confirmed. Without it, submit and
  recharge stop without sending any request.

Environment:
  LITESIGHT_TOKEN        Personal Access Token (or use configure command)

EOF
}

# 主命令路由
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    local cmd=$1
    shift

    case $cmd in
        configure) cmd_configure "$@" ;;
        account)   cmd_account "$@" ;;
        list)      cmd_list "$@" ;;
        quote)     cmd_quote "$@" ;;
        submit)    cmd_submit "$@" ;;
        status)    cmd_status "$@" ;;
        result)    cmd_result "$@" ;;
        media)     cmd_media "$@" ;;
        recharge)  cmd_recharge "$@" ;;
        -h|--help|help) usage ;;
        *)
            echo "Unknown command: $cmd" >&2
            echo "Run 'litesight' without arguments to see usage." >&2
            exit 1
            ;;
    esac
}

main "$@"
