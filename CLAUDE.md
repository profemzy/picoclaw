# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PicoClaw is an ultra-lightweight personal AI assistant framework written in Go, designed to run on minimal hardware (<10MB RAM). It's an autonomous agent that connects to multiple LLM providers and chat platforms.

## Build & Development Commands

```bash
make build          # Build for current platform (output in build/)
make test           # Run all tests (go test ./...)
make lint           # Run golangci-lint (v2 config)
make fmt            # Format code via golangci-lint formatters
make vet            # Run go vet
make check          # Run deps + fmt + vet + test
make deps           # Download and verify dependencies
make generate       # Run go generate (required before build)
make install        # Build and install to ~/.local/bin
```

Run a single test: `go test ./pkg/agent/ -run TestName`

Build requires the `stdjson` build tag (included in Makefile's `GOFLAGS`).

## Architecture

### Entry Point & Commands
`cmd/picoclaw/main.go` dispatches CLI subcommands: `agent` (interactive chat), `gateway` (long-running bot service), `onboard` (setup wizard), `status`, `migrate`, `auth`, `cron`, `skills`.

### Core Packages (under `pkg/`)

- **agent** — Central execution engine. `loop.go` orchestrates the agent loop: receives messages via the event bus, calls LLM providers, executes tools, and routes responses back. `registry.go` manages multiple named agents. `instance.go` encapsulates per-agent config, workspace, and session.
- **providers** — LLM provider abstraction. `types.go` defines the `LLMProvider` interface (`Chat` method). `factory.go` creates providers from config. `fallback.go` implements automatic failover chains between models. Supports OpenAI-compatible, Anthropic, Gemini, DeepSeek, Zhipu, Ollama, and many more.
- **channels** — Chat platform integrations (Telegram, Discord, Slack, DingTalk, Feishu/Lark, WeChat Work, LINE, QQ, OneBot). `manager.go` coordinates channel lifecycle.
- **tools** — Extensible tool registry. `Tool` interface requires `Name()`, `Description()`, `Parameters()`, `Execute()`. Optional `ContextualTool` and `AsyncTool` interfaces. Built-in tools: file ops, shell exec, web search/fetch, message, spawn (subagents), cron, skills.
- **config** — JSON config with env var overrides (`PICOCLAW_*`). Model references use `vendor/model` format (e.g., `anthropic/claude-sonnet-4.6`, `ollama/llama3`).
- **skills** — Custom skill discovery, installation from ClawHub registry, and per-agent filtering.
- **bus** — Event message bus (pub/sub) connecting channels to agents.
- **session** — Conversation history persistence.
- **heartbeat** — Periodic background task execution using HEARTBEAT.md prompts.

### Key Interfaces
- `LLMProvider` — All LLM backends implement this (Chat method with messages, tools, model, options).
- `Tool` — All agent tools implement this. Register via the tool registry.
- Channel implementations are in `pkg/channels/` with per-platform files.

### Workspace Layout
Runtime data lives in `~/.picoclaw/workspace/` with `sessions/`, `memory/`, `state/`, `cron/`, `skills/`, and markdown files (AGENTS.md, IDENTITY.md, SOUL.md, TOOLS.md, etc.).

## Code Style & Conventions

- **Line length**: 120 characters max (enforced by golines)
- **Formatting**: gofmt, gofumpt, goimports, golines, gci (imports: standard → third-party → local module)
- **Rewrite rules**: Use `any` instead of `interface{}`, use `a[b:]` instead of `a[b:len(a)]`
- **Testing**: Uses `stretchr/testify` for assertions. Tests use `os.MkdirTemp` for fixtures.
- **Concurrency**: `sync.Map` for concurrent maps, `context.Context` propagation throughout.
- **Error handling**: Errors classified as retriable vs non-retriable for provider fallback logic.

## CI Pipeline

PR checks run two jobs: (1) `golangci-lint run` and (2) `go test ./...`. Both run `go generate ./...` first. Push to main runs `make build-all`.
