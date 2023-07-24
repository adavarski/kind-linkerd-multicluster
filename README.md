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

Run the `setup-clusters.sh` script. It creates three KinD clusters:

- One primary cluster (`primary`)
- Two Istio remotes (`remote1`, `remote2`)

`kubectl` contexts are named respectively:

- `kind-primary`
- `kind-remote1`
- `kind-remote2`


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

