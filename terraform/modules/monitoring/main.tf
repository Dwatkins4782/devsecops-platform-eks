###############################################################################
# Monitoring Module
# Deploys Prometheus, Grafana, and Alertmanager via Helm with CloudWatch
# integration for comprehensive observability.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }
}

# -----------------------------------------------------------------------------
# Prometheus + Grafana (kube-prometheus-stack)
# Includes Prometheus Operator, Prometheus, Alertmanager, Grafana, and
# default recording/alerting rules.
# -----------------------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 900

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention         = var.prometheus_retention
          retentionSize     = var.prometheus_retention_size
          replicas          = var.prometheus_replicas
          scrapeInterval    = "30s"
          evaluationInterval = "30s"

          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.storage_class_name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }

          podMonitorSelectorNilUsesHelmValues     = false
          serviceMonitorSelectorNilUsesHelmValues  = false
          ruleSelectorNilUsesHelmValues             = false
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          replicas = var.alertmanager_replicas
          resources = {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "512Mi"
            }
          }
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.storage_class_name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }

        config = {
          global = {
            resolve_timeout = "5m"
          }
          route = {
            group_by        = ["alertname", "namespace", "severity"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "4h"
            receiver        = "default"
            routes = [
              {
                match = {
                  severity = "critical"
                }
                receiver        = "critical-alerts"
                repeat_interval = "1h"
              },
              {
                match = {
                  severity = "warning"
                }
                receiver        = "warning-alerts"
                repeat_interval = "4h"
              }
            ]
          }
          receivers = [
            {
              name = "default"
            },
            {
              name = "critical-alerts"
              slack_configs = [
                {
                  api_url  = var.slack_webhook_url
                  channel  = var.slack_critical_channel
                  title    = "[CRITICAL] {{ .GroupLabels.alertname }}"
                  text     = "{{ range .Alerts }}*{{ .Annotations.summary }}*\n{{ .Annotations.description }}\n{{ end }}"
                }
              ]
            },
            {
              name = "warning-alerts"
              slack_configs = [
                {
                  api_url  = var.slack_webhook_url
                  channel  = var.slack_warning_channel
                  title    = "[WARNING] {{ .GroupLabels.alertname }}"
                  text     = "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}"
                }
              ]
            }
          ]
        }
      }

      grafana = {
        replicas = var.grafana_replicas

        adminPassword = var.grafana_admin_password

        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }

        persistence = {
          enabled          = true
          size             = "10Gi"
          storageClassName = var.storage_class_name
        }

        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name      = "default"
                orgId     = 1
                folder    = ""
                type      = "file"
                disableDeletion = false
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }

        sidecar = {
          dashboards = {
            enabled         = true
            searchNamespace = "ALL"
            label           = "grafana_dashboard"
          }
          datasources = {
            enabled         = true
            searchNamespace = "ALL"
          }
        }

        ingress = {
          enabled = var.grafana_ingress_enabled
          annotations = {
            "kubernetes.io/ingress.class"                    = "alb"
            "alb.ingress.kubernetes.io/scheme"               = "internal"
            "alb.ingress.kubernetes.io/target-type"          = "ip"
            "alb.ingress.kubernetes.io/listen-ports"         = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn"      = var.grafana_certificate_arn
          }
          hosts = var.grafana_ingress_hosts
        }
      }

      defaultRules = {
        create = true
        rules = {
          alertmanager                = true
          etcd                        = false
          configReloaders             = true
          general                     = true
          k8s                         = true
          kubeApiserverAvailability   = true
          kubeApiserverBurnrate       = true
          kubeApiserverHistogram      = true
          kubeApiserverSlos           = true
          kubeControllerManager       = true
          kubelet                     = true
          kubeProxy                   = true
          kubePrometheusGeneral       = true
          kubePrometheusNodeRecording = true
          kubernetesApps              = true
          kubernetesResources         = true
          kubernetesStorage           = true
          kubernetesSystem            = true
          kubeSchedulerAlerting       = true
          kubeSchedulerRecording      = true
          kubeStateMetrics            = true
          network                     = true
          node                        = true
          nodeExporterAlerting        = true
          nodeExporterRecording       = true
          prometheus                  = true
          prometheusOperator          = true
        }
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Container Insights (AWS-native monitoring)
# -----------------------------------------------------------------------------

resource "helm_release" "cloudwatch_observability" {
  name       = "amazon-cloudwatch-observability"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-cloudwatch-observability"
  version    = var.cloudwatch_addon_version
  namespace  = "amazon-cloudwatch"

  create_namespace = true

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = data.aws_region.current.name
  }

  set {
    name  = "containerLogs.enabled"
    value = "true"
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# -----------------------------------------------------------------------------
# IRSA Role for CloudWatch Agent
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.cluster_name}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_agent.name
}
