# msvc-wine

msvc + windows sdk for linux (wine), as docker images

## what

- docker image with the toolchain at `/opt/msvc`
- wrappers for `PATH` (`cl`, `link`, etc) inside the container
- optional `buildtools` layer (cmake/ninja/clang/python/uv/sccache)
- trimming support (`scripts/trim-msvc.sh`) to keep images small

## quick start

build a trimmed buildtools image:
```bash
# trimmed base toolchain
docker build -f docker/msvc.docker -t msvc-wine:trim --build-arg MSVC_TRIM=yes .
# buildtools layer
docker build -f docker/msvc.buildtools.docker -t msvc-wine:buildtools-trim --build-arg BASE=msvc-wine:trim .
```

interactive shell (mount current dir at `/work`):
```bash
docker run --rm -it -v "$PWD:/work" -w /work msvc-wine:buildtools-trim /bin/bash
```

inside the container:
```bash
cl /?
```

## use with cmake

simple pattern (ninja + release):

```bash
cmake -S . -B build -G Ninja -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl && cmake --build build
```

if you hit pdb/winbind issues in debug-like builds, either enable winbind (`--build-arg WITH_WINBIND=yes`) or prefer release builds.

## tuning

dockerfiles accept the following args:

- `MSVC_ARCHS` (default: `x64`) — targets to include (`"x86 x64 arm arm64"`)
- `HOST_ARCH` (default: `x64`) — host arch for tools
- `ONLY_HOST` (default: `yes`) — download only host-arch packages
- `MSVC_VERSION`, `SDK_VERSION` — pin toolset / sdk versions (optional)
- `WITH_WINBIND` (default: `no`) — install winbind in the runtime image
- `DEBIAN_VERSION`, `DEBIAN_FLAVOR` (defaults: `trixie` + `slim`)
- `MSVC_TRIM` (default: `no`) — enable trimming (recommended: `yes`)
- `MSVC_TRIM_FLAGS` (default: `--only-sdk-version --trim-optional`) — passed to `scripts/trim-msvc.sh`

example: keep multiple target archs:
```bash
docker build -f docker/msvc.docker -t msvc-wine:trim-multiarch --build-arg MSVC_TRIM=yes --build-arg MSVC_ARCHS="x86 x64 arm arm64" .
```

## import/export images

export:
```bash
docker save msvc-wine:buildtools-trim | zstd -10 -T0 -o msvc-wine_buildtools_trim.zst
```

import:
```bash
zstd -d -c msvc-wine_buildtools_trim.zst | docker load
```

## validation

sanity checks:
```bash
docker build -f docker/msvc.hello.docker -t msvc-wine:hello --build-arg BASE=msvc-wine:trim .
docker build -f docker/msvc.clang.docker -t msvc-wine:clang --build-arg BASE=msvc-wine:trim .
```

full test run:
```bash
docker build -f docker/msvc.test.docker -t msvc-wine:test --build-arg BASE=msvc-wine:trim .
```
