###############################################################################
# Security Tools Module — Outputs
###############################################################################

output "security_namespace" {
  description = "Namespace where security tools are deployed"
  value       = kubernetes_namespace.security.metadata[0].name
}

output "falco_release_name" {
  description = "Helm release name for Falco"
  value       = helm_release.falco.name
}

output "falco_release_version" {
  description = "Deployed version of Falco Helm chart"
  value       = helm_release.falco.version
}

output "trivy_operator_release_name" {
  description = "Helm release name for Trivy Operator"
  value       = helm_release.trivy_operator.name
}

output "trivy_operator_release_version" {
  description = "Deployed version of Trivy Operator Helm chart"
  value       = helm_release.trivy_operator.version
}

output "gatekeeper_release_name" {
  description = "Helm release name for OPA Gatekeeper"
  value       = helm_release.gatekeeper.name
}

output "gatekeeper_release_version" {
  description = "Deployed version of OPA Gatekeeper Helm chart"
  value       = helm_release.gatekeeper.version
}

output "gatekeeper_namespace" {
  description = "Namespace where OPA Gatekeeper is deployed"
  value       = "gatekeeper-system"
}
