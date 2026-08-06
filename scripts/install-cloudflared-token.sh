#!/bin/sh
set -eu

# Tunnel Token 只允许从标准输入读取，避免进入 shell 历史和进程参数。
TOKEN_FILE="/etc/cloudflared/token"
temporary_file=""
saved_tty=""

fail() {
    printf '错误: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    if [ -n "$saved_tty" ]; then
        stty "$saved_tty" 2>/dev/null || true
    fi
    if [ -n "$temporary_file" ] && [ -f "$temporary_file" ]; then
        rm -f -- "$temporary_file"
    fi
}

trap cleanup EXIT HUP INT TERM

[ "$(id -u)" -eq 0 ] || fail '必须以 root 身份运行'
[ "$#" -eq 0 ] || fail '禁止通过命令行参数传递 Tunnel Token'

token=""
if [ -t 0 ]; then
    saved_tty="$(stty -g)"
    printf '请输入新的 Cloudflare Tunnel Token: ' >&2
    stty -echo
    IFS= read -r token || true
    stty "$saved_tty"
    saved_tty=""
    printf '\n' >&2
else
    IFS= read -r token || true
fi

[ -n "$token" ] || fail 'Tunnel Token 不能为空'

token_directory="$(dirname -- "$TOKEN_FILE")"
install -d -m 0755 "$token_directory"
umask 077
temporary_file="$(mktemp "${TOKEN_FILE}.tmp.XXXXXX")"
printf '%s' "$token" > "$temporary_file"
chmod 0600 "$temporary_file"
mv -f -- "$temporary_file" "$TOKEN_FILE"
temporary_file=""
unset token

printf 'Tunnel Token 已安全写入 %s（权限 0600）。\n' "$TOKEN_FILE"
