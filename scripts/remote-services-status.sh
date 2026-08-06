#!/bin/sh
set -eu

SUPERVISOR_CONFIG="/etc/monkeycode-remote/supervisord.conf"
overall_status=0

printf '%s\n' '=== 版本 ==='
python3 --version
node --version
npm --version
cloudflared --version

printf '%s\n' '=== 进程 ==='
if [ -S /run/monkeycode-remote/supervisor.sock ]; then
    /usr/bin/supervisorctl -c "$SUPERVISOR_CONFIG" status || true
    cloudflared_status="$(/usr/bin/supervisorctl -c "$SUPERVISOR_CONFIG" status cloudflared 2>&1 || true)"
    if printf '%s\n' "$cloudflared_status" | grep -Eq '^[^[:space:]]+[[:space:]]+RUNNING([[:space:]]|$)'; then
        :
    else
        printf '错误: cloudflared 未处于 RUNNING 状态。\n' >&2
        overall_status=1
    fi
else
    printf '%s\n' 'Supervisor 尚未启动。'
    overall_status=1
fi

printf '%s\n' '=== SSH 端点 ==='
if nc -z -w 1 127.0.0.1 22 >/dev/null 2>&1; then
    printf '%s\n' '127.0.0.1:22 可连接。'
    ss -H -ltnp | awk '$4 ~ /:22$/ { print }'
else
    printf '%s\n' '错误: 127.0.0.1:22 不可连接。' >&2
    overall_status=1
fi

printf '%s\n' '=== cloudflared 最近日志 ==='
if [ -f /var/log/monkeycode-remote/cloudflared.log ]; then
    tail -n 20 /var/log/monkeycode-remote/cloudflared.log
else
    printf '%s\n' '尚无 cloudflared 日志。'
fi

exit "$overall_status"
