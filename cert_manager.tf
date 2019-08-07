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
    command = "kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v0.8.1/cert-manager.yaml"
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
