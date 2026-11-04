#!/bin/sh
# Smoke test, run inside the built image by scripts/build.sh --test: every tool the CI relies on
# is present, and a crate with a C dependency cross-compiles to a static binary for each target
# that runs (under qemu for ARM).
set -eu
for tool in rustc cargo cargo-clippy rustfmt gcc arm-linux-gnueabihf-gcc aarch64-linux-gnu-gcc \
            qemu-arm-static qemu-aarch64-static readelf file node git zstd python3 jq; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
rustc --version; node --version

work=$(mktemp -d); cd "$work"
cargo new --quiet smoke && cd smoke
# A build-script C compile stands in for ring: proves CC_<target> and the cross gcc work.
cat >> Cargo.toml <<'TOML'
[build-dependencies]
cc = "1"
TOML
printf 'int smoke_add(int a, int b) { return a + b; }\n' > smoke.c
printf 'fn main() { cc::Build::new().file("smoke.c").compile("smoke"); }\n' > build.rs
cat > src/main.rs <<'RS'
unsafe extern "C" { fn smoke_add(a: i32, b: i32) -> i32; }
fn main() { println!("smoke {} {}", std::env::consts::ARCH, unsafe { smoke_add(40, 2) }); }
RS
for t in x86_64-unknown-linux-musl armv7-unknown-linux-musleabihf aarch64-unknown-linux-musl; do
  cargo build --quiet --release --target "$t"
  bin="target/$t/release/smoke"
  desc=$(file -b "$bin"); echo "$t: $desc"
  echo "$desc" | grep -Eq 'statically linked|static-pie linked' || { echo "not static: $t" >&2; exit 1; }
  case "$t" in
    x86_64*)  out=$("$bin") ;;
    armv7*)   out=$(qemu-arm-static "$bin") ;;
    aarch64*) out=$(qemu-aarch64-static "$bin") ;;
  esac
  echo "  -> $out"; echo "$out" | grep -q ' 42$'
done
echo "rust-cross smoke test passed"
