# syntax=docker/dockerfile:1

# ---- builder ----------------------------------------------------------------
# Builds the Go c-archive (libwg) and then the Rust binary.
FROM rust:1-bookworm AS builder

# The netstack build needs Go >= 1.23: wireguard-go's tun/netstack and the
# pinned gvisor (v0.0.0-20250503...) use gvisor's pkg/buffer API, and go.mod
# declares `go 1.23.1`. (Older Go 1.20.x no longer works — that gvisor's
# gohacks package excludes pre-1.21 toolchains.)
ARG GO_VERSION=1.23.7
ARG TARGETARCH=amd64

# Go toolchain (for the cgo c-archive) + clang/libclang for bindgen
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git build-essential clang libclang-dev \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
        | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /src
COPY . .

# 1) build libwg (gVisor netstack + SOCKS5 proxy) as a C archive
# 2) build the corplink-rs binary (build.rs links ./libwg/libwg.a)
RUN cd libwg/wireguard-go \
    && CGO_ENABLED=1 go build -trimpath -buildmode=c-archive -o libwg.a ./libwg \
    && mv libwg.a libwg.h ../ \
    && cd /src \
    && cargo build --release \
    && strip target/release/corplink-rs

# ---- runtime ----------------------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/target/release/corplink-rs /usr/local/bin/corplink-rs

# config.json (and the generated *_cookies.json) live here; mount a volume.
WORKDIR /data
VOLUME ["/data"]

# SOCKS5 / netstack mode needs no TUN device and no privileges, so the
# container runs as an unprivileged user and only needs the proxy port.
RUN useradd -u 10001 -d /data corplink && chown corplink /data
USER corplink

ENV RUST_LOG=info
EXPOSE 1080

ENTRYPOINT ["corplink-rs"]
CMD ["/data/config.json"]
