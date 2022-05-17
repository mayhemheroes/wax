# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gcc

ADD . /wax
WORKDIR /wax
RUN gcc ./src/waxc.c -o waxc
