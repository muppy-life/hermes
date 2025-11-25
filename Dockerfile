# Build stage
# Multi-platform support: automatically selects correct architecture (amd64/arm64)
FROM hexpm/elixir:1.15.7-erlang-26.1.2-alpine-3.18.4 AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Set build ENV
ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create app directory
WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application files
COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets
RUN mix assets.build

# Compile the release
RUN mix compile

# Generate release
COPY config/runtime.exs config/
RUN mix release

# Runtime stage
FROM alpine:3.18.4 AS app

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs curl

# Create app user
RUN addgroup -g 1000 hermes && \
    adduser -D -u 1000 -G hermes hermes

# Create app directory
WORKDIR /app

# Copy the release from build stage
COPY --from=build --chown=hermes:hermes /app/_build/prod/rel/hermes ./

# Set user
USER hermes

# Expose port
EXPOSE 4000

# Set environment variables
ENV MIX_ENV=prod \
    PORT=4000 \
    LANG=C.UTF-8

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

# Start the application
CMD ["/app/bin/hermes", "start"]
