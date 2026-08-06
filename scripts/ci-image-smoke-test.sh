#!/bin/sh
set -eu

# 该脚本只在一次性 CI 容器中运行，用于验证最终镜像的关键安全约束。
test "$(id -u)" -eq 0
command -v node >/dev/null
command -v npm >/dev/null
command -v cloudflared >/dev/null
command -v supervisord >/dev/null
command -v sshd >/dev/null
command -v ssh-keyscan >/dev/null

test "$(node -p process.release.lts)" != "undefined"
cloudflared tunnel run --help | grep -q -- '--token-file'
cloudflared tunnel ready --help | grep -q -- '--metrics'

test ! -e /etc/cloudflared/token
test ! -s /root/.ssh/authorized_keys
test -z "$(find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*_key' -print -quit)"

ssh-keygen -A >/dev/null
sshd -t
sshd_config="$(sshd -T)"
printf '%s\n' "$sshd_config" | grep -qx 'port 2222'
printf '%s\n' "$sshd_config" | grep -qx 'listenaddress 127.0.0.1:2222'
printf '%s\n' "$sshd_config" | grep -qx 'passwordauthentication no'
printf '%s\n' "$sshd_config" | grep -qx 'authenticationmethods publickey'

printf '%s\n' 'dummy-ci-token' | install-cloudflared-token
test "$(stat -c '%a' /etc/cloudflared/token)" = "600"

ssh-keygen -q -t ed25519 -N "" -f /tmp/ci-ssh-key
IFS= read -r public_key < /tmp/ci-ssh-key.pub
printf '%s\n' "$public_key" | install-ssh-public-key
grep -Fqx -- "$public_key" /root/.ssh/authorized_keys
test "$(stat -c '%a' /root/.ssh/authorized_keys)" = "600"

rm -f /tmp/ci-ssh-key /tmp/ci-ssh-key.pub
unset public_key sshd_config
