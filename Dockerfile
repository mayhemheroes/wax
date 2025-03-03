# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gcc

ADD . /wax
WORKDIR /wax
RUN gcc ./src/waxc.c -o waxc

RUN mkdir -p /deps
RUN ldd /wax/waxc | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /wax/waxc /wax/waxc
ENV LD_LIBRARY_PATH=/deps
