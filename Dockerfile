FROM golang:1.19-alpine AS dwsbase

RUN apk add --no-cache make=4.3-r0 bash=5.1.16-r2

COPY testsuite/submodules/dws /dws
WORKDIR /dws
RUN make manifests

FROM ghcr.io/lunarmodules/busted:v2 AS testbase

RUN apk add --no-cache make=4.3-r0 bash=5.1.16-r0 git=2.34.5-r0 && \
    apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
    --no-cache python3=3.10.8-r1 && python -m ensurepip --upgrade && \
    pip3 install --no-cache-dir openapi-schema-validator==0.3.4 pyyaml==6.0 && \
    luarocks install luacov && luarocks install luacov-multiple && luarocks install luacov-html

COPY --from=dwsbase /dws /dws

FROM testbase AS test

WORKDIR /
COPY testsuite/unit/bin /bin
COPY testsuite/unit/luacov.lua /.luacov
COPY src/burst_buffer/burst_buffer.lua /
COPY testsuite/unit/burst_buffer/test.lua /

RUN busted -o junit -Xoutput junit.xml --coverage test.lua && \
    mv luacov-html coverage.html && \
    tar -czvf coverage.html.tar.gz /coverage.html

FROM scratch AS testartifacts

ARG testExecutionFile="unittest.junit.xml"
ARG testCoverageFile="coverage.cobertura.xml"
ARG testCoverageReport="coverage.html.tar.gz"

COPY --from=test junit.xml /$testExecutionFile
COPY --from=test cobertura.xml /$testCoverageFile
COPY --from=test coverage.html.tar.gz /$testCoverageReport