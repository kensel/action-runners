# syntax=docker/dockerfile:1
# Job container for Rust builds that cross-compile static musl binaries for x86_64, armv7 and
# aarch64 (filecat-agent). Everything the CI used to install on every run is baked in:
# the pinned Rust toolchain + musl targets + clippy, the ARM GNU cross gcc (ring compiles C and
# gcc is the linker driver), qemu-user-static for the ARM tests, readelf/file for artefact checks,
# and Node (GitHub mounts its own; Gitea act_runner runs JS actions with the container's node).
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG RUST_VERSION=1.98.0
ARG RUST_TARGETS="x86_64-unknown-linux-musl armv7-unknown-linux-musleabihf aarch64-unknown-linux-musl"
ARG RUST_COMPONENTS="clippy rustfmt"
ARG NODE_MAJOR=24

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/node/bin:$PATH \
    CARGO_TERM_COLOR=always \
    CARGO_INCREMENTAL=0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git git-lfs openssh-client jq unzip xz-utils zstd tar gzip \
      build-essential pkg-config file binutils python3 sudo \
      gcc-arm-linux-gnueabihf gcc-aarch64-linux-gnu \
      qemu-user-static \
 && rm -rf /var/lib/apt/lists/*

# Node: latest release of the major line, checksum-verified against nodejs.org's SHASUMS256.
RUN set -eu; \
    base="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"; \
    curl -fsSL "$base/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    tarball=$(awk '/linux-x64\.tar\.xz$/ { print $2 }' /tmp/SHASUMS256.txt); \
    curl -fsSL "$base/$tarball" -o "/tmp/$tarball"; \
    (cd /tmp && grep " $tarball\$" SHASUMS256.txt | sha256sum -c -); \
    mkdir -p /usr/local/node; \
    tar -xJf "/tmp/$tarball" -C /usr/local/node --strip-components=1; \
    rm -f /tmp/*.tar.xz /tmp/SHASUMS256.txt; \
    node --version

# Rust: pinned toolchain, minimal profile, targets and components preinstalled.
RUN set -eu; \
    curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
      --default-toolchain "$RUST_VERSION" \
      $(for c in $RUST_COMPONENTS; do printf -- '-c %s ' "$c"; done) \
      $(for t in $RUST_TARGETS; do printf -- '-t %s ' "$t"; done); \
    rm /tmp/rustup-init.sh; \
    chmod -R a+rwX "$RUSTUP_HOME" "$CARGO_HOME"; \
    rustc --version; cargo --version

# Default cross linkers so plain `cargo build --target ...` works without a project build script.
# (filecat's agent/build.sh sets the same values itself.)
COPY cargo-config.toml /usr/local/cargo/config.toml

# Runs as root (the GitHub/Gitea job-container default); `sudo` is present so steps written for the
# hosted ubuntu runner (`sudo apt-get ...`) still work unchanged.
LABEL org.opencontainers.image.source="https://github.com/kensel/action-runners" \
      org.opencontainers.image.description="CI job container: Rust ${RUST_VERSION} + musl cross (x86_64, armv7, aarch64) + qemu"
