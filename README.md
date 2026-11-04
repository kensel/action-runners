# action-runners

Prebuilt CI **job-container images** for GitHub Actions and Gitea Actions, published to Docker Hub
as tags of a single repository: **`kensel/action-runners`**.

Jobs start with their toolchains already installed, so CI time goes to building and testing.

## Images

| Image (`images/<name>`) | Pin this tag | Contents |
|---|---|---|
| `rust-cross` | `kensel/action-runners:rust-cross-1.98.0` | Ubuntu 26.04 (same release as the `ubuntu-26.04` hosted runner), Rust 1.98.0 (clippy, rustfmt) with musl targets x86_64 / armv7 / aarch64, `gcc-arm-linux-gnueabihf` + `gcc-aarch64-linux-gnu`, `qemu-user` (with `qemu-*-static` names), `file`/`readelf`, Python 3, Node 26 LTS, git, jq, zstd, sudo |

Each image is published under three tags:

| Tag | Meaning |
|---|---|
| `<name>-<TAG>` | e.g. `rust-cross-1.98.0`; pin this one in workflows |
| `<name>-<TAG>-<sha7>` | an immutable build from one commit of this repo |
| `<name>` | the newest build of that image (a moving tag) |

`TAG` comes from `images/<name>/image.env`.

## Layout

```
images/
  rust-cross/
    Dockerfile          the image
    image.env           TAG, PLATFORMS, and build args (Rust version, targets, Node major, base image)
    cargo-config.toml   default cross linkers and qemu runners for the musl targets
    test.sh             smoke test that runs inside the built image (cross-compiles C+Rust, runs it under qemu)
scripts/
  build.sh              build / --test / --push one or more images (used by CI and locally)
.github/workflows/build-images.yml   GitHub Actions: on a v* tag, build + test + push every image
.gitea/workflows/build-images.yml    Gitea Actions: same thing
examples/filecat-agent-jobs.yml      how filecat's Rust jobs switch over to the image
```

## Using an image in a workflow

```yaml
jobs:
  agent:
    runs-on: ubuntu-latest
    container: kensel/action-runners:rust-cross-1.98.0
    steps:
      - uses: actions/checkout@v5
      - uses: Swatinem/rust-cache@v2     # still worth keeping: it caches crates and target/
      - run: ./build.sh all
```

Remove the `dtolnay/rust-toolchain` and `apt-get install gcc-*-cross / qemu-user-static` steps.
[examples/filecat-agent-jobs.yml](examples/filecat-agent-jobs.yml) shows the full change for filecat.

On **Gitea**, the same `container:` line works. You can also map a runner label straight to the
image in act_runner's `config.yaml` (`"rust-cross:docker://kensel/action-runners:rust-cross-1.98.0"`)
and use `runs-on: rust-cross`. A self-hosted runner pulls the image once and keeps it locally.

## Publishing

CI runs only when you push a `v*` tag. It builds, smoke-tests and pushes every image; commits and
pull requests run nothing.

```bash
git tag v2026.11.0 && git push origin v2026.11.0
```

One-time setup on GitHub: the `dockerhub` environment (Settings → Environments) holds the
credentials, and only `v*` tags may deploy to it.

| Name | Kind | Value |
|---|---|---|
| `DOCKERHUB_USERNAME` | environment variable | `kensel` |
| `DOCKERHUB_TOKEN` | environment secret | a Docker Hub access token with Read & Write scope |

```bash
gh secret set DOCKERHUB_TOKEN --env dockerhub --repo kensel/action-runners
```

The tag name is just the trigger. The published tags come from `TAG` in each `image.env`, so
pushing a new git tag without changing `TAG` rebuilds the image (picking up base-image security
fixes) and overwrites `rust-cross-<TAG>` with that build. The `-<sha>` tag from each build is never
overwritten.

On Gitea, the runner needs the Docker socket mounted into job containers; the comments at the top of
[.gitea/workflows/build-images.yml](.gitea/workflows/build-images.yml) show how. If the repo is
mirrored to both forges, set the variable `PUSH_IMAGES=false` on the Gitea side so only one of them
pushes.

### Locally

```bash
scripts/build.sh --test rust-cross
```

```bash
docker login && scripts/build.sh --test --push rust-cross
```

## Bumping Rust

1. In `images/rust-cross/image.env`, set `RUST_VERSION` and `TAG` to the new version.
2. Commit, then push a new `v*` tag. CI publishes `rust-cross-<new>`.
3. In the projects that use the image, change `container: kensel/action-runners:rust-cross-<new>`.

The old tag stays published, so projects can move to the new one whenever they are ready.

## Adding an image

Create `images/<name>/` with a `Dockerfile` and an `image.env` that has at least `TAG=`. Add a
`test.sh` if you want a smoke test. The next `v*` tag builds it along with the others.

Job-container images should run as root, the GitHub/Gitea default. Install `node` if JS actions
will run on Gitea: act_runner uses the container's node, while GitHub mounts its own.
