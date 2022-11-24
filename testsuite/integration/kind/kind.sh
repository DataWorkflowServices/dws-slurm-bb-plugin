#!/usr/bin/env bash

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

generate_cluster () {
  set -e

  CONFIG=$(dirname $0)/kind-config.yaml
  # Only write the config if it's not present.
  if ! [[ -f $CONFIG ]]
  then
    # System Local Controllers (SLC)
    SLCCONFIG=$(cat << EOF

    kubeadmConfigPatches:
    - |
      kind: JoinConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: cray.wlm.manager=true
EOF
  )

  cat > $CONFIG <<EOF
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  name: dws
  nodes:
  - role: control-plane
  - role: worker $SLCCONFIG
EOF
  fi

  # Create a KIND cluster to run DWS operator.
  kind create cluster --wait 60s --image=kindest/node:v1.25.2 --config $CONFIG
}

install_dependencies () {
  set -e

  # Make sure the current context is set to dws
  kubectl config use-context kind-dws

  # Install the cert-manager for the DWS webhook.
  kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.7.0/cert-manager.yaml

  kubectl wait deployment -n cert-manager cert-manager --for condition=Available=True
  kubectl wait deployment -n cert-manager cert-manager-cainjector --for condition=Available=True
  kubectl wait deployment -n cert-manager cert-manager-webhook --for condition=Available=True
}

prep_kubeconfig () {
  set -e
  cp ~/.kube/config kubeconfig
  yq -i e '(.clusters | map(select(.name=="kind-dws")))[0].cluster.server |= "https://dws-control-plane:6443"' kubeconfig
  yq -i e '.current-context |= "kind-dws"' kubeconfig
  chmod a+r kubeconfig
}

teardown () {
  rm kubeconfig
  rm kind-config.yaml
  kind delete cluster --name=dws
}