# KinD: Linkerd Lab multi-cluster


## Requirements

- Linux OS
- [Docker](https://docs.docker.com/)
- [KinD](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [istioctl](https://istio.io/latest/docs/setup/install/istioctl/)
- [helm](https://helm.sh/docs/intro/install/)
- [step](https://smallstep.com/docs/step-cli/installation)
- [linkerd](https://linkerd.io/2.13/getting-started/#step-1-install-the-cli)
- [linkerd-smi](https://linkerd.io/2.13/tasks/linkerd-smi/#cli)


```
kind create cluster --config kind-primary.yaml
kind create cluster --config kind-remote1.yaml
kind create cluster --config kind-remote2.yaml

docker network inspect kind -f '{{.IPAM.Config}}'


helm repo add metallb https://metallb.github.io/metallb --force-update
for ctx in kind-primary kind-remote1 kind-remote2; do
 helm install metallb -n metallb-system --create-namespace metallb/metallb --kube-context=${ctx}
done

kubectl --context=kind-primary apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.17.0.61-172.17.0.70

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  labels:
    todos: verdade
  name: example
  namespace: metallb-system
EOF

kubectl --context=kind-remote1 apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.17.0.71-172.17.0.80

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  labels:
    todos: verdade
  name: example
  namespace: metallb-system
EOF

kubectl --context=kind-remote2 apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.17.0.81-172.17.0.90

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  labels:
    todos: verdade
  name: example
  namespace: metallb-system
EOF

```


`kubectl` contexts are named respectively:

- `kind-primary`
- `kind-remote1`
- `kind-remote2`



$ kubectl config get-contexts 
CURRENT   NAME            CLUSTER         AUTHINFO        NAMESPACE
          kind-primary   kind-primary   kind-primary   
          kind-remote1    kind-remote1    kind-remote1    
*         kind-remote2    kind-remote2    kind-remote2  

```


```

mkdir certs && cd certs
step certificate create \
  root.linkerd.cluster.local \
  ca.crt ca.key --profile root-ca \
  --no-password --insecure
step certificate create \
  identity.linkerd.cluster.local \
  issuer.crt issuer.key \
  --profile intermediate-ca \
  --not-after 8760h --no-password \
  --insecure --ca ca.crt --ca-key ca.key

alias lk='linkerd'
alias ka='kubectl apply -f '

for ctx in kind-primary kind-remote1 kind-remote2; do                   
  echo "install crd ${ctx}"
  lk install --context=${ctx} --crds | ka - --context=${ctx};

  echo "install linkerd ${ctx}";
  lk install --context=${ctx} \
    --identity-trust-anchors-file=ca.crt \
    --identity-issuer-certificate-file=issuer.crt \
    --identity-issuer-key-file=issuer.key | ka - --context=${ctx};

  echo "install viz ${ctx}";
  lk --context=${ctx} viz install | ka - --context=${ctx};

  echo "install multicluster ${ctx}";    
  lk --context=${ctx} multicluster install | ka - --context=${ctx};

  echo "install smi ${ctx}";        
  lk smi install --context=${ctx}  | ka - --context=${ctx};
done

for ctx in kind-primary kind-remote1 kind-remote2; do
  printf "Checking cluster: ${ctx} ........."
  while [ "$(kubectl --context=${ctx} -n linkerd-multicluster get service linkerd-gateway -o 'custom-columns=:.status.loadBalancer.ingress[0].ip' --no-headers)" = "<none>" ]; do
      printf '.'
      sleep 1
  done
  echo "`kubectl --context=${ctx} -n linkerd-multicluster get service linkerd-gateway -o 'custom-columns=:.status.loadBalancer.ingress[0].ip' --no-headers`"
  printf "\n"
done


for ctx in kind-primary kind-remote1 kind-remote2; do
  echo "Checking link....${ctx}"
  lk --context=${ctx} multicluster check

  echo "Checking gateways ...${ctx}"
  lk --context=${ctx} multicluster gateways

  echo "..............done ${ctx}"
done


for ctx in kind-primary kind-remote1 kind-remote2; do
  echo "Adding test services on cluster: ${ctx} ........."
  kubectl --context=${ctx} create ns test
  kubectl --context=${ctx} apply \
    -n test -k "github.com/adavarski/kind-linkerd-multicluster/multicluster/${ctx}/"

  kubectl --context=${ctx} -n test \
    rollout status deploy/podinfo || break
  echo "-------------"
done


for ctx in kind-primary kind-remote1 kind-remote2; do
  echo "Check pods on cluster: ${ctx} ........."
  kubectl get pod -n test --context=${ctx}
done

kubectl port-forward -n test svc/frontend 8080:8080 --context=kind-primary
Browser: http://localhost:8080

kubectl port-forward -n test svc/frontend 8080:8080 --context=kind-remote1
Browser: http://localhost:8080

kubectl port-forward -n test svc/frontend 8080:8080 --context=kind-remote2
Browser: http://localhost:8080

for ctx in kind-primary kind-remote1 kind-remote2; do
  echo -en "\n\nLabel svc podinfo on cluster: ${ctx} .........\n"
  kubectl label svc -n test podinfo mirror.linkerd.io/exported=true --context=${ctx}
  sleep 4

  echo "Check services transConnected (if word exists )....on cluster ${ctx}"
  kubectl get svc -n test --context=${ctx}

done


kubectl --context=kind-primary apply -f - <<EOF
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: podinfo
  namespace: test
spec:
  service: podinfo
  backends:
  - service: podinfo
    weight: 50
  - service: podinfo-kind-remote1
    weight: 50
EOF    

kubectl --context=kind-remote1 apply -f - <<EOF
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: podinfo
  namespace: test
spec:
  service: podinfo
  backends:
  - service: podinfo
    weight: 50
  - service: podinfo-kind-primary
    weight: 50
EOF    

$ kubectl port-forward -n test --context=kind-primary svc/frontend 8080

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
for ctx in kind-primary kind-remote1 kind-remote2; do
  echo "Install ingress-nginx - ${ctx}"
  helm install ingress-nginx -n ingress-nginx --create-namespace ingress-nginx/ingress-nginx --set controller.podAnnotations.linkerd.io/inject=enabled --kube-context=${ctx}
  
  echo "Wait for ingress-nginx installation to finish, 30s, wide"
  kubectl rollout status deploy -n ingress-nginx ingress-nginx-controller --context=${ctx}

  echo "Breeding an income for the podinfo - ${ctx}"
  kubectl --context=${ctx} -n test create ingress frontend --class nginx --rule="frontend-${ctx}.127-0-0-1.sslip.io/*=frontend:8080" --annotation "nginx.ingress.kubernetes.io/service-upstream=true"
done


for ctx in kind-primary kind-remote1 kind-remote2; do
  echo "Add the hostname and IP to your /etc/hosts and wait for ingress-nginx to assign IP to the ingress, about 30s"
  kubectl --context=${ctx} get ingress -n test 
done
```


## Clean local environment
```
$ kind delete cluster --name=primary
Deleting cluster "primary" ...
$ kind delete cluster --name=remote1
Deleting cluster "remote1" ...
$ kind delete cluster --name=remote2
Deleting cluster "remote2" .
```

Note: We can run the `setup-clusters.sh` script. It creates three KinD clusters:

- One primary cluster (`primary`)
- Two remotes (`remote1`, `remote2`)

Example Output:

```

[+] Creating KinD clusters
   ⠿ [remote2] Cluster created
   ⠿ [remote1] Cluster created
   ⠿ [primary] Cluster created
[+] Adding routes to other clusters
   ⠿ [primary] Route to 10.20.0.0/24 added
   ⠿ [primary] Route to 10.30.0.0/24 added
   ⠿ [remote1] Route to 10.10.0.0/24 added
   ⠿ [remote1] Route to 10.30.0.0/24 added
   ⠿ [remote2] Route to 10.10.0.0/24 added
   ⠿ [remote2] Route to 10.20.0.0/24 added
[+] Deploying MetalLB inside primary
   ⠿ [primary] MetalLB deployed
[+] Deploying MetalLB inside clusters
   ⠿ [primary] MetalLB deployed
   ⠿ [remote1] MetalLB deployed
   ⠿ [remote2] MetalLB deployed

```
