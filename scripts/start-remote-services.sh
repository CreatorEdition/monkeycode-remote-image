#!/bin/sh
set -eu

SUPERVISOR_CONFIG="/etc/monkeycode-remote/supervisord.conf"
SUPERVISOR_PID_FILE="/run/monkeycode-remote/supervisord.pid"
TOKEN_FILE="/etc/cloudflared/token"
METRICS_ADDRESS="127.0.0.1:20241"
SSH_HOST="127.0.0.1"
SSH_PORT="2222"

fail() {
    printf '错误: %s\n' "$1" >&2
    exit 1
}

supervisor_control() {
    /usr/bin/supervisorctl -c "$SUPERVISOR_CONFIG" "$@"
}

program_is_running() {
    supervisor_control status "$1" 2>/dev/null |
        grep -Eq '^[^[:space:]]+[[:space:]]+RUNNING([[:space:]]|$)'
}

start_program_if_needed() {
    program_name="$1"
    program_state="$(supervisor_control status "$program_name" 2>/dev/null | awk '{ print $2 }' || true)"
    case "$program_state" in
        RUNNING|STARTING) ;;
        *) supervisor_control start "$program_name" >/dev/null 2>&1 || true ;;
    esac
}

cloudflared_tunnel_is_ready() {
    /usr/local/bin/cloudflared tunnel --metrics "$METRICS_ADDRESS" ready >/dev/null 2>&1
}

ssh_endpoint_is_ready() {
    ssh-keyscan -T 2 -p "$SSH_PORT" "$SSH_HOST" >/dev/null 2>&1
}

[ "$(id -u)" -eq 0 ] || fail '必须以 root 身份运行'
[ -s "$TOKEN_FILE" ] || fail '缺少 Tunnel Token，请先运行 install-cloudflared-token'
[ -f "$SUPERVISOR_CONFIG" ] || fail "缺少 Supervisor 配置: $SUPERVISOR_CONFIG"

chmod 0600 "$TOKEN_FILE"
install -d -m 0755 /run/monkeycode-remote /run/sshd /var/log/monkeycode-remote
ssh-keygen -A
sshd -t

if [ -s "$SUPERVISOR_PID_FILE" ] && kill -0 "$(cat "$SUPERVISOR_PID_FILE")" 2>/dev/null; then
    supervisor_control reread >/dev/null
    supervisor_control update >/dev/null
else
    rm -f -- "$SUPERVISOR_PID_FILE" /run/monkeycode-remote/supervisor.sock
    /usr/bin/supervisord -c "$SUPERVISOR_CONFIG"
fi

attempt=0
while ! program_is_running sshd || ! ssh_endpoint_is_ready; do
    start_program_if_needed sshd
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || fail "OpenSSH 未能按时监听 ${SSH_HOST}:${SSH_PORT}"
    sleep 1
done

attempt=0
while ! program_is_running cloudflared || ! cloudflared_tunnel_is_ready; do
    start_program_if_needed cloudflared
    attempt=$((attempt + 1))
    [ "$attempt" -lt 120 ] || fail 'cloudflared 未能在 120 秒内建立可用 Tunnel 连接，请检查日志'
    sleep 1
done

supervisor_control status sshd cloudflared
ssh_endpoint_is_ready || fail "SSH 端点 ${SSH_HOST}:${SSH_PORT} 不可用"
cloudflared_tunnel_is_ready || fail 'cloudflared Tunnel 尚未连接 Cloudflare Edge'
printf '远程服务已启动；OpenSSH 监听 %s:%s。\n' "$SSH_HOST" "$SSH_PORT"
printf '可运行 remote-services-status 查看状态。\n'
