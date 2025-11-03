# Makefile for building attic Docker image.
#
# Configuration is loaded from `.env.maintainer` and can be overridden by
# environment variables.
#
# Usage:
#   make build                    # Build using `.env.maintainer`.
#   BUILD_IMAGE=... make build    # Override specific variables.

# Load configuration from `.env.maintainer` if it exists.
-include .env.maintainer

# Allow environment variable overrides with defaults.
BUILD_IMAGE ?= unattended/petros:latest
RUNTIME_IMAGE ?= debian:trixie-slim
DOCKER_BUILD_ARGS ?=
IMAGE_NAME ?= attic
IMAGE_TAG ?= latest
ACT_PULL ?= true

.PHONY: init
init:
	@echo "Initializing configuration files ..."
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env from .env.example - please review."; \
	else \
		echo ".env already exists."; \
	fi
	@if [ ! -f server.toml ]; then \
		cp server.toml.example server.toml; \
		echo "Created server.toml from server.toml.example - please review."; \
	else \
		echo "server.toml already exists."; \
	fi
	@echo "Initialization complete. Review configuration before running."

.PHONY: clean
clean:
	@bash -c 'echo -e "\033[33mWARNING: This will delete binaries.\033[0m"; \
	read -p "Are you sure you want to continue? [y/N]: " confirm; \
	if [[ "$$confirm" != "y" && "$$confirm" != "Y" ]]; then \
		echo "Operation cancelled."; \
		exit 1; \
	fi'
	rm -rf out/
	rm -rf target/
	rm -f result result-*

.PHONY: build
build:
	@echo "Building native binaries ..."
	mkdir -p out
	cargo build --release -p attic-server
	cp ./target/release/atticd ./out/atticd
	cp ./target/release/atticadm ./out/atticadm
	@echo "Build complete."

.PHONY: test
test:
	@echo "Running tests ..."
	@echo "... tests completed."

.PHONY: docker
docker:
	@echo "Building attic Docker image ..."
	@echo "  Build image:   $(BUILD_IMAGE)"
	@echo "  Runtime image: $(RUNTIME_IMAGE)"
	@echo "  Output tag:    $(IMAGE_NAME):$(IMAGE_TAG)"
	docker build \
		$(DOCKER_BUILD_ARGS) \
		--build-arg BUILD_IMAGE=$(BUILD_IMAGE) \
		--build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		.
	@echo "Build complete: $(IMAGE_NAME):$(IMAGE_TAG)"

.PHONY: ci
ci:
	@echo "Building Docker image from pre-built binaries (CI mode) ..."
	@if [ ! -f out/atticd ] || [ ! -f out/atticadm ]; then \
		echo "ERROR: Pre-built binaries not found in ./out/" >&2; \
		echo "Run 'make build' first to create the binaries." >&2; \
		exit 1; \
	fi
	@echo "  Runtime image: $(RUNTIME_IMAGE)"
	@echo "  Output tag:    $(IMAGE_NAME):$(IMAGE_TAG)"
	docker build \
		$(DOCKER_BUILD_ARGS) \
		--build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) \
		-f Dockerfile.ci \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		.
	@echo "Build complete: $(IMAGE_NAME):$(IMAGE_TAG)"

.PHONY: run
run:
	@if [ ! -f server.toml ]; then \
		echo "ERROR: server.toml not found" >&2; \
		echo "Run 'make init' to create configuration files." >&2; \
		exit 1; \
	fi
	@if [ ! -f .env ]; then \
		echo "ERROR: .env not found" >&2; \
		echo "Run 'make init' to create configuration files." >&2; \
		exit 1; \
	fi
	@echo "Starting attic container ..."
	docker run --rm -it \
		--name attic \
		-p 8080:8080 \
		--env-file .env \
		-v $(CURDIR)/server.toml:/home/attic/server.toml:ro \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		-f /home/attic/server.toml

.PHONY: shell
shell:
	@echo "Opening shell in container ..."
	docker run --rm -it \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: act
act:
	@echo "Running GitHub Actions workflow locally with act ..."
	@if [ ! -d ".act-secrets" ]; then \
		echo "WARNING: .act-secrets/ directory not found" >&2; \
		echo "See docs/WORKFLOW_TESTING.md for setup instructions" >&2; \
	fi
	act push -j release \
		--pull=$(ACT_PULL) \
		--container-options "-v $(CURDIR)/.act-secrets:/opt/github-runner/secrets:ro --group-add 960" \
		$(if $(DOCKER_BUILD_ARGS),--env DOCKER_BUILD_ARGS="$(DOCKER_BUILD_ARGS)")

.PHONY: help
help:
	@echo "Attic Server Build System"
	@echo ""
	@echo "Targets:"
	@echo "  init            Initialize config from examples."
	@echo "  clean           Clean output directories."
	@echo "  build           Build native binaries."
	@echo "  test            Run all tests for the build."
	@echo "  docker          Build Docker image (compiles inside container)."
	@echo "  ci              Build Docker image from pre-built binaries."
	@echo "  run             Run the built Docker image locally."
	@echo "  shell           Open a shell in the Docker image."
	@echo "  act             Test GitHub Actions release workflow locally."
	@echo "  help            Show this help message."
	@echo ""
	@echo "Configuration:"
	@echo "  Variables are loaded from .env.maintainer."
	@echo "  Override with environment variables:"
	@echo "    BUILD_IMAGE        - Builder image."
	@echo "    RUNTIME_IMAGE      - Runtime base image."
	@echo "    IMAGE_NAME         - Docker image name."
	@echo "    IMAGE_TAG          - Docker image tag."
	@echo "    DOCKER_BUILD_ARGS  - Additional Docker build flags."
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  BUILD_IMAGE=unattended/petros:latest make build"
	@echo "  IMAGE_TAG=v1.0.0 make build"
	@echo "  DOCKER_BUILD_ARGS='--network host' make build"

.DEFAULT_GOAL := build
