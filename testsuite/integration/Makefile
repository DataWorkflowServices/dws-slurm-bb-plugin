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

.PHONY: setup-kind
setup-kind:
	@{ \
		set -e ; \
		source kind/kind.sh ; \
		test ! -z "$(SKIP_KIND_GENERATION)" && echo "Skipping cluster generation" || generate_cluster ; \
		install_dependencies ; \
		prep_kubeconfig ; \
	}
	cd slurm && docker compose build && docker compose up --wait
	docker network connect slurm_default dws-control-plane

.PHONY: setup-dws
setup-dws:
	@{\
		set -e ; \
		cd ../submodules/dws ; \
		docker buildx build -t local/dws-operator:test --cache-from="/tmp/.buildx-cache" --load . ; \
		IMAGE_TAG_BASE=local/dws-operator VERSION=test KIND_CLUSTER=dws make kind-push deploy ; \
		kubectl wait deployment --timeout=60s -n dws-operator-system dws-operator-controller-manager --for condition=Available=True ; \
	}

.PHONY: setup
setup: setup-kind setup-dws

.PHONY: test
test:
	docker compose build
	docker compose up

.PHONY: reports
reports:
	mkdir reports
	docker cp -a integration-test:/reports/ .

.PHONY: clean
clean:
	docker compose down || echo "Integration test container cleanup failed"
	docker network disconnect slurm_default dws-control-plane || echo "Docker network cleanup failed"
	cd slurm && docker compose down || echo "Slurm cleanup failed"
	source kind/kind.sh && teardown || echo "Kind cleanup failed"

all: setup test