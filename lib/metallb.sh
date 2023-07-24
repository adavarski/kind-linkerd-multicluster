#!/usr/bin/env bash

source "${BASH_SOURCE[0]%/*}"/logging.sh
source "${BASH_SOURCE[0]%/*}"/kind.sh


# Deploy MetalLB to the given cluster.
function metallb::deploy {
	local cluster_name=$1
	local l2pool_start=$2
	local l2pool_end=$((l2pool_start+9))

	local kind_subnet_prefix
	kind_subnet_prefix="$(kind::subnet | cut -d'.' -f1,2).255"

	kubectl apply \
		--context="kind-${cluster_name}" \
		-f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml \
		>/dev/null

	kubectl wait deployments.apps/controller \
		--context="kind-${cluster_name}" \
		-n metallb-system \
		--timeout=1m \
		--for=condition=Available \
		>/dev/null

	kubectl wait daemonsets.app/speaker \
		--context="kind-${cluster_name}" \
		-n metallb-system \
		--timeout=1m \
		--for=jsonpath='{.status.numberReady}'=1 \
		>/dev/null

	kubectl apply \
		--context="kind-${cluster_name}" \
		-f - <<-EOM >/dev/null
			apiVersion: metallb.io/v1beta1
			kind: IPAddressPool
			metadata:
			  name: pool
			  namespace: metallb-system
			spec:
			  addresses:
			  - ${kind_subnet_prefix}.${l2pool_start}-${kind_subnet_prefix}.${l2pool_end}
		EOM

	kubectl apply \
		--context="kind-${cluster_name}" \
		-f - <<-EOM >/dev/null
			apiVersion: metallb.io/v1beta1
			kind: L2Advertisement
			metadata:
			  name: pool
			  namespace: metallb-system
			spec:
			  ipAddressPools:
			  - pool
		EOM

	log::submsg "[${cluster_name}] MetalLB deployed"
}
