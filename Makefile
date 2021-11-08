REGISTRY ?= ghcr.io
USERNAME ?= hainesbg
SHA ?= $(shell git describe --match=none --always --abbrev=8 --dirty)
TAG ?= $(shell git describe --tag --always --dirty)
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
REGISTRY_AND_USERNAME := $(REGISTRY)/$(USERNAME)

# Sync bldr image with Pkgfile
BLDR ?= docker run --rm --volume $(PWD):/tools --entrypoint=/bldr \
	ghcr.io/hainesbg/bldr:v0.2.0-alpha.6-2-ge999d96-frontend graph --root=/tools

BUILD := docker buildx build
PLATFORM ?= linux/amd64
PROGRESS ?= auto
PUSH ?= true
DEST ?= _out
COMMON_ARGS := --file=Pkgfile
COMMON_ARGS += --progress=$(PROGRESS)
COMMON_ARGS += --platform=$(PLATFORM)

TARGETS = tools

all: $(TARGETS) ## Builds all known pkgs.

.PHONY: help
help: ## This help menu.
	@grep -E '^[a-zA-Z0-9\.%_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

target-%: ## Builds the specified target defined in the Pkgfile. The build result will only remain in the build cache.
	@$(BUILD) \
		--target=$* \
		$(COMMON_ARGS) \
		$(TARGET_ARGS) .

local-%: ## Builds the specified target defined in the Pkgfile using the local output type. The build result will be output to the specified local destination.
	@$(MAKE) target-$* TARGET_ARGS="--output=type=local,dest=$(DEST) $(TARGET_ARGS)"

rebuild-%: ## Builds the specified target twice into $(DEST)/build-1/2 and compares results.
	@rm -fr $(DEST)/build-1 $(DEST)/build-2 $(DEST)/build-1.txt $(DEST)/build-2.txt
	@$(MAKE) target-$* PROGRESS=plain TARGET_ARGS="--output=type=local,dest=$(DEST)/build-1 $(TARGET_ARGS)" 2>&1 | tee $(DEST)/build-1.txt
	@docker buildx rm reproducer || true
	@docker buildx create --driver docker-container --driver-opt network=host --name reproducer
	@$(MAKE) target-$* PROGRESS=plain TARGET_ARGS="--output=type=local,dest=$(DEST)/build-2 --builder=reproducer $(TARGET_ARGS)" 2>&1 | tee $(DEST)/build-2.txt
	@docker buildx rm reproducer
	@find _out/ -exec touch -ch -t 202108110000 {} \;
	@diffoscope _out/build-1 _out/build-2

docker-%: ## Builds the specified target defined in the Pkgfile using the docker output type. The build result will be loaded into Docker.
	@$(MAKE) target-$* TARGET_ARGS="$(TARGET_ARGS)"

.PHONY: $(TARGETS)
$(TARGETS):
	@$(MAKE) docker-$@ TARGET_ARGS="--tag=$(REGISTRY_AND_USERNAME)/$@:$(TAG) --push=$(PUSH)"

.PHONY: deps.png
deps.png: ## Regenerate deps.png.
	@$(BLDR) graph | dot -Tpng > deps.png
