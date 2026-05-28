# Multi-stage build for either Slide Rust binary.
#   docker build --build-arg BIN=slide-api -t slide-api .
#   docker build --build-arg BIN=slide-sfu -t slide-sfu .
FROM rust:1.94-slim AS builder
ARG BIN=slide-api
WORKDIR /app

# Build deps. rustls is used throughout, so OpenSSL isn't required, but
# pkg-config + cmake cover transitive native build steps (webrtc).
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config cmake build-essential \
 && rm -rf /var/lib/apt/lists/*

COPY . .
RUN cargo build --release --bin ${BIN} \
 && cp target/release/${BIN} /app/server

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/server /usr/local/bin/server
ENV RUST_LOG=info
# slide-api: 8080, slide-sfu: 9000 (+ UDP media range for the SFU).
EXPOSE 8080 9000
CMD ["server"]
