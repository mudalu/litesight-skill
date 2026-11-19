#!/usr/bin/env bash
#
# LiteSight CLI for AI agent skills
# 通过 HTTPS 调用 LiteSight 开放接口，使用个人访问令牌（PAT）鉴权。
# 依赖：bash、curl。
#

set -euo pipefail

LITESIGHT_API_URL="${LITESIGHT_API_URL:-https://www.litesight.cn/api/admin/skillhub}"
LITESIGHT_TOKEN_FILE="${HOME}/.config/litesight/token"

die() {
    echo "Error: $*" >&2
    exit 1
}

# 令牌只允许发往 LiteSight 官方域名（HTTPS）；本机调试地址除外
check_api_url() {
    local url=$LITESIGHT_API_URL scheme rest host
    case "$url" in
        https://*) scheme=https; rest=${url#https://} ;;
        http://*)  scheme=http;  rest=${url#http://} ;;
        *) die "LITESIGHT_API_URL is not allowed: $url" ;;
    esac

    host=${rest%%[/?#]*}
    # 拒绝 user@host 形式，避免伪装成官方域名
    case "$host" in
        *@*) die "LITESIGHT_API_URL is not allowed: $url" ;;
    esac
    host=${host%%:*}

    case "$scheme:$host" in
        https:litesight.cn|https:*.litesight.cn) ;;
        http:localhost|http:127.0.0.1) ;;
        *) die "LITESIGHT_API_URL must be an https://*.litesight.cn address (got: $url)" ;;
    esac
}

# 从环境变量或配置文件读取 Token
get_token() {
    if [[ -n "${LITESIGHT_TOKEN:-}" ]]; then
        printf '%s' "$LITESIGHT_TOKEN"
    elif [[ -f "$LITESIGHT_TOKEN_FILE" ]]; then
        tr -d '\r\n' < "$LITESIGHT_TOKEN_FILE"
    else
        echo "Error: LITESIGHT_TOKEN not set and $LITESIGHT_TOKEN_FILE not found" >&2
        echo "Please set LITESIGHT_TOKEN environment variable or save token to $LITESIGHT_TOKEN_FILE" >&2
        exit 1
    fi
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

# HTTP 请求包装
api_call() {
    local method=$1
    local path=$2
    local data=${3:-}

    check_api_url

    local token
    token=$(get_token)

    local curl_opts=(
        -X "$method"
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        --silent
        --show-error
        --fail-with-body
        --max-time 60
    )

    if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
    fi

    curl "${curl_opts[@]}" "${LITESIGHT_API_URL}${path}"
}

# 命令：配置 Token
cmd_configure() {
    echo "Enter your LiteSight Personal Access Token (input hidden):"
    local token
    read -rs token
    echo
    token=$(printf '%s' "$token" | tr -d '\r\n ')

    [[ -n "$token" ]] || die "empty token"

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

# 命令：报价（可直接传入整段分享文案，服务端会提取其中的链接）
cmd_quote() {
    local url=${1:-}

    if [[ -z "$url" ]]; then
        echo "Usage: litesight quote <url-or-share-text>" >&2
        exit 1
    fi

    api_call POST "/quotes" "{\"url\":\"$(json_escape "$url")\"}"
}

# 命令：提交任务
cmd_submit() {
    local quote_id=${1:-}
    local idempotency_key=${2:-"$(date +%s)-${RANDOM}${RANDOM}"}
    local force=${3:-false}

    if [[ -z "$quote_id" ]]; then
        echo "Usage: litesight submit <quote_id> [idempotency_key] [force]" >&2
        exit 1
    fi
    require_bool "$force" "force"

    api_call POST "/tasks" "{\"quoteId\":\"$(json_escape "$quote_id")\",\"idempotencyKey\":\"$(json_escape "$idempotency_key")\",\"force\":$force}"
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

# 命令：充值链接
cmd_recharge() {
    api_call POST "/recharge-link"
}

usage() {
    cat <<EOF
LiteSight CLI

Usage:
  litesight configure              Configure Personal Access Token
  litesight account                Get account status and credits
  litesight list [status] [page] [size]  List analysis tasks
  litesight quote <url-or-share-text>    Quote analysis for a video link
  litesight submit <quote_id> [idempotency_key] [force]  Submit analysis task
  litesight status <task_id>       Get task status
  litesight result <task_id> [--sections <s>] [--cursor <c>] [--limit <n>]  Get task result
  litesight media <task_id> [refresh]  Get media links
  litesight recharge               Create recharge link

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
