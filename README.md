# SPIFFE / SPIRE Kubernetes Demo

This demo demonstrates how to deploy **SPIFFE** and **SPIRE** inside a local **kind** (Kubernetes in Docker) cluster using **helmfile**, and how workload pods obtain their **SPIFFE Verifiable Identity Documents (SVIDs)** via the SPIFFE Workload API and CSI Driver.

---

## Prerequisites

Ensure you have the following CLI tools installed:

- [kind](https://kind.sigs.k8s.io) (Kubernetes in Docker)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (Kubernetes CLI)
- [helm](https://helm.sh) (Kubernetes package manager)
- [helmfile](https://helmfile.readthedocs.io/en/latest/) (Declarative Helm release manager)

You will also need a container runtime:
- [docker](https://www.docker.com) or [podman](https://podman.io)

### With `nix` and `direnv`

If you are using Nix with flakes, you can enter a shell with all required tools:

```bash
nix develop
```

If you use `direnv`, run `direnv allow` to automatically load the dev environment.

---

## Setup the Environment

### 1. Create the kind Cluster

Create the local Kubernetes cluster using the provided configuration:

```bash
kind create cluster --config kind-config.yaml
```

### 2. Deploy SPIRE via Helmfile

Install the SPIRE CRDs, SPIRE Server, SPIRE Agent, and SPIFFE CSI Driver:

```bash
helmfile apply --skip-diff-on-install
```

### 3. Verify the Deployment

Check that all SPIRE components are running and healthy:

```bash
watch kubectl get pods -A
```

You should see:
- `spire-server-0` (SPIRE Server StatefulSet & Controller Manager)
- `spire-agent-*` (SPIRE Agent DaemonSet)
- `spiffe-csi-driver-*` (SPIFFE CSI Driver DaemonSet)

---

## Run the Demo

### 1. Apply the ClusterSPIFFEID Registration Entry

Register the dynamic identity mapping rule. This assigns SPIFFE IDs formatted as `spiffe://example.org/ns/<namespace>/sa/<serviceaccount>` to any pod labeled with `spiffe.io/spire-managed-identity: "true"`:

```bash
kubectl apply -f examples/00-clusterspiffeid.yaml
```

### 2. Deploy the Demo Workload Pods

Deploy `tls-server` and `tls-client`. The server runs an OpenSSL mutual-TLS server and the client calls it with its own SVID.

```bash
kubectl apply -f examples/01-tls-server.yaml
kubectl apply -f examples/02-tls-client.yaml
```

### 3. Optional: Inspect SVID Certificates with OpenSSL

You can inspect and verify the fetched X.509 SVID certificates locally using `kubectl exec` and `openssl`:

#### Inspect SPIFFE ID (SAN) and Certificate Details

Extract and inspect the Subject Alternative Name (SAN) containing the SPIFFE ID:

```bash
kubectl exec tls-server -c tls -- cat /svid-data/svid.0.pem \
	| openssl x509 -text -noout \
	| grep -A 2 "Subject Alternative Name"
```

#### Verify SVID Against Trust Bundle

Verify that the workload's X.509 SVID is valid and signed by the SPIFFE trust domain root CA:

```bash
# Extract Trust Bundle from the pod
kubectl exec tls-server -c tls -- \
	cat /svid-data/bundle.0.pem > ./bundle.0.pem

# Verify certificate chain
kubectl exec tls-server -c tls -- cat /svid-data/svid.0.pem \
	| openssl verify -CAfile ./bundle.0.pem
```

### 4. Observe SVID-Based mTLS

The TLS server pod uses its SVID as the OpenSSL server certificate and requires a client certificate signed by the SPIFFE bundle. The TLS client presents its SVID with an OpenSSL client in a loop:

```bash
# TLS client SVID (spiffe://example.org/ns/default/sa/tls-client)
kubectl logs tls-client -c tls
```

Output contains

```
HTTP/1.0 200 ok
Content-type: text/html
```

on success.

### 5. Demonstrate Rejection

Exec into the TLS client container:

```bash
kubectl exec -it tls-client -c tls -- /bin/sh
```

From inside the container, connect without presenting a client certificate. The TLS server should reject the connection because client authentication is required:

```sh
printf 'GET / HTTP/1.1\r\nHost: tls-server\r\nConnection: close\r\n\r\n' | openssl s_client -connect tls-server.default.svc.cluster.local:8443 -CAfile /svid-data/bundle.0.pem -verify_return_error -quiet
```

---

## Clean Up

To delete the demo pods and CRs:

```bash
kubectl delete -f examples/02-tls-client.yaml
kubectl delete -f examples/01-tls-server.yaml
kubectl delete -f examples/00-clusterspiffeid.yaml
```

To delete the kind cluster completely:

```bash
kind delete cluster --name cds-2026-demo
```
