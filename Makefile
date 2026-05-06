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

.PHONY: all build test format lint clean notes help
all: build

build: ## Build the native project if present; otherwise no-op.
	cd app && mix compile --warnings-as-errors

test: ## Run the Elixir test suite.
	cd app && mix test

format: ## Format Elixir source and tests.
	cd app && mix format

lint: ## Run warning-as-error compilation as the repository lint gate.
	cd app && mix compile --warnings-as-errors

clean: ## Remove generated output files.
	rm -rf "$(CLEAN_DIR)"
	rm -rf app/_build app/cover app/histlog

notes: ## Print the notes directory path.
	@printf "Notes directory: notes\n"

help: ## Show available targets.
	@printf "Available targets:\n  build test format lint clean notes\n"
