FROM golang:1.19-alpine AS gobase
FROM ghcr.io/lunarmodules/busted:master as unitbase

RUN apk add --no-cache make=4.3-r0 bash=5.1.16-r0 && \
    apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
    --no-cache python3=3.10.8-r0 && python -m ensurepip --upgrade && \
    pip3 install --no-cache-dir openapi-schema-validator==0.3.4 pyyaml==6.0

COPY testsuite/submodules/dws /dws
COPY --from=gobase /usr/local/go/ /usr/local/go/

WORKDIR /dws
RUN export PATH="$PATH:/usr/local/go/bin" && \
    make manifests

FROM unitbase as unittest

WORKDIR /
COPY testsuite/unit/bin/validate validate
COPY src/burst_buffer/burst_buffer.lua /burst_buffer.lua
COPY testsuite/unit/burst_buffer/test.lua /test.lua

RUN busted /test.lua