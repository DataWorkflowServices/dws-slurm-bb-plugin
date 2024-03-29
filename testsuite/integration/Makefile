#
# Copyright 2022-2024 Hewlett Packard Enterprise Development LP
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
		docker buildx build -t local/dws:test --load . ; \
		IMAGE_TAG_BASE=local/dws VERSION=test KIND_CLUSTER=dws make kind-push deploy ; \
		kubectl wait deployment --timeout=120s -n dws-system dws-controller-manager --for condition=Available=True ; \
		kubectl wait deployment --timeout=120s -n dws-system dws-webhook --for condition=Available=True ; \
	}

.PHONY: setup-dws-test-driver
setup-dws-test-driver:
	@{\
		set -e ; \
		cd ../submodules/dws-test-driver ; \
		docker buildx build -t ghcr.io/dataworkflowservices/dws-test-driver:local-test --load . ; \
		VERSION=local-test KIND_CLUSTER=dws make kind-push deploy ; \
		kubectl wait deployment --timeout=60s -n dws-test-system dws-test-driver-controller-manager --for condition=Available=True ; \
	}

.PHONY: setup
setup: setup-kind setup-dws setup-dws-test-driver

.PHONY: test
test:
	docker compose build
	docker compose up

.PHONY: debug
debug:
	echo "***** SLURMCTLD LOGS *****"
	docker logs slurmctld
	echo
	echo "***** SLURM COMPUTE LOGS *****"
	docker logs c1
	echo
	echo "***** KIND NODE *****"
	kubectl describe node dws-control-plane dws-worker
	echo
	echo "***** DWS DEPLOYMENT *****"
	kubectl describe deployment -n dws-system dws-controller-manager
	echo
	echo "***** DWS LOGS *****"
	kubectl logs -n dws-system deployment/dws-controller-manager
	
.PHONY: reports
reports:
	mkdir reports
	docker cp -a integration-test:/reports/ .

.PHONY: clean
clean: clean-tests
	docker compose down || echo "Integration test container cleanup failed"
	docker network disconnect slurm_default dws-control-plane || echo "Docker network cleanup failed"
	cd slurm && docker compose down --volumes || echo "Slurm cleanup failed"
	source kind/kind.sh && teardown || echo "Kind cleanup failed"

.PHONY: clean-tests
clean-tests:
	rm -rf src/.pytest_cache src/tests/__pycache__ src/tests/dws_bb_plugin/__pycache__ src/tests/environment/__pycache__ src/tests/a-environment/__pycache__ src/tests/b-dws-bb-plugin/__pycache__

all: setup test
