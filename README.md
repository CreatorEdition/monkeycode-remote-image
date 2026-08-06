# MonkeyCode Remote Image

面向 MonkeyCode Firecracker 开发环境的远程工作镜像。镜像以 MonkeyCode 官方 `base:bookworm` 为基础，补充最新 Node.js LTS、最新稳定版 cloudflared、OpenSSH 与进程守护能力，供本地 Agent 通过 Cloudflare Tunnel 操作远端 `/workspace`。

## 设计目标

- 优先使用上游最新稳定组件，由 GitHub Actions 每日重新拉取并构建。
- 发布后使用 OCI digest 固定实际运行版本，避免可变标签导致环境漂移。
- 不修改基础镜像的 `ENTRYPOINT` 或 `CMD`，降低 MonkeyCode 私有 Firecracker 启动器的兼容风险。
- Tunnel Token、SSH 私钥、密码和 Cookie 均不进入镜像、仓库或构建日志。
- cloudflared 与专用 OpenSSH 由 Supervisor 守护，异常退出后自动拉起，并通过 cloudflared `/ready` 验证真实 Edge 连接。

## 上游镜像策略

| 组件 | 构建来源 | 策略 |
|---|---|---|
| MonkeyCode | `ghcr.io/chaitin/monkeycode-runner/base:bookworm` | 每次构建强制拉取 |
| Node.js | `node:lts-bookworm-slim` | 使用最新 LTS，不追踪短生命周期 Current |
| cloudflared | `cloudflare/cloudflared:latest` | 使用 Cloudflare 官方最新稳定镜像 |

GitHub Actions 只构建 `linux/amd64`，并关闭额外的 provenance/SBOM manifest，减少 MonkeyCode 私有镜像解析器的兼容风险。

## 构建与发布

PR 工作流仅获得仓库只读权限，执行静态检查、真实镜像构建和冒烟测试，但不登录或推送 GHCR。合并到 `main`、手动触发或每日 UTC 03:17 定时任务会先载入并测试最终镜像，只有同一镜像通过后才推送 GHCR。首次发布后必须在 GitHub Package 设置中确认镜像为 `Public`，并从未登录 GHCR 的环境验证匿名拉取。

本地需要 Docker Buildx 时，可执行：

```sh
docker buildx build --pull --platform linux/amd64 \
  --tag ghcr.io/creatoredition/monkeycode-remote-image:local \
  --load .
```

构建阶段允许上游标签前进，以获得最新的 MonkeyCode base、Node.js LTS 和 cloudflared；部署阶段必须使用 Actions 摘要中的不可变地址：

```text
ghcr.io/creatoredition/monkeycode-remote-image@sha256:<构建摘要中的 digest>
```

不要长期把 `:latest` 绑定到 MonkeyCode。它只用于首次兼容性验证和发现新版本。

## Cloudflare 前置配置

在 Cloudflare Zero Trust 中创建远程管理 Tunnel，并为目标主机名配置：

```text
Service: ssh://127.0.0.1:2222
```

镜像使用专用回环端口 `2222`，避免误用或覆盖 MonkeyCode 平台可能存在的 `22` 端口服务。若现有 Tunnel 仍指向 `ssh://127.0.0.1:22`，必须先在 Cloudflare Dashboard 中改成上述地址。建议同时为该主机名配置 Cloudflare Access 策略。Tunnel Token 仅在 MonkeyCode VM 运行时写入，不参与镜像构建。

## MonkeyCode 首次配置

先临时绑定公开的 `:latest` 验证平台兼容性，再在 MonkeyCode Web Shell 中依次执行：

```sh
node --version
cloudflared --version
install-cloudflared-token
install-ssh-public-key
start-remote-services
remote-services-status
```

`install-cloudflared-token` 会关闭终端回显并从标准输入读取 Token；`install-ssh-public-key` 只接受一行公钥。不要把 Token 或私钥放在命令参数、Shell 历史、项目文件或截图中。

`start-remote-services` 启动后台 Supervisor，等待 cloudflared 至少建立一条可用 Edge 连接，并确认受本镜像加固的 OpenSSH 在 `127.0.0.1:2222` 返回有效 Host Key 后才返回终端。此后不需要保持 Web Shell 打开，也不要再手动执行 `cloudflared tunnel run`。

常用管理命令：

```sh
remote-services-status
supervisorctl -c /etc/monkeycode-remote/supervisord.conf restart cloudflared
supervisorctl -c /etc/monkeycode-remote/supervisord.conf status
```

如需轮换 Tunnel Token，重新运行 `install-cloudflared-token`，再重启 cloudflared。

## 本地 SSH 与 Agent 接入

本地机器需要安装 `cloudflared`，并保管对应 SSH 私钥。在 `~/.ssh/config` 中添加：

```sshconfig
Host monkeycode-remote
    HostName monkeycode.example.com
    User root
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
    ServerAliveInterval 30
    ServerAliveCountMax 3
    StrictHostKeyChecking accept-new
```

把 `monkeycode.example.com` 替换为 Tunnel 的真实主机名，然后连接：

```sh
ssh monkeycode-remote
```

每个新 VM 都会生成独立 SSH Host Key。确认环境确实被重建后，如本地报告 Host Key 变化，应先删除该主机名的旧记录再重新核验并连接；不要通过关闭 Host Key 检查来绕过告警。

## 稳定性黑盒验收

镜像构建成功不能证明 MonkeyCode 的 Firecracker 生命周期行为。首次部署至少完成以下验收：

1. `remote-services-status` 返回成功，cloudflared 为 `RUNNING` 且 `/ready` 可用，`127.0.0.1:2222` 返回有效 SSH Host Key。
2. 本地 SSH 能进入 `/workspace`，关闭 Web Shell 并等待至少 10 分钟后仍能重新连接。
3. 验证 Supervisor 自动恢复 cloudflared：

   ```sh
   old_pid="$(supervisorctl -c /etc/monkeycode-remote/supervisord.conf pid cloudflared)"
   test "$old_pid" -gt 1
   kill "$old_pid"
   sleep 15
   remote-services-status
   ```

4. 按平台允许的方式分别执行一次休眠/恢复与完整 VM 重启。休眠恢复后直接检查状态；完整重启后按下一节执行 Web Shell 恢复命令。
5. 在 Cloudflare 日志中确认 Tunnel 重新注册连接，而不是只看到本地进程存活。

Supervisor 能处理当前 VM 内的进程异常退出，但不能绕过 MonkeyCode 的空闲休眠、每日额度、完整重启或 VM 回收策略。

## 完整重启与新 VM 恢复

当前未发现 MonkeyCode 可验证的自定义开机启动钩子，因此不能把 Supervisor 的进程重启能力理解为系统开机自启。完整 VM 重启后，进入 MonkeyCode Web Shell 执行：

```sh
start-remote-services
remote-services-status
```

如果提示 Token 或公钥不存在，说明平台提供的是全新 VM 或未保留对应文件系统；需重新运行 `install-cloudflared-token`、`install-ssh-public-key`，再运行上述启动命令。完成 MonkeyCode 黑盒验证并确认存在可靠启动钩子前，不要自动修改镜像 `ENTRYPOINT/CMD`。

## 安全边界

- 禁止把 Cloudflare Tunnel Token 作为任何构建输入，包括 Dockerfile、GitHub Secrets、普通项目环境变量或命令行参数。
- 禁止在镜像中预生成 SSH Host Key；每个 VM 必须在首次启动时单独生成。
- 本镜像管理的 SSH 只监听 VM 回环地址 `127.0.0.1:2222`，外部入口必须经过 Cloudflare Tunnel。
- GHCR 镜像可以公开，但其中不得包含任何运行时凭据。
- Cloudflare Tunnel 在线不等于 MonkeyCode VM 保活；休眠和回收策略必须在 MonkeyCode 平台侧单独处理。

## 回退策略

若 `base:bookworm` 在 MonkeyCode 私有 Firecracker 运行时缺少平台注入能力，第二阶段只修改基础镜像参数并重新走 PR/CI：

```dockerfile
ARG MONKEYCODE_BASE_IMAGE=ghcr.io/chaitin/monkeycode-runner/devbox:latest
```

`devbox` 已包含自己的 Node.js；当前多阶段复制仍会把它统一到最新 Node.js LTS。回退后必须重新执行完整黑盒验收，并固定新的发布 digest。

cloudflared 的 ICMP proxy 权限警告不会影响 `ssh://` TCP ingress。只有在 QUIC 实际反复断线且日志与网络测试能复现时，才评估固定 HTTP/2；当前默认保留 Cloudflare 自动协议选择。
