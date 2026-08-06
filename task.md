# 任务记录

## 🔄 进行中：构建 MonkeyCode 远程工作镜像

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
- [ ] 合并 PR 并确认 GHCR 可匿名拉取

### 风险

- MonkeyCode 的私有 Firecracker 启动器可能忽略 OCI `ENTRYPOINT/CMD`，因此镜像不依赖它们自动启动服务。
- GHCR 首次发布后的默认可见性可能不是公开，需要通过 API 或 Package 设置确认。
- Tunnel 流量不会自动刷新 MonkeyCode 的任务 VM 空闲计时。
