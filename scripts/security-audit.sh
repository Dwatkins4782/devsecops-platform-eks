#!/usr/bin/env bash
###############################################################################
# Kubernetes Security Audit Script
# Performs comprehensive security checks across the EKS cluster including
# pod security, RBAC, network policies, secrets, images, and compliance.
#
# Usage: ./security-audit.sh [--namespace <ns>] [--output <json|text>] [--verbose]
###############################################################################

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR="./audit-reports"
NAMESPACE="${NAMESPACE:-}"
OUTPUT_FORMAT="text"
VERBOSE=false
EXIT_CODE=0
WARN_COUNT=0
FAIL_COUNT=0
PASS_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Kubernetes Security Audit Script for DevSecOps Platform

Options:
    -n, --namespace <ns>    Audit a specific namespace (default: all)
    -o, --output <format>   Output format: text or json (default: text)
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

Examples:
    $SCRIPT_NAME                          # Audit all namespaces
    $SCRIPT_NAME -n production            # Audit production namespace
    $SCRIPT_NAME -o json -v               # Verbose JSON output
EOF
    exit 0
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS_COUNT++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN_COUNT++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL_COUNT++)); EXIT_CODE=1; }

header() {
    echo ""
    echo "==========================================================================="
    echo " $1"
    echo "==========================================================================="
}

check_prerequisites() {
    local missing=false
    for cmd in kubectl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            log_fail "Required command not found: $cmd"
            missing=true
        fi
    done
    if [[ "$missing" == "true" ]]; then
        echo "Install missing dependencies and try again."
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        log_fail "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
    log_pass "Connected to cluster successfully"
}

get_namespaces() {
    if [[ -n "$NAMESPACE" ]]; then
        echo "$NAMESPACE"
    else
        kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' \
            | grep -v -E '^(kube-system|kube-public|kube-node-lease)$'
    fi
}

# ---------------------------------------------------------------------------
# Audit Checks
# ---------------------------------------------------------------------------

audit_privileged_containers() {
    header "CHECK: Privileged Containers"
    local found=false

    for ns in $(get_namespaces); do
        local privs
        privs=$(kubectl get pods -n "$ns" -o json 2>/dev/null | \
            jq -r '.items[] | .metadata.name as $pod |
            .spec.containers[]? | select(.securityContext.privileged == true) |
            "\($pod) -> \(.name)"' 2>/dev/null || echo "")

        if [[ -n "$privs" ]]; then
            found=true
            while IFS= read -r line; do
                log_fail "Privileged container in namespace $ns: $line"
            done <<< "$privs"
        fi
    done

    if [[ "$found" == "false" ]]; then
        log_pass "No privileged containers found"
    fi
}

audit_root_containers() {
    header "CHECK: Containers Running as Root"
    local found=false

    for ns in $(get_namespaces); do
        local roots
        roots=$(kubectl get pods -n "$ns" -o json 2>/dev/null | \
            jq -r '.items[] | .metadata.name as $pod |
            .spec.containers[]? |
            select(.securityContext.runAsNonRoot != true and
                   (.securityContext.runAsUser == null or .securityContext.runAsUser == 0)) |
            "\($pod) -> \(.name)"' 2>/dev/null || echo "")

        if [[ -n "$roots" ]]; then
            found=true
            while IFS= read -r line; do
                log_warn "Container may run as root in namespace $ns: $line"
            done <<< "$roots"
        fi
    done

    if [[ "$found" == "false" ]]; then
        log_pass "All containers enforce non-root execution"
    fi
}

audit_resource_limits() {
    header "CHECK: Resource Limits"
    local found=false

    for ns in $(get_namespaces); do
        local no_limits
        no_limits=$(kubectl get pods -n "$ns" -o json 2>/dev/null | \
            jq -r '.items[] | .metadata.name as $pod |
            .spec.containers[]? |
            select(.resources.limits.cpu == null or .resources.limits.memory == null) |
            "\($pod) -> \(.name)"' 2>/dev/null || echo "")

        if [[ -n "$no_limits" ]]; then
            found=true
            while IFS= read -r line; do
                log_warn "Missing resource limits in namespace $ns: $line"
            done <<< "$no_limits"
        fi
    done

    if [[ "$found" == "false" ]]; then
        log_pass "All containers have resource limits defined"
    fi
}

audit_latest_tags() {
    header "CHECK: Images Using :latest Tag"
    local found=false

    for ns in $(get_namespaces); do
        local latest_imgs
        latest_imgs=$(kubectl get pods -n "$ns" -o json 2>/dev/null | \
            jq -r '.items[] | .metadata.name as $pod |
            .spec.containers[]? |
            select(.image | (endswith(":latest") or (contains(":") | not))) |
            "\($pod) -> \(.image)"' 2>/dev/null || echo "")

        if [[ -n "$latest_imgs" ]]; then
            found=true
            while IFS= read -r line; do
                log_fail "Image using :latest or untagged in namespace $ns: $line"
            done <<< "$latest_imgs"
        fi
    done

    if [[ "$found" == "false" ]]; then
        log_pass "No images using :latest or untagged references"
    fi
}

audit_network_policies() {
    header "CHECK: Network Policies"

    for ns in $(get_namespaces); do
        local np_count
        np_count=$(kubectl get networkpolicies -n "$ns" --no-headers 2>/dev/null | wc -l)

        if [[ "$np_count" -eq 0 ]]; then
            log_warn "No network policies in namespace: $ns"
        else
            log_pass "Namespace $ns has $np_count network policy(ies)"
        fi
    done
}

audit_default_service_accounts() {
    header "CHECK: Default Service Account Token Mounting"

    for ns in $(get_namespaces); do
        local automount
        automount=$(kubectl get serviceaccount default -n "$ns" -o json 2>/dev/null | \
            jq -r '.automountServiceAccountToken // true' 2>/dev/null || echo "true")

        if [[ "$automount" == "true" ]]; then
            log_warn "Default SA automounts tokens in namespace: $ns"
        else
            log_pass "Default SA token automount disabled in: $ns"
        fi
    done
}

audit_rbac_cluster_admin() {
    header "CHECK: ClusterRoleBindings to cluster-admin"

    local bindings
    bindings=$(kubectl get clusterrolebindings -o json 2>/dev/null | \
        jq -r '.items[] | select(.roleRef.name == "cluster-admin") |
        .metadata.name + " -> " +
        (.subjects // [] | map(.kind + ":" + .name) | join(", "))' 2>/dev/null || echo "")

    if [[ -n "$bindings" ]]; then
        while IFS= read -r line; do
            log_warn "cluster-admin binding: $line"
        done <<< "$bindings"
    else
        log_pass "No custom cluster-admin bindings found"
    fi
}

audit_secrets_encryption() {
    header "CHECK: Secrets Management"

    local secret_count
    secret_count=$(kubectl get secrets -A --field-selector type=Opaque --no-headers 2>/dev/null | wc -l)
    log_info "Found $secret_count Opaque secrets across the cluster"

    local unencrypted
    unencrypted=$(kubectl get secrets -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.type == "Opaque") |
        select(.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"] != null) |
        .metadata.namespace + "/" + .metadata.name' 2>/dev/null || echo "")

    if [[ -n "$unencrypted" ]]; then
        local count
        count=$(echo "$unencrypted" | wc -l)
        log_warn "$count secret(s) have last-applied-configuration (may contain plaintext values)"
    else
        log_pass "No secrets with exposed last-applied-configuration annotations"
    fi
}

audit_pod_security_standards() {
    header "CHECK: Pod Security Standards Labels"

    for ns in $(get_namespaces); do
        local enforce_label
        enforce_label=$(kubectl get namespace "$ns" -o json 2>/dev/null | \
            jq -r '.metadata.labels["pod-security.kubernetes.io/enforce"] // "not-set"' 2>/dev/null || echo "not-set")

        if [[ "$enforce_label" == "not-set" ]]; then
            log_warn "Namespace $ns has no Pod Security Standards enforcement label"
        elif [[ "$enforce_label" == "privileged" ]]; then
            log_warn "Namespace $ns allows privileged Pod Security Standard"
        else
            log_pass "Namespace $ns enforces '$enforce_label' Pod Security Standard"
        fi
    done
}

audit_security_tools_health() {
    header "CHECK: Security Tools Health"

    # Falco
    local falco_pods
    falco_pods=$(kubectl get pods -A -l app.kubernetes.io/name=falco --no-headers 2>/dev/null | wc -l)
    if [[ "$falco_pods" -gt 0 ]]; then
        log_pass "Falco is running ($falco_pods pod(s))"
    else
        log_fail "Falco is not running"
    fi

    # Trivy Operator
    local trivy_pods
    trivy_pods=$(kubectl get pods -A -l app.kubernetes.io/name=trivy-operator --no-headers 2>/dev/null | wc -l)
    if [[ "$trivy_pods" -gt 0 ]]; then
        log_pass "Trivy Operator is running ($trivy_pods pod(s))"
    else
        log_fail "Trivy Operator is not running"
    fi

    # OPA Gatekeeper
    local gk_pods
    gk_pods=$(kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | wc -l)
    if [[ "$gk_pods" -gt 0 ]]; then
        log_pass "OPA Gatekeeper is running ($gk_pods pod(s))"
    else
        log_fail "OPA Gatekeeper is not running"
    fi

    # Gatekeeper constraints
    local constraint_count
    constraint_count=$(kubectl get constraints --no-headers 2>/dev/null | wc -l)
    log_info "Active Gatekeeper constraints: $constraint_count"
}

# ---------------------------------------------------------------------------
# Report Generation
# ---------------------------------------------------------------------------

generate_report() {
    header "AUDIT SUMMARY"
    echo ""
    echo "  Timestamp:    $TIMESTAMP"
    echo "  Cluster:      $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    echo "  Scope:        ${NAMESPACE:-all namespaces}"
    echo ""
    echo -e "  ${GREEN}PASSED:  $PASS_COUNT${NC}"
    echo -e "  ${YELLOW}WARNINGS: $WARN_COUNT${NC}"
    echo -e "  ${RED}FAILURES: $FAIL_COUNT${NC}"
    echo ""

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}Overall Result: FAIL${NC}"
    elif [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}Overall Result: PASS WITH WARNINGS${NC}"
    else
        echo -e "  ${GREEN}Overall Result: PASS${NC}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -o|--output)    OUTPUT_FORMAT="$2"; shift 2 ;;
        -v|--verbose)   VERBOSE=true; shift ;;
        -h|--help)      usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------

main() {
    echo ""
    echo "###################################################################"
    echo "#  DevSecOps Platform - Kubernetes Security Audit                 #"
    echo "#  Timestamp: $TIMESTAMP                              #"
    echo "###################################################################"

    mkdir -p "$REPORT_DIR"

    check_prerequisites
    audit_privileged_containers
    audit_root_containers
    audit_resource_limits
    audit_latest_tags
    audit_network_policies
    audit_default_service_accounts
    audit_rbac_cluster_admin
    audit_secrets_encryption
    audit_pod_security_standards
    audit_security_tools_health
    generate_report

    exit "$EXIT_CODE"
}

main "$@"
