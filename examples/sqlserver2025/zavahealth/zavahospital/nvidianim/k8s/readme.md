# NIM Kubernetes manifests

[nim-embedding.yaml](nim-embedding.yaml), [nim-chat.yaml](nim-chat.yaml), and
[ingress.yaml](ingress.yaml) define the inference services and ingress used by
the [NIM deployment guide](../README.md).

Use the parent's deployment scripts and prerequisites rather than applying
manifests without preparation. Review namespace, GPU requests, image tags,
pull-secret references, service routing, and TLS configuration against the
actual cluster. Keep NGC keys and certificate private keys out of source.

Verify readiness and endpoint responses before continuing with
[SQL integration](../sql/readme.md). Obtain approval for GPU spending and
network exposure; teardown belongs to the parent deployment workflow.
