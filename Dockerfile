# NOTE: use Google's "distroless with libgcc1" base image, see:
#       https://github.com/GoogleContainerTools/distroless/blob/6755e21ccd99ddead6edc8106ba03888cbeed41a/cc/README.md
ARG BASE_IMAGE_FINAL_STAGES="gcr.io/distroless/cc:nonroot"

FROM rust:1.97-bookworm AS builder

COPY --from=ghcr.io/casey/just:1.58.0 /just /usr/local/bin/

WORKDIR /usr/src/lidi
COPY . .
RUN just release

FROM ${BASE_IMAGE_FINAL_STAGES} AS send

COPY --from=builder --chown=root:root --chmod=755 /usr/src/lidi/target/release/lidi-send /usr/local/bin/
ENTRYPOINT ["lidi-send"]

FROM ${BASE_IMAGE_FINAL_STAGES} AS receive

COPY --from=builder --chown=root:root --chmod=755 /usr/src/lidi/target/release/lidi-receive /usr/local/bin/
ENTRYPOINT ["lidi-receive"]
