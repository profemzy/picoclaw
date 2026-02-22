# ============================================================
# Stage 1: Build the picoclaw binary
# ============================================================
FROM golang:1.26.0-alpine AS builder

RUN apk add --no-cache git make

WORKDIR /src

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN make build

# ============================================================
# Stage 2: Minimal runtime image
# ============================================================
FROM alpine:3.23

RUN apk add --no-cache ca-certificates tzdata curl jq bash

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:18790/health || exit 1

# Copy binary
COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw

# Create non-root user and group
RUN addgroup -g 1000 picoclaw && \
    adduser -D -u 1000 -G picoclaw picoclaw

# Switch to non-root user
USER picoclaw

# Run onboard to create initial directories and config
RUN /usr/local/bin/picoclaw onboard

# Copy Oluto skill into container (scripts, references, assets)
COPY --chown=picoclaw:picoclaw deploy/skills/oluto/ /home/picoclaw/.picoclaw/skills/oluto/
RUN chmod +x /home/picoclaw/.picoclaw/skills/oluto/scripts/*.sh

# Symlink skills into workspace so read_file tool can access SKILL.md and references
RUN ln -s /home/picoclaw/.picoclaw/skills /home/picoclaw/.picoclaw/workspace/skills

ENTRYPOINT ["picoclaw"]
CMD ["gateway"]
