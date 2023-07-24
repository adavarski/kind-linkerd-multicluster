#!/usr/bin/env bash

source "${BASH_SOURCE[0]%/*}"/logging.sh


# Create a KinD cluster.
#
# We configure the API server's service account issuer to allow Istio to use
# third party service account tokens.
# Ref.
#   https://istio.io/v1.15/docs/ops/best-practices/security/#configure-third-party-service-account-tokens
#   https://v1-24.docs.kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection
function kind::cluster::create {
	local cluster_name=$1
	local pod_subnet=$2
	local svc_subnet=$3

	if kind::cluster::exists ${cluster_name}; then
		log::submsg "[${cluster_name}] Cluster already exists"
		return 0
	fi

	local -i exit_code=0
	kind create cluster \
		--name=${cluster_name} \
		--quiet \
		--image=kindest/node:v1.25.3 \
		--config=<(cat <<-EOM
			kind: Cluster
			apiVersion: kind.x-k8s.io/v1alpha4
			networking:
			  podSubnet: ${pod_subnet}
			  serviceSubnet: ${svc_subnet}
			nodes:
			- role: control-plane
			kubeadmConfigPatches:
			- |
			  apiVersion: kubeadm.k8s.io/v1beta2
			  kind: ClusterConfiguration
			  metadata:
			    name: config
			  apiServer:
			    extraArgs:
			      service-account-issuer: kubernetes.default.svc
			      service-account-signing-key-file: /etc/kubernetes/pki/sa.key
		EOM
		)

	log::submsg "[${cluster_name}] Cluster created"
}

# Check whether a KinD cluster exists.
function kind::cluster::exists {
	local cluster_name=$1

	kind get kubeconfig \
		--name=${cluster_name} \
		--quiet \
		>/dev/null
}

# Wait for the readiness of a KinD cluster.
function kind::cluster::wait_ready {
	local cluster_name=$1

	local output
	# retry for max 60s (30*2s)
	for _ in $(seq 1 60); do
		output="$(kind::cluster::pod_cidr ${cluster_name})"
		if [[ -n ${output} ]]; then
			return 0
		fi

		sleep 2
	done

	log::err "Timeout waiting for readiness of cluster ${cluster_name}"
	return 1
}

# Return the Pod CIDR of the control-plane node in the given cluster.
function kind::cluster::pod_cidr {
	local cluster_name=$1

	local node_name
	node_name="$(kind::cluster::node_name "${cluster_name}")"

	local pod_cidr
	pod_cidr="$(kubectl get node \
		--context="kind-${cluster_name}" \
		-o jsonpath='{.spec.podCIDR}' \
		"${node_name}"
	)"

	echo ${pod_cidr}
}

# Return the IP of the control-plane node in the given cluster.
function kind::cluster::node_ip {
	local cluster_name=$1

	local node_name
	node_name="$(kind::cluster::node_name "${cluster_name}")"

	local node_ip
	node_ip="$(kubectl get node \
		--context="kind-${cluster_name}" \
		-o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' \
		"${node_name}"
	)"

	echo ${node_ip}
}

# Add a route to the given network in the control-plane node of the given cluster.
function kind::cluster::add_route {
	local cluster_name=$1
	local net=$2
	local via=$3

	local node_name
	node_name="$(kind::cluster::node_name "${cluster_name}")"

	local -i exit_code=0
	docker exec "${node_name}" \
		ip route add ${net} via ${via} \
		2>/dev/null \
		|| exit_code=$?

	if ((exit_code)); then
		case $exit_code in
			2)
				log::submsg "[${cluster_name}] Route to ${net} already exists"
				return 0
				;;
			*)
				return $exit_code
				;;
		esac
	fi

	log::submsg "[${cluster_name}] Route to ${net} added"
}

# Return the name of the control-plane node in the given cluster.
function kind::cluster::node_name {
	local cluster_name=$1

	local node_name
	node_name="$(kubectl get nodes \
		--context="kind-${cluster_name}" \
		-o jsonpath='{.items[?(@.metadata.labels['"'"'node-role\.kubernetes\.io/control-plane'"'"'])].metadata.name}' \
	)"

	echo "${node_name}"
}

# Return the subnet of the KinD Docker network.
function kind::subnet {
	local kind_subnet
	kind_subnet="$(docker network inspect kind \
		-f '{{ (index .IPAM.Config 0).Subnet }}' \
	)"

	echo "${kind_subnet}"
}
