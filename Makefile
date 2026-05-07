# Makefile for workspace-native development and cleanup.
#
# This Makefile provides a normalized interface for native builds, cleanup,
# and notes-path discovery across language ecosystems.
#
# Usage:
#   make          # build the native project (if any)
#   make build    # compile using the native toolchain or no-op
#   make clean    # remove generated output
#   make notes    # show the notes directory path
#
CLEAN_DIR ?= dist
PREFIX ?= $(HOME)/.local
HISTLOG_BIN := $(CURDIR)/app/histlog

.PHONY: all build install test coverage format format-check lint ci release clean notes help
all: build

build: ## Compile histlog and build local launcher plus escript.
	cd app && mix compile --warnings-as-errors
	cd app && mix escript.build
	elixir scripts/write_launcher.exs

install: build ## Symlink the histlog escript under PREFIX/bin.
	mkdir -p "$(PREFIX)/bin"
	rm -f "$(PREFIX)/bin/histlog"
	ln -s "$(HISTLOG_BIN)" "$(PREFIX)/bin/histlog"

test: ## Run the Elixir test suite.
	cd app && mix test

coverage: ## Run the Elixir test suite with the built-in coverage summary.
	cd app && mix test --cover --exclude smoke_shell

format: ## Format Elixir source and tests.
	cd app && mix format

format-check: ## Check Elixir formatting without modifying files.
	cd app && mix format --check-formatted

lint: ## Run warning-as-error compilation as the repository lint gate.
	cd app && mix compile --warnings-as-errors

ci: format-check lint test build ## Run the local CI gate, including escript build.

release: ## Run the interactive release wizard. Pass VERSION=vX.Y.Z to select explicitly.
	@if [ -n "$(VERSION)" ]; then \
		VERSION="$(VERSION)" elixir scripts/release.exs; \
	else \
		elixir scripts/release.exs; \
	fi

clean: ## Remove generated output files.
	rm -rf "$(CLEAN_DIR)"
	rm -rf app/_build app/cover app/histlog app/histlog.escript

notes: ## Print the notes directory path.
	@printf "Notes directory: notes\n"

help: ## Show available targets.
	@printf "Available targets:\n  build install test coverage format format-check lint ci release clean notes\n"
