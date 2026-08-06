#!/bin/sh
set -eu

# SSH 公钥从标准输入读取并去重写入，镜像内不预置任何用户凭据。
AUTHORIZED_KEYS_FILE="${SSH_AUTHORIZED_KEYS_FILE:-/root/.ssh/authorized_keys}"

fail() {
    printf '错误: %s\n' "$1" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail '必须以 root 身份运行'
[ "$#" -eq 0 ] || fail '请通过标准输入提供 SSH 公钥'

public_key=""
if [ -t 0 ]; then
    printf '请粘贴一行 SSH 公钥: ' >&2
fi
IFS= read -r public_key || true

case "$public_key" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
    *) fail 'SSH 公钥格式不受支持' ;;
esac

key_directory="$(dirname -- "$AUTHORIZED_KEYS_FILE")"
install -d -m 0700 "$key_directory"
touch "$AUTHORIZED_KEYS_FILE"
chmod 0600 "$AUTHORIZED_KEYS_FILE"

if grep -Fqx -- "$public_key" "$AUTHORIZED_KEYS_FILE"; then
    printf 'SSH 公钥已存在，无需重复写入。\n'
else
    printf '%s\n' "$public_key" >> "$AUTHORIZED_KEYS_FILE"
    printf 'SSH 公钥已写入 %s。\n' "$AUTHORIZED_KEYS_FILE"
fi

unset public_key
