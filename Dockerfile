FROM --platform=linux/amd64 ubuntu:22.04 AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y gcc

ADD . /wax
WORKDIR /wax
RUN gcc ./src/waxc.c -o waxc

RUN mkdir -p /deps && \
    ldd /wax/waxc | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:22.04

COPY --from=builder /deps /deps
COPY --from=builder /wax/waxc /wax/waxc
ENV LD_LIBRARY_PATH=/deps
