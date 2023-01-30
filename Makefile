#
# Copyright 2022 Hewlett Packard Enterprise Development LP
# Other additional copyright holders may be indicated within.
#
# The entirety of this work is licensed under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
#
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#NOCACHE= --no-cache
#PROGRESS= --progress plain

test: $(find src -type f) $(find testsuite/unit/src -type f) Dockerfile
	docker buildx build $(NOCACHE) $(PROGRESS) --target test -t test .

OUTPUT_HANDLER = --output TAP
TAG ?=  # specify a string like TAG="-t mytag"
test-no-docker:
	busted $(TAG) $(OUTPUT_HANDLER) testsuite/unit/src/burst_buffer/dws-test.lua

integration-test: $(find testsuite/integration/src -type f) testsuite/integration/Dockerfile
	cd testsuite/integration && make setup test clean
