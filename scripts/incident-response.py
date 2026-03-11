#!/usr/bin/env python3
"""
Kubernetes Incident Response Script
====================================
Automated incident response for the DevSecOps platform. Collects forensic
data from compromised pods, isolates workloads via network policy, captures
logs, and generates incident reports.

Usage:
    python incident-response.py --pod <pod-name> --namespace <ns> [--action isolate|collect|full]
    python incident-response.py --namespace <ns> --label app=compromised --action full
"""

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
    from kubernetes.stream import stream
except ImportError:
    print("ERROR: kubernetes client library not installed.")
    print("Install with: pip install kubernetes")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

INCIDENT_DIR = Path("./incident-reports")
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
ISOLATION_POLICY_NAME = "incident-response-isolate-{pod}"
EVIDENCE_COMMANDS = [
    ("processes", ["ps", "auxwww"]),
    ("network-connections", ["cat", "/proc/net/tcp"]),
    ("environment", ["env"]),
    ("mounts", ["mount"]),
    ("hostname", ["hostname"]),
    ("dns-resolv", ["cat", "/etc/resolv.conf"]),
    ("etc-passwd", ["cat", "/etc/passwd"]),
]


# ---------------------------------------------------------------------------
# Logger Setup
# ---------------------------------------------------------------------------

def setup_logging(verbose: bool = False) -> logging.Logger:
    """Configure and return the logger instance."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format=LOG_FORMAT)
    return logging.getLogger("incident-response")


# ---------------------------------------------------------------------------
# Kubernetes Client Initialization
# ---------------------------------------------------------------------------

def init_k8s_client() -> tuple:
    """Initialize Kubernetes API clients, trying in-cluster first."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()

    core_v1 = client.CoreV1Api()
    apps_v1 = client.AppsV1Api()
    networking_v1 = client.NetworkingV1Api()

    return core_v1, apps_v1, networking_v1


# ---------------------------------------------------------------------------
# Incident Context
# ---------------------------------------------------------------------------

class IncidentContext:
    """Holds all state for a single incident response operation."""

    def __init__(self, namespace: str, pod_name: str, incident_id: str):
        self.namespace = namespace
        self.pod_name = pod_name
        self.incident_id = incident_id
        self.timestamp = datetime.now(timezone.utc).isoformat()
        self.report_dir = INCIDENT_DIR / incident_id
        self.evidence: dict = {}
        self.actions_taken: list = []
        self.errors: list = []

    def add_evidence(self, key: str, data: str):
        self.evidence[key] = data

    def add_action(self, action: str):
        self.actions_taken.append({
            "action": action,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    def add_error(self, error: str):
        self.errors.append({
            "error": error,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })


# ---------------------------------------------------------------------------
# Evidence Collection
# ---------------------------------------------------------------------------

def collect_pod_metadata(
    logger: logging.Logger,
    core_v1: client.CoreV1Api,
    ctx: IncidentContext,
) -> Optional[client.V1Pod]:
    """Collect full pod specification and status as evidence."""
    logger.info(f"Collecting metadata for pod {ctx.namespace}/{ctx.pod_name}")
    try:
        pod = core_v1.read_namespaced_pod(name=ctx.pod_name, namespace=ctx.namespace)
        pod_dict = pod.to_dict()
        ctx.add_evidence("pod-metadata", json.dumps(pod_dict, indent=2, default=str))
        ctx.add_action(f"Collected pod metadata for {ctx.pod_name}")
        logger.info(f"Pod status: {pod.status.phase}")
        logger.info(f"Node: {pod.spec.node_name}")
        logger.info(f"IP: {pod.status.pod_ip}")
        logger.info(f"Containers: {[c.name for c in pod.spec.containers]}")
        return pod
    except ApiException as e:
        msg = f"Failed to collect pod metadata: {e.reason}"
        logger.error(msg)
        ctx.add_error(msg)
        return None


def collect_pod_logs(
    logger: logging.Logger,
    core_v1: client.CoreV1Api,
    ctx: IncidentContext,
    pod: client.V1Pod,
):
    """Collect current and previous logs from all containers in the pod."""
    logger.info("Collecting container logs")
    for container in pod.spec.containers:
        container_name = container.name
        for previous in [False, True]:
            label = f"logs-{container_name}" + ("-previous" if previous else "")
            try:
                logs = core_v1.read_namespaced_pod_log(
                    name=ctx.pod_name,
                    namespace=ctx.namespace,
                    container=container_name,
                    previous=previous,
                    tail_lines=10000,
                    timestamps=True,
                )
                ctx.add_evidence(label, logs)
                ctx.add_action(f"Collected {'previous ' if previous else ''}logs for container {container_name}")
                logger.info(f"  Collected {label}: {len(logs)} bytes")
            except ApiException as e:
                if e.status != 404:
                    logger.warning(f"  Could not collect {label}: {e.reason}")


def collect_runtime_evidence(
    logger: logging.Logger,
    core_v1: client.CoreV1Api,
    ctx: IncidentContext,
    pod: client.V1Pod,
):
    """Execute forensic commands inside the container to collect runtime state."""
    logger.info("Collecting runtime evidence from container")
    container_name = pod.spec.containers[0].name

    for evidence_name, command in EVIDENCE_COMMANDS:
        try:
            result = stream(
                core_v1.connect_get_namespaced_pod_exec,
                name=ctx.pod_name,
                namespace=ctx.namespace,
                container=container_name,
                command=command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False,
            )
            ctx.add_evidence(f"runtime-{evidence_name}", result)
            ctx.add_action(f"Collected runtime evidence: {evidence_name}")
            logger.info(f"  Collected {evidence_name}")
        except ApiException as e:
            logger.warning(f"  Failed to collect {evidence_name}: {e.reason}")
            ctx.add_error(f"Failed to exec for {evidence_name}: {e.reason}")
        except Exception as e:
            logger.warning(f"  Error collecting {evidence_name}: {str(e)}")


def collect_events(
    logger: logging.Logger,
    core_v1: client.CoreV1Api,
    ctx: IncidentContext,
):
    """Collect Kubernetes events related to the pod and namespace."""
    logger.info("Collecting cluster events")
    try:
        field_selector = f"involvedObject.name={ctx.pod_name}"
        events = core_v1.list_namespaced_event(
            namespace=ctx.namespace,
            field_selector=field_selector,
        )
        event_data = []
        for event in events.items:
            event_data.append({
                "type": event.type,
                "reason": event.reason,
                "message": event.message,
                "count": event.count,
                "first_timestamp": str(event.first_timestamp),
                "last_timestamp": str(event.last_timestamp),
                "source": event.source.component if event.source else None,
            })
        ctx.add_evidence("events", json.dumps(event_data, indent=2))
        ctx.add_action(f"Collected {len(event_data)} events")
        logger.info(f"  Collected {len(event_data)} events")
    except ApiException as e:
        logger.error(f"Failed to collect events: {e.reason}")
        ctx.add_error(f"Failed to collect events: {e.reason}")


def collect_network_policies(
    logger: logging.Logger,
    networking_v1: client.NetworkingV1Api,
    ctx: IncidentContext,
):
    """Collect existing network policies in the namespace."""
    logger.info("Collecting network policies")
    try:
        policies = networking_v1.list_namespaced_network_policy(namespace=ctx.namespace)
        policy_data = []
        for policy in policies.items:
            policy_data.append({
                "name": policy.metadata.name,
                "pod_selector": str(policy.spec.pod_selector),
                "policy_types": policy.spec.policy_types,
            })
        ctx.add_evidence("network-policies", json.dumps(policy_data, indent=2))
        ctx.add_action(f"Collected {len(policy_data)} network policies")
    except ApiException as e:
        logger.error(f"Failed to collect network policies: {e.reason}")


# ---------------------------------------------------------------------------
# Isolation Actions
# ---------------------------------------------------------------------------

def isolate_pod(
    logger: logging.Logger,
    networking_v1: client.NetworkingV1Api,
    core_v1: client.CoreV1Api,
    ctx: IncidentContext,
    pod: client.V1Pod,
):
    """Isolate the compromised pod by applying a deny-all network policy."""
    logger.warning(f"ISOLATING pod {ctx.namespace}/{ctx.pod_name}")

    # Get pod labels for the network policy selector
    pod_labels = pod.metadata.labels or {}
    if not pod_labels:
        logger.error("Pod has no labels; cannot create targeted network policy")
        ctx.add_error("Pod has no labels for isolation policy selector")
        return False

    policy_name = ISOLATION_POLICY_NAME.format(pod=ctx.pod_name[:50])

    network_policy = client.V1NetworkPolicy(
        metadata=client.V1ObjectMeta(
            name=policy_name,
            namespace=ctx.namespace,
            labels={
                "app.kubernetes.io/managed-by": "incident-response",
                "incident-id": ctx.incident_id,
            },
            annotations={
                "incident-response/reason": f"Isolating pod {ctx.pod_name}",
                "incident-response/timestamp": ctx.timestamp,
            },
        ),
        spec=client.V1NetworkPolicySpec(
            pod_selector=client.V1LabelSelector(
                match_labels=pod_labels,
            ),
            policy_types=["Ingress", "Egress"],
            ingress=[],
            egress=[],
        ),
    )

    try:
        networking_v1.create_namespaced_network_policy(
            namespace=ctx.namespace,
            body=network_policy,
        )
        ctx.add_action(f"Created isolation network policy: {policy_name}")
        logger.warning(f"  Created deny-all network policy: {policy_name}")
    except ApiException as e:
        if e.status == 409:
            logger.info(f"  Isolation policy already exists: {policy_name}")
        else:
            logger.error(f"  Failed to create isolation policy: {e.reason}")
            ctx.add_error(f"Failed to create isolation policy: {e.reason}")
            return False

    # Add isolation label to the pod
    try:
        body = {"metadata": {"labels": {"security.incident/isolated": "true"}}}
        core_v1.patch_namespaced_pod(
            name=ctx.pod_name,
            namespace=ctx.namespace,
            body=body,
        )
        ctx.add_action("Added isolation label to pod")
        logger.info("  Added isolation label to pod")
    except ApiException as e:
        logger.warning(f"  Could not label pod: {e.reason}")

    return True


# ---------------------------------------------------------------------------
# Report Generation
# ---------------------------------------------------------------------------

def generate_report(logger: logging.Logger, ctx: IncidentContext):
    """Write all collected evidence and actions to disk."""
    logger.info(f"Generating incident report: {ctx.report_dir}")

    ctx.report_dir.mkdir(parents=True, exist_ok=True)

    # Write individual evidence files
    for key, data in ctx.evidence.items():
        filepath = ctx.report_dir / f"{key}.txt"
        filepath.write_text(data if isinstance(data, str) else json.dumps(data, indent=2))

    # Write summary report
    summary = {
        "incident_id": ctx.incident_id,
        "timestamp": ctx.timestamp,
        "target_pod": ctx.pod_name,
        "target_namespace": ctx.namespace,
        "actions_taken": ctx.actions_taken,
        "errors": ctx.errors,
        "evidence_files": list(ctx.evidence.keys()),
        "total_evidence_size_bytes": sum(
            len(v.encode()) if isinstance(v, str) else len(json.dumps(v).encode())
            for v in ctx.evidence.values()
        ),
    }

    summary_path = ctx.report_dir / "incident-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    logger.info(f"  Summary written to: {summary_path}")

    # Write human-readable timeline
    timeline_path = ctx.report_dir / "timeline.txt"
    with open(timeline_path, "w") as f:
        f.write(f"Incident Response Timeline\n")
        f.write(f"{'=' * 60}\n")
        f.write(f"Incident ID:  {ctx.incident_id}\n")
        f.write(f"Pod:          {ctx.namespace}/{ctx.pod_name}\n")
        f.write(f"Started:      {ctx.timestamp}\n\n")
        for action in ctx.actions_taken:
            f.write(f"  [{action['timestamp']}] {action['action']}\n")
        if ctx.errors:
            f.write(f"\nErrors:\n")
            for error in ctx.errors:
                f.write(f"  [{error['timestamp']}] {error['error']}\n")

    logger.info(f"  Timeline written to: {timeline_path}")
    logger.info(f"  Total evidence files: {len(ctx.evidence)}")

    return summary_path


# ---------------------------------------------------------------------------
# Main Orchestration
# ---------------------------------------------------------------------------

def run_incident_response(args: argparse.Namespace):
    """Main entry point for incident response workflow."""
    logger = setup_logging(args.verbose)
    core_v1, apps_v1, networking_v1 = init_k8s_client()

    incident_id = f"INC-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}-{args.pod}"
    ctx = IncidentContext(
        namespace=args.namespace,
        pod_name=args.pod,
        incident_id=incident_id,
    )

    logger.info("=" * 60)
    logger.info(f"INCIDENT RESPONSE INITIATED")
    logger.info(f"  Incident ID: {incident_id}")
    logger.info(f"  Target:      {args.namespace}/{args.pod}")
    logger.info(f"  Action:      {args.action}")
    logger.info("=" * 60)

    # Step 1: Collect pod metadata (always needed)
    pod = collect_pod_metadata(logger, core_v1, ctx)
    if pod is None:
        logger.error("Cannot proceed without pod metadata. Exiting.")
        sys.exit(1)

    # Step 2: Collect evidence
    if args.action in ("collect", "full"):
        logger.info("--- Phase: Evidence Collection ---")
        collect_pod_logs(logger, core_v1, ctx, pod)
        collect_runtime_evidence(logger, core_v1, ctx, pod)
        collect_events(logger, core_v1, ctx)
        collect_network_policies(logger, networking_v1, ctx)

    # Step 3: Isolate the pod
    if args.action in ("isolate", "full"):
        logger.info("--- Phase: Pod Isolation ---")
        success = isolate_pod(logger, networking_v1, core_v1, ctx, pod)
        if success:
            logger.warning("Pod has been network-isolated")
        else:
            logger.error("Pod isolation failed -- manual intervention required")

    # Step 4: Generate report
    logger.info("--- Phase: Report Generation ---")
    summary_path = generate_report(logger, ctx)

    # Final summary
    logger.info("=" * 60)
    logger.info("INCIDENT RESPONSE COMPLETE")
    logger.info(f"  Incident ID:     {incident_id}")
    logger.info(f"  Actions taken:   {len(ctx.actions_taken)}")
    logger.info(f"  Errors:          {len(ctx.errors)}")
    logger.info(f"  Evidence files:  {len(ctx.evidence)}")
    logger.info(f"  Report:          {summary_path}")
    logger.info("=" * 60)

    if ctx.errors:
        logger.warning("Some operations encountered errors. Review the report.")
        return 1
    return 0


# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Kubernetes Incident Response Automation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Collect evidence from a compromised pod
  python incident-response.py --pod webapp-abc123 --namespace production --action collect

  # Isolate a pod immediately
  python incident-response.py --pod webapp-abc123 --namespace production --action isolate

  # Full response: collect evidence then isolate
  python incident-response.py --pod webapp-abc123 --namespace production --action full
        """,
    )
    parser.add_argument(
        "--pod", "-p",
        required=True,
        help="Name of the target pod",
    )
    parser.add_argument(
        "--namespace", "-n",
        required=True,
        help="Kubernetes namespace of the target pod",
    )
    parser.add_argument(
        "--action", "-a",
        choices=["collect", "isolate", "full"],
        default="full",
        help="Action to perform: collect evidence, isolate pod, or both (default: full)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose debug logging",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    exit_code = run_incident_response(args)
    sys.exit(exit_code)
