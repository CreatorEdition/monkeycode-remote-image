# syntax=docker/dockerfile:1.7

ARG MONKEYCODE_BASE_IMAGE=ghcr.io/chaitin/monkeycode-runner/base:bookworm
ARG NODE_IMAGE=node:lts-bookworm-slim
ARG CLOUDFLARED_IMAGE=cloudflare/cloudflared:latest

FROM ${NODE_IMAGE} AS node_runtime
FROM ${CLOUDFLARED_IMAGE} AS cloudflared_runtime
FROM ${MONKEYCODE_BASE_IMAGE}

ARG BUILD_DATE=""
ARG VCS_REF=""

LABEL org.opencontainers.image.title="MonkeyCode Remote Image" \
      org.opencontainers.image.description="MonkeyCode remote workspace with Node.js LTS, cloudflared, OpenSSH and Supervisor" \
      org.opencontainers.image.source="https://github.com/CreatorEdition/monkeycode-remote-image" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

ARG DEBIAN_FRONTEND=noninteractive

COPY --from=node_runtime /usr/local/ /usr/local/
COPY --from=cloudflared_runtime /usr/local/bin/cloudflared /usr/local/bin/cloudflared

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        iproute2 \
        iputils-ping \
        jq \
        netcat-openbsd \
        openssh-server \
        python3-venv \
        rsync \
        supervisor; \
    mkdir -p \
        /etc/cloudflared \
        /etc/monkeycode-remote \
        /root/.ssh \
        /run/monkeycode-remote \
        /run/sshd \
        /var/log/monkeycode-remote; \
    chmod 0700 /root/.ssh; \
    chmod 0755 /etc/cloudflared /etc/monkeycode-remote; \
    sshd -t; \
    rm -f /etc/ssh/ssh_host_*; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    if command -v corepack >/dev/null 2>&1; then corepack enable; fi; \
    node --version; \
    npm --version; \
    python3 --version; \
    cloudflared --version

COPY config/sshd/monkeycode.conf /etc/ssh/sshd_config.d/monkeycode.conf
COPY config/supervisor/monkeycode-remote.conf /etc/monkeycode-remote/supervisord.conf
COPY scripts/install-cloudflared-token.sh /usr/local/sbin/install-cloudflared-token
COPY scripts/install-ssh-public-key.sh /usr/local/sbin/install-ssh-public-key
COPY scripts/start-remote-services.sh /usr/local/sbin/start-remote-services
COPY scripts/remote-services-status.sh /usr/local/sbin/remote-services-status

RUN set -eux; \
    chmod 0755 \
        /usr/local/sbin/install-cloudflared-token \
        /usr/local/sbin/install-ssh-public-key \
        /usr/local/sbin/start-remote-services \
        /usr/local/sbin/remote-services-status; \
    chmod 0644 \
        /etc/ssh/sshd_config.d/monkeycode.conf \
        /etc/monkeycode-remote/supervisord.conf; \
    ssh-keygen -A; \
    sshd -t; \
    rm -f /etc/ssh/ssh_host_*

WORKDIR /workspace
