#!/usr/bin/env bash
#
# LiteSight CLI for AI agent skills
# 通过 HTTPS 调用 LiteSight 开放接口，使用个人访问令牌（PAT）鉴权。
# 依赖：bash、curl。
#
# 安全约定：
#   - 接口地址固定为 LiteSight 官方域名，不能通过环境变量或参数修改。
#   - 令牌通过标准输入交给 curl，不出现在命令行参数里。
#   - 分享文案等不可信文本通过文件或标准输入传入，不放在命令行参数里。
#   - 扣积分（submit）和生成支付入口（recharge）必须经过确认，见下方
#     “确认机制”一节；submit 只接受本机刚报过价、尚未过期的 quote_id，
#     并在确认前回显本次费用。
#   - 不提供强制重新解析的开关：已解析过的链接不会被重复扣费。
#

set -euo pipefail

readonly LITESIGHT_API_BASE="https://www.litesight.cn/api/admin/skillhub"
readonly LITESIGHT_TOKEN_FILE="${HOME}/.config/litesight/token"
readonly LITESIGHT_QUOTE_DIR="${HOME}/.cache/litesight/quotes"
readonly LITESIGHT_QUOTE_TTL=600
readonly LITESIGHT_MAX_INPUT=4000

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

# 从响应 JSON 里取一个数字字段；取不到时输出空
json_number() {
    local re="\"$2\"[[:space:]]*:[[:space:]]*([0-9]+)"
    [[ "$1" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}" || true
}

require_task_id() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] || die "task_id must be a number. $2"
}

require_bool() {
    [[ "$1" == "true" || "$1" == "false" ]] || die "$2 must be true or false"
}

require_quote_id() {
    [[ "${1:-}" =~ ^[A-Za-z0-9-]{8,64}$ ]] || die "invalid quote_id"
}

# ---------------------------------------------------------------------------
# 本机报价记录：quote 成功后记下费用，submit 时据此回显并校验
# ---------------------------------------------------------------------------

save_quote() {
    local body=$1 re='"quote_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9-]{8,64})"'
    [[ "$body" =~ $re ]] || return 0
    local quote_id=${BASH_REMATCH[1]}
    local credits balance duration
    credits=$(json_number "$body" required_credits)
    balance=$(json_number "$body" balance)
    duration=$(json_number "$body" duration_seconds)
    [[ -n "$credits" ]] || return 0

    mkdir -p "$LITESIGHT_QUOTE_DIR"
    (umask 077 && printf '%s %s %s %s\n' "$credits" "${balance:-0}" "${duration:-0}" "$(date +%s)" \
        > "$LITESIGHT_QUOTE_DIR/$quote_id")
}

# 读取报价记录，结果放进 QUOTE_CREDITS / QUOTE_BALANCE / QUOTE_DURATION
load_quote() {
    local file="$LITESIGHT_QUOTE_DIR/$1" saved_at now
    [[ -f "$file" ]] || die "no local record of this quote. Run 'quote' first and show the cost to the user."
    read -r QUOTE_CREDITS QUOTE_BALANCE QUOTE_DURATION saved_at < "$file"
    [[ "$QUOTE_CREDITS" =~ ^[0-9]+$ && "$saved_at" =~ ^[0-9]+$ ]] || die "quote record is corrupted. Run 'quote' again."
    now=$(date +%s)
    if (( now - saved_at > LITESIGHT_QUOTE_TTL )); then
        rm -f "$file"
        die "this quote has expired. Run 'quote' again and show the new cost to the user."
    fi
}

# ---------------------------------------------------------------------------
# 确认机制
# ---------------------------------------------------------------------------
# >>> confirmation
# 调用方必须带 --yes，表示用户已经在对话里明确同意本次操作。
# 不带时中止，不发出任何请求。
confirm_action() {
    local confirmed=$1 what=$2
    echo "$what" >&2
    if [[ "$confirmed" != "true" ]]; then
        echo "Error: this action requires explicit user confirmation." >&2
        echo "Show the cost above to the user and ask. Only after the user clearly agrees, run the command again with --yes." >&2
        exit 2
    fi
}
# <<< confirmation

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

# 命令：报价（不扣费）
#   quote --file <path>   从文件读取链接或整段分享文案（推荐）
#   quote -               从标准输入读取
#   quote <url>           只接受不含空格和引号的纯链接
cmd_quote() {
    local usage="Usage: litesight quote --file <path> | quote - | quote <plain-url>"
    local text url_re='^https?://[A-Za-z0-9._~:/?#@!&=%+,;-]+$'

    case "${1:-}" in
        "") die "$usage" ;;
        -)
            [[ $# -eq 1 ]] || die "$usage"
            text=$(head -c "$LITESIGHT_MAX_INPUT")
            ;;
        --file)
            [[ $# -eq 2 ]] || die "$usage"
            [[ -f "$2" ]] || die "file not found: $2"
            text=$(head -c "$LITESIGHT_MAX_INPUT" -- "$2")
            ;;
        *)
            [[ $# -eq 1 && "$1" =~ $url_re ]] \
                || die "only a plain URL may be passed as an argument. Put share text in a file and use: quote --file <path>"
            text=$1
            ;;
    esac

    [[ -n "$text" ]] || die "empty input"

    local resp rc=0
    resp=$(api_call POST "/quotes" "{\"url\":\"$(json_escape "$text")\"}") || rc=$?
    printf '%s\n' "$resp"
    [[ $rc -eq 0 ]] || exit "$rc"
    save_quote "$resp"
}

# 命令：提交任务（扣积分，需要确认）
cmd_submit() {
    local usage="Usage: litesight submit <quote_id> --yes [--idempotency-key <key>]"
    local quote_id="" idempotency_key="" confirmed=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes) confirmed=true; shift ;;
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
    require_quote_id "$quote_id"
    if [[ -n "$idempotency_key" ]]; then
        [[ "$idempotency_key" =~ ^[A-Za-z0-9_.:-]{1,128}$ ]] || die "invalid idempotency key"
    fi

    load_quote "$quote_id"
    confirm_action "$confirmed" \
        "Submit quote $quote_id: spends $QUOTE_CREDITS credit(s); balance $QUOTE_BALANCE; video length ${QUOTE_DURATION}s."

    [[ -n "$idempotency_key" ]] || idempotency_key="$(date +%s)-${RANDOM}${RANDOM}"

    # force 固定为 false：已解析过的链接由服务端去重，不会重复扣费
    api_call POST "/tasks" "{\"quoteId\":\"$quote_id\",\"idempotencyKey\":\"$idempotency_key\",\"force\":false}"

    # 报价一次有效：提交成功后删除本机记录
    rm -f "$LITESIGHT_QUOTE_DIR/$quote_id"
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

# 命令：充值链接（生成支付入口，需要确认）
cmd_recharge() {
    local confirmed=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes) confirmed=true; shift ;;
            *) die "Unknown option: $1. Usage: litesight recharge --yes" ;;
        esac
    done

    confirm_action "$confirmed" "Create a LiteSight recharge link (opens a payment page; nothing is charged by this command)."

    api_call POST "/recharge-link"
}

usage() {
    cat <<EOF
LiteSight CLI

Usage:
  litesight configure              Configure Personal Access Token
  litesight account                Get account status and credits
  litesight list [status] [page] [size]  List analysis tasks
  litesight quote --file <path>    Quote a video link or share text read from a file (free)
  litesight quote -                Same, read from standard input
  litesight quote <plain-url>      Same, for a URL without spaces or quotes
  litesight submit <quote_id> --yes [--idempotency-key <key>]
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
