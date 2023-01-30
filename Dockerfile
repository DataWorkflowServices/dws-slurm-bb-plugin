FROM ghcr.io/lunarmodules/busted:v2 AS testbase

RUN apk add --no-cache make bash git python3 && \
    python3 -m ensurepip --upgrade && \
    pip3 install --no-cache-dir openapi-schema-validator==0.3.4 pyyaml==6.0 && \
    luarocks install luacov && luarocks install luacov-multiple && luarocks install luacov-html

COPY testsuite/submodules/dws /dws

FROM testbase AS testrun

WORKDIR /
COPY testsuite/unit/luacov.lua /.luacov
COPY testsuite/unit/output.lua /output.lua
COPY src /
COPY testsuite/unit/src/burst_buffer/dws-test.lua /

RUN busted -o output.lua -Xoutput junit.xml --verbose --coverage *test.lua || \
    touch testsFailed.indicator

FROM scratch AS testresults

ARG testExecutionFile="unittest.junit.xml"
COPY --from=testrun junit.xml /$testExecutionFile

FROM testrun AS packageresults

RUN mv luacov-html coverage.html && \
    tar -czvf coverage.html.tar.gz /coverage.html

FROM testresults AS testartifacts

ARG testCoverageFile="coverage.cobertura.xml"
ARG testCoverageReport="coverage.html.tar.gz"
COPY --from=testrun cobertura.xml /$testCoverageFile
COPY --from=packageresults coverage.html.tar.gz /$testCoverageReport

FROM testrun AS test

RUN test ! -f testsFailed.indicator
