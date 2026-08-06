#!/bin/sh
set -eu

SUPERVISOR_CONFIG="/etc/monkeycode-remote/supervisord.conf"
METRICS_ADDRESS="127.0.0.1:20241"
SSH_HOST="127.0.0.1"
SSH_PORT="2222"
overall_status=0

supervisor_control() {
    /usr/bin/supervisorctl -c "$SUPERVISOR_CONFIG" "$@"
}

program_is_running() {
    supervisor_control status "$1" 2>/dev/null |
        grep -Eq '^[^[:space:]]+[[:space:]]+RUNNING([[:space:]]|$)'
}

[ "$(id -u)" -eq 0 ] || {
    printf '%s\n' '错误: 必须以 root 身份运行。' >&2
    exit 1
}

printf '%s\n' '=== 版本 ==='
python3 --version
node --version
npm --version
cloudflared --version

printf '%s\n' '=== 进程 ==='
if [ -S /run/monkeycode-remote/supervisor.sock ]; then
    supervisor_control status || true
    for program_name in sshd cloudflared; do
        if ! program_is_running "$program_name"; then
            printf '错误: %s 未处于 RUNNING 状态。\n' "$program_name" >&2
            overall_status=1
        fi
    done
else
    printf '%s\n' '错误: Supervisor 尚未启动。' >&2
    overall_status=1
fi

printf '%s\n' '=== Tunnel 连通性 ==='
if /usr/local/bin/cloudflared tunnel --metrics "$METRICS_ADDRESS" ready >/dev/null 2>&1; then
    printf 'cloudflared 已连接 Cloudflare Edge（metrics: %s）。\n' "$METRICS_ADDRESS"
else
    printf '%s\n' '错误: cloudflared /ready 尚未确认可用连接。' >&2
    overall_status=1
fi

printf '%s\n' '=== SSH 端点 ==='
if ssh-keyscan -T 2 -p "$SSH_PORT" "$SSH_HOST" >/dev/null 2>&1; then
    printf '%s:%s 已确认为 SSH 服务。\n' "$SSH_HOST" "$SSH_PORT"
    ss -H -ltnp | awk -v port=":${SSH_PORT}" '$4 ~ (port "$") { print }'
else
    printf '错误: %s:%s 未返回有效 SSH Host Key。\n' "$SSH_HOST" "$SSH_PORT" >&2
    overall_status=1
fi

printf '%s\n' '=== cloudflared 最近日志 ==='
if [ -f /var/log/monkeycode-remote/cloudflared.log ]; then
    tail -n 20 /var/log/monkeycode-remote/cloudflared.log
else
    printf '%s\n' '尚无 cloudflared 日志。'
fi

exit "$overall_status"
