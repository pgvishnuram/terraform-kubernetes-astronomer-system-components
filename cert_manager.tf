resource "kubernetes_namespace" "cert_manager" {
  count = var.certmanager_domain != "" ? 1 : 0
  metadata {
    name = "cert-manager"
    labels = {
      istio-injection                         = "disabled"
      "certmanager.k8s.io/disable-validation" = true
    }
  }
  provisioner "local-exec" {
    command = "kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.8/deploy/manifests/00-crds.yaml"
  }
}

kubectl create secret generic clouddns-dns01-solver-svc-acct \
 --from-file=key.json

resource "kubernetes_secret" "cert_manager_key" {
  count = var.certmanager_domain != "" ? 1 : 0

  metadata {
    name      = "clouddns-dns01-solver-svc-acct"
    namespace = kubernetes_namespace.cert_manager[0].metadata[0].name
  }

  type = "kubernetes.io/generic"

  data = {
    "connection" = var.db_connection_string
  }
}

data "helm_repository" "jetstack" {

  depends_on = [module.tiller]
  name       = "jetstack"
  url        = "https://charts.jetstack.io"
}

resource "helm_release" "cert_manager" {
  count      = var.certmanager_domain != "" ? 1 : 0
  depends_on = [module.tiller]
  name       = "cert-manager"
  version    = "v0.8.1"
  chart      = "cert-manager"
  repository = data.helm_repository.jetstack.name
  namespace  = kubernetes_namespace.cert_manager[0].metadata[0].name
  wait       = true
  values = [<<EOF
ingressShim:
  defaultIssuerName: letsencrypt-prod
  defaultIssuerKind: Issuer
EOF
]
}

resource null_resource "issuer" {

  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    command = <<EOS
cat <<EOF | kubectl apply -f -
---
apiVersion: certmanager.k8s.io/v1alpha1
kind: Issuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: steven@astronomer.io
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: example-issuer-account-key
    solvers:
    - dns01:
      clouddns:
        project: ${var.gcp_project}
        serviceAccountSecretRef:
          name: prod-clouddns-svc-acct-secret
          key: service-account.json
EOF
EOS
  }

}

resource null_resource "certificate" {

  depends_on = [null_resource.issuer]

  provisioner "local-exec" {
    command = <<EOS
cat <<EOF | kubectl apply -f -
---
apiVersion: certmanager.k8s.io/v1alpha1
kind: Certificate
metadata:
 name: test-certificate
 namespace: ${var.astronomer_namespace}
spec:
 secretName: test-secret
 issuerRef:
   name: letsencrypt-prod
   kind: Issuer
 dnsNames:
  - '${var.certmanager_domain}'
 acme:
   config:
     - dns01:
         provider: dns
       domains:
         - '${var.certmanager_domain}'
EOF
EOS
  }

}
