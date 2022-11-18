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

SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

SKIP_KIND_GENERATION?=""

.PHONY: setup
setup:
	@{ \
		set -e ; \
		source kind/kind.sh ; \
		test ! -z "$(SKIP_KIND_GENERATION)" && echo "Skipping cluster generation" || generate_cluster ; \
		install_dependencies ; \
		prep_kubeconfig ; \
	}
	cd ../submodules/dws && make docker-build kind-push deploy
	cd slurm && docker compose up --build --wait
	docker network connect slurm_default dws-control-plane


.PHONY: test
test: setup

.PHONY: clean
clean:
	docker network disconnect slurm_default dws-control-plane || echo "Docker network cleanup failed"
	cd slurm && docker compose down || echo "Slurm cleanup failed"
	source kind/kind.sh && teardown || echo "Kind cleanup failed"

all: setup test clean