# Stage 1: Build Go auth server
FROM golang:1.22-bookworm AS go-builder

WORKDIR /build
COPY core/scripts/auth/user_auth.go .
RUN echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf && \
    go mod init hysteria_auth && go mod tidy && go build -o user_auth .

# Stage 2: Runtime
FROM ubuntu:24.04

# TARGETARCH is set automatically by Docker (amd64, arm64, arm/v7, etc.)
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 \
    python3-venv \
    curl \
    openssl \
    jq \
    lsof \
    supervisor \
    wireguard-tools \
    iptables \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Install Hysteria2 binary from GitHub Releases using Docker TARGETARCH
RUN HY_VERSION=$(curl -fsSL "https://api.github.com/repos/apernet/hysteria/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//') && \
    echo "Downloading hysteria ${HY_VERSION} for linux-${TARGETARCH}..." && \
    curl -fsSL -o /usr/local/bin/hysteria \
        "https://github.com/apernet/hysteria/releases/download/${HY_VERSION}/hysteria-linux-${TARGETARCH}" && \
    chmod +x /usr/local/bin/hysteria

# Copy compiled Go auth server
COPY --chmod=755 --from=go-builder /build/user_auth /etc/hysteria/core/scripts/auth/user_auth

# Copy application source
COPY . /etc/hysteria/

# Create Python venv, install dependencies, and expose packages to system python3
RUN python3 -m venv /etc/hysteria/hysteria2_venv && \
    /etc/hysteria/hysteria2_venv/bin/pip install --no-cache-dir -r /etc/hysteria/requirements.txt && \
    find /etc/hysteria/hysteria2_venv/lib -name site-packages -type d \
        > /usr/lib/python3/dist-packages/hysteria-venv.pth

# Download geo data at build time (same as bare-metal install.sh)
RUN curl -fsSL --max-time 30 -o /etc/hysteria/geosite.dat \
        "https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat" && \
    curl -fsSL --max-time 30 -o /etc/hysteria/geoip.dat \
        "https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"

# Preserve the repo config.json as a template (entrypoint symlinks config.json to volume)
RUN cp /etc/hysteria/config.json /etc/hysteria/config.json.template

# Install systemctl shim so existing scripts work in Docker
COPY --chmod=755 docker/systemctl-shim.sh /usr/local/bin/systemctl

# Copy entrypoint
COPY --chmod=755 docker/entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
