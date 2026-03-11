###############################################################################
# Monitoring Module — Outputs
###############################################################################

output "prometheus_namespace" {
  description = "Namespace where Prometheus is deployed"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "prometheus_stack_release_name" {
  description = "Helm release name for kube-prometheus-stack"
  value       = helm_release.kube_prometheus_stack.name
}

output "prometheus_stack_version" {
  description = "Deployed version of kube-prometheus-stack"
  value       = helm_release.kube_prometheus_stack.version
}

output "grafana_service_name" {
  description = "Kubernetes service name for Grafana"
  value       = "kube-prometheus-stack-grafana"
}

output "prometheus_service_name" {
  description = "Kubernetes service name for Prometheus"
  value       = "kube-prometheus-stack-prometheus"
}

output "alertmanager_service_name" {
  description = "Kubernetes service name for Alertmanager"
  value       = "kube-prometheus-stack-alertmanager"
}

output "cloudwatch_agent_role_arn" {
  description = "IAM role ARN for the CloudWatch agent"
  value       = aws_iam_role.cloudwatch_agent.arn
}

output "cloudwatch_observability_release_name" {
  description = "Helm release name for CloudWatch Observability"
  value       = helm_release.cloudwatch_observability.name
}
