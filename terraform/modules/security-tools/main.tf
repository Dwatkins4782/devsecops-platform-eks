###############################################################################
# Security Tools Module
# Deploys Falco (runtime security), Trivy Operator (vulnerability scanning),
# and OPA Gatekeeper (admission control) via Helm.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
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
# Security Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "security" {
  metadata {
    name = var.security_namespace

    labels = {
      "app.kubernetes.io/managed-by"             = "terraform"
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }

    annotations = {
      "purpose" = "Security tooling - Falco, Trivy, OPA Gatekeeper"
    }
  }
}

# -----------------------------------------------------------------------------
# Falco — Runtime Security Monitoring
# Monitors syscalls and Kubernetes audit logs for anomalous behavior.
# -----------------------------------------------------------------------------

resource "helm_release" "falco" {
  name       = "falco"
  repository = "https://falcosecurity.github.io/charts"
  chart      = "falco"
  version    = var.falco_version
  namespace  = kubernetes_namespace.security.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      driver = {
        kind = var.falco_driver_kind
      }

      falco = {
        grpc = {
          enabled       = true
          bind_address  = "unix:///run/falco/falco.sock"
          threadiness   = 0
        }

        grpc_output = {
          enabled = true
        }

        json_output         = true
        json_include_output_property = true
        log_stderr          = true
        log_syslog          = false
        log_level           = var.falco_log_level

        priority            = var.falco_minimum_priority

        buffered_outputs    = false
        rate_limiter = {
          enabled    = true
          rate       = 100
          max_burst  = 1000
        }

        http_output = {
          enabled = var.falco_http_output_enabled
          url     = var.falco_http_output_url
        }

        rules_file = [
          "/etc/falco/falco_rules.yaml",
          "/etc/falco/falco_rules.local.yaml",
          "/etc/falco/rules.d",
        ]
      }

      falcosidekick = {
        enabled = var.enable_falcosidekick

        config = {
          slack = {
            webhookurl  = var.slack_webhook_url
            channel     = var.falco_slack_channel
            minimumpriority = "warning"
            outputformat    = "all"
          }

          prometheus = {
            extralabels = "source:falco"
          }
        }

        webui = {
          enabled = var.enable_falcosidekick_ui
        }
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }

      tolerations = [
        {
          effect   = "NoSchedule"
          operator = "Exists"
        }
      ]

      serviceMonitor = {
        enabled = true
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# Trivy Operator — Continuous Vulnerability Scanning
# Automatically scans running workloads for CVEs, misconfigurations,
# exposed secrets, and license compliance issues.
# -----------------------------------------------------------------------------

resource "helm_release" "trivy_operator" {
  name       = "trivy-operator"
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  version    = var.trivy_operator_version
  namespace  = kubernetes_namespace.security.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      trivy = {
        severity = var.trivy_severity_levels
        ignoreUnfixed = var.trivy_ignore_unfixed

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      operator = {
        scanJobsConcurrentLimit = var.trivy_concurrent_scans
        scanJobsRetryDelay      = "30s"
        vulnerabilityScannerEnabled    = true
        configAuditScannerEnabled      = true
        exposedSecretScannerEnabled    = true
        rbacAssessmentScannerEnabled   = true
        infraAssessmentScannerEnabled  = true

        scanJobTimeout = "10m"

        metricsVulnIdEnabled   = true
        metricsFindingsEnabled = true
      }

      serviceMonitor = {
        enabled = true
        labels = {
          release = "kube-prometheus-stack"
        }
      }

      compliance = {
        failEntriesLimit  = 10
        reportType        = ["summary", "detail"]
        cron              = var.trivy_compliance_cron
        specs             = ["nsa", "cis"]
      }
    })
  ]

  depends_on = [helm_release.falco]
}

# -----------------------------------------------------------------------------
# OPA Gatekeeper — Kubernetes Admission Control
# Enforces policies at the API server level using Rego constraint templates.
# -----------------------------------------------------------------------------

resource "helm_release" "gatekeeper" {
  name       = "gatekeeper"
  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  version    = var.gatekeeper_version
  namespace  = "gatekeeper-system"
  timeout    = 600

  create_namespace = true

  values = [
    yamlencode({
      replicas = var.gatekeeper_replicas

      auditInterval     = var.gatekeeper_audit_interval
      constraintViolationsLimit = 100
      auditMatchKindOnly = false
      auditFromCache     = false

      emitAdmissionEvents  = true
      emitAuditEvents      = true
      logDenies            = true
      logLevel             = "INFO"

      image = {
        pullPolicy = "IfNotPresent"
      }

      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8888"
      }

      controllerManager = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }
      }

      audit = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      mutatingWebhookEnabled = false

      psp = {
        enabled = false
      }
    })
  ]

  depends_on = [helm_release.falco]
}

# -----------------------------------------------------------------------------
# Gatekeeper Constraint Templates (Custom Resource Definitions)
# These define reusable policy types that constraints reference.
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "require_labels_template" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8srequiredlabels"
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sRequiredLabels"
          }
          validation = {
            openAPIV3Schema = {
              type = "object"
              properties = {
                labels = {
                  type = "array"
                  items = {
                    type = "string"
                  }
                }
              }
            }
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-REGO
            package k8srequiredlabels

            violation[{"msg": msg, "details": {"missing_labels": missing}}] {
              provided := {label | input.review.object.metadata.labels[label]}
              required := {label | label := input.parameters.labels[_]}
              missing := required - provided
              count(missing) > 0
              msg := sprintf("Missing required labels: %%v", [missing])
            }
          REGO
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

resource "kubernetes_manifest" "block_latest_tag_template" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8sblocklatestimages"
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sBlockLatestImages"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-REGO
            package k8sblocklatestimages

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              endswith(container.image, ":latest")
              msg := sprintf("Container %%v uses :latest tag. Use a specific version tag instead.", [container.name])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              not contains(container.image, ":")
              msg := sprintf("Container %%v has no tag specified (defaults to :latest). Use a specific version tag.", [container.name])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.initContainers[_]
              endswith(container.image, ":latest")
              msg := sprintf("Init container %%v uses :latest tag. Use a specific version tag instead.", [container.name])
            }
          REGO
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

resource "kubernetes_manifest" "require_resource_limits_template" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8srequireresourcelimits"
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sRequireResourceLimits"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-REGO
            package k8srequireresourcelimits

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              not container.resources.limits.cpu
              msg := sprintf("Container %%v does not have CPU limits set.", [container.name])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              not container.resources.limits.memory
              msg := sprintf("Container %%v does not have memory limits set.", [container.name])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              not container.resources.requests.cpu
              msg := sprintf("Container %%v does not have CPU requests set.", [container.name])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              not container.resources.requests.memory
              msg := sprintf("Container %%v does not have memory requests set.", [container.name])
            }
          REGO
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}
