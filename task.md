# 任务记录

## ✅ 已完成：构建 MonkeyCode 远程工作镜像

日期：2026-08-06

### 目标

- 基于 MonkeyCode 官方 `base:bookworm` 构建远程工作镜像。
- 使用最新 Node.js LTS 与最新稳定版 cloudflared。
- 通过 Supervisor 守护 cloudflared，并提供安全的运行时凭据配置流程。
- 使用 GitHub Actions 构建 `linux/amd64` 并发布到公开 GHCR。
- 完成静态检查、独立安全审计、中文提交和 PR。

### 实施清单

- [x] 确认仓库为空并建立主分支
- [x] 完成 latest 与不可变 digest 的方案裁决
- [x] 实现 Dockerfile 与运行时脚本
- [x] 实现 GitHub Actions 构建发布流程
- [x] 更新使用与安全文档
- [x] 执行静态检查和独立审计
- [x] 推送分支并创建 PR
- [x] 等待 PR CI 成功
- [x] 合并 PR 并确认 GHCR 可匿名拉取

### 发布结果

- 实现 PR：<https://github.com/CreatorEdition/monkeycode-remote-image/pull/1>
- 发布工作流：<https://github.com/CreatorEdition/monkeycode-remote-image/actions/runs/31063816756>
- 不可变镜像：`ghcr.io/creatoredition/monkeycode-remote-image@sha256:50322b4ac849f75f0aa67d6562434275d50622a07f4fe9e2985874d7a4aa60aa`
- 匿名 GHCR Manifest 请求返回 HTTP 200，`latest` 与不可变 SHA 标签指向同一 digest。
- 发布镜像实测 Node.js `v24.19.0`、npm `11.17.0`、cloudflared `2026.7.3`。

### 风险

- MonkeyCode 的私有 Firecracker 启动器可能忽略 OCI `ENTRYPOINT/CMD`，因此镜像不依赖它们自动启动服务。
- Tunnel 流量不会自动刷新 MonkeyCode 的任务 VM 空闲计时。
