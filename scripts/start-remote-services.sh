#!/bin/sh
set -eu

SUPERVISOR_CONFIG="/etc/monkeycode-remote/supervisord.conf"
SUPERVISOR_PID_FILE="/run/monkeycode-remote/supervisord.pid"
TOKEN_FILE="/etc/cloudflared/token"

fail() {
    printf '错误: %s\n' "$1" >&2
    exit 1
}

supervisor_control() {
    /usr/bin/supervisorctl -c "$SUPERVISOR_CONFIG" "$@"
}

ssh_endpoint_is_ready() {
    nc -z -w 1 127.0.0.1 22 >/dev/null 2>&1
}

[ "$(id -u)" -eq 0 ] || fail '必须以 root 身份运行'
[ -s "$TOKEN_FILE" ] || fail '缺少 Tunnel Token，请先运行 install-cloudflared-token'
[ -f "$SUPERVISOR_CONFIG" ] || fail "缺少 Supervisor 配置: $SUPERVISOR_CONFIG"

chmod 0600 "$TOKEN_FILE"
install -d -m 0755 /run/monkeycode-remote /run/sshd /var/log/monkeycode-remote
ssh-keygen -A

if [ -s "$SUPERVISOR_PID_FILE" ] && kill -0 "$(cat "$SUPERVISOR_PID_FILE")" 2>/dev/null; then
    supervisor_control reread >/dev/null
    supervisor_control update >/dev/null
else
    rm -f -- "$SUPERVISOR_PID_FILE" /run/monkeycode-remote/supervisor.sock
    /usr/bin/supervisord -c "$SUPERVISOR_CONFIG"
fi

attempt=0
while ! supervisor_control status cloudflared 2>/dev/null | grep -Eq '^[^[:space:]]+[[:space:]]+RUNNING([[:space:]]|$)'; do
    cloudflared_state="$(supervisor_control status cloudflared 2>/dev/null | awk '{ print $2 }' || true)"
    case "$cloudflared_state" in
        STARTING) ;;
        *) supervisor_control start cloudflared >/dev/null 2>&1 || true ;;
    esac
    attempt=$((attempt + 1))
    [ "$attempt" -lt 40 ] || fail 'cloudflared 未能按时进入 RUNNING 状态'
    sleep 1
done

if ssh_endpoint_is_ready; then
    printf '检测到 127.0.0.1:22 已有 SSH 服务，保留平台现有服务。\n'
else
    sshd_state="$(supervisor_control status sshd 2>/dev/null | awk '{ print $2 }' || true)"
    case "$sshd_state" in
        RUNNING|STARTING) ;;
        *) supervisor_control start sshd >/dev/null 2>&1 || true ;;
    esac

    attempt=0
    while ! ssh_endpoint_is_ready; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 20 ] || fail 'OpenSSH 未能按时监听 127.0.0.1:22'
        sleep 1
    done
    printf '已由 Supervisor 启动 OpenSSH，并监听 127.0.0.1:22。\n'
fi

supervisor_control status cloudflared
ssh_endpoint_is_ready || fail 'SSH 端点 127.0.0.1:22 不可用'
printf '远程服务已启动；可运行 remote-services-status 查看状态。\n'
