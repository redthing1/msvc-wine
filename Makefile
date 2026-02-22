DOCKER ?= docker
DIST ?= dist

.PHONY: trim-x64 trim-multi buildtools-trim-x64 buildtools-trim-multi buildtools-trim zst

trim-x64:
	$(DOCKER) build -f docker/msvc.docker -t msvc-wine:trim-x64 --build-arg MSVC_TRIM=yes --build-arg MSVC_ARCHS="x64" .

trim-multi:
	$(DOCKER) build -f docker/msvc.docker -t msvc-wine:trim-multi --build-arg MSVC_TRIM=yes --build-arg MSVC_ARCHS="x86 x64 arm arm64" .

buildtools-trim-x64: trim-x64
	$(DOCKER) build -f docker/msvc.buildtools.docker -t msvc-wine:buildtools-trim-x64 --build-arg BASE=msvc-wine:trim-x64 .

buildtools-trim-multi: trim-multi
	$(DOCKER) build -f docker/msvc.buildtools.docker -t msvc-wine:buildtools-trim-multi --build-arg BASE=msvc-wine:trim-multi .

buildtools-trim: buildtools-trim-x64 buildtools-trim-multi

zst: buildtools-trim
	@test -n "$(VERSION)" || (echo "usage: make zst VERSION=vx.x.x" && exit 1)
	mkdir -p "$(DIST)"
	$(DOCKER) save msvc-wine:buildtools-trim-x64 | zstd -10 -T0 -o "$(DIST)/msvc-wine_$(VERSION)_buildtools-trim-x64.tar.zst"
	$(DOCKER) save msvc-wine:buildtools-trim-multi | zstd -10 -T0 -o "$(DIST)/msvc-wine_$(VERSION)_buildtools-trim-multi.tar.zst"
