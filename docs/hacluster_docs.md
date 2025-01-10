<h1>HA Cluster Docs</h1>

<h2>Table of Contents</h2>

- [Introduction](#introduction)
- [Points of Failure](#points-of-failure)
- [Potential Failures Analysis](#potential-failures-analysis)
  - [Assumptions](#assumptions)
  - [Failure Scenarios and Impact](#failure-scenarios-and-impact)
    - [Low Impact (Cluster remains functional)](#low-impact-cluster-remains-functional)
    - [Medium Impact (Potential for Disruption)](#medium-impact-potential-for-disruption)
    - [High Impact (Cluster Failure)](#high-impact-cluster-failure)
  - [Mitigating Failures](#mitigating-failures)

---

# Introduction

We provide documentation on the HA cluster.

# Points of Failure

There is no single point of failture in this HA cluster once it is deployed.

1. **Control Plane High Availability**:
   - There are 3 control plane nodes running K3s in HA mode
   - If one control plane node fails, the others continue managing the cluster

2. **NGINX Application Availability**:
   - NGINX deployment has 3 replicas
   - These pods are distributed across worker nodes
   - If one pod or node fails, traffic is automatically redirected to the remaining pods

3. **Load Balancing**:
   - The service is exposed via LoadBalancer type with multiple Tailscale IPs
   - Traffic can enter through any of the worker nodes
   - If one worker node fails, traffic will still reach the application through other nodes

4. **Network Redundancy**:
   - Tailscale provides mesh networking
   - Each node can communicate directly with every other node
   - No single network path is critical

# Potential Failures Analysis

Let's break down the potential failure combinations in your K3s cluster, considering you have redundancy in control planes, worker nodes, and ingress controllers.

## Assumptions

* **Quorum for Control Plane:** K3s uses etcd for its control plane data store.  A majority of control plane nodes must be operational for the cluster to function.  In your case, that's 2 out of 3.
* **Ingress Controller High Availability:** You have 3 ingress controllers, presumably using a load balancer or similar mechanism to distribute traffic.  The loss of one or two ingress controllers shouldn't bring down the entire ingress functionality.
* **Tailscale for Networking:** Tailscale provides resilient networking, so node-to-node communication shouldn't be entirely dependent on the underlying network infrastructure. However, heavy network segmentation or Tailscale's own outages could become factors.

## Failure Scenarios and Impact

Here's a breakdown of the failure combinations, from least to most impactful:

### Low Impact (Cluster remains functional)

* **1 Worker Node Down:** The cluster should continue operating normally.  Pods on the failed worker will be rescheduled to other available workers.
* **1 Ingress Controller Down:** The remaining two ingress controllers will continue to handle traffic.  There might be a brief period of disruption during failover.
* **1 Control Plane Node Down:**  The cluster continues to operate as you still have a quorum (2 out of 3 control plane nodes).

### Medium Impact (Potential for Disruption)

* **2 Worker Nodes Down:**  This significantly reduces your cluster's capacity.  If the remaining worker doesn't have enough resources, pod scheduling might fail, and some applications might become unavailable.
* **2 Ingress Controllers Down:** While theoretically, the single remaining ingress controller could handle traffic, this puts a significant strain on it and could lead to performance degradation or even failure under load.

### High Impact (Cluster Failure)

* **2 Control Plane Nodes Down:**  You no longer have a quorum for the control plane (only 1 out of 3 remaining). The cluster will cease to function correctly.  No new pods can be scheduled, and existing pods might become unresponsive.
* **3 Worker Nodes Down:** All workloads are down as there's nowhere for them to run.
* **3 Ingress Controllers Down:** No external traffic can reach your services.
* **Combinations:**  Any combination that results in loss of control plane quorum (2+ control plane nodes) or all worker nodes will bring the cluster down.  For example:
    * 1 Control Plane Node + 1 Worker Node + 1 Ingress Controller down (if the remaining control plane node fails during recovery, you lose quorum).
    * 1 Control Plane Node + 2 Worker Nodes down.

## Mitigating Failures

* **Monitoring:** Implement robust monitoring to detect failures early.
* **Resource Limits and Requests:** Configure appropriate resource requests and limits for your pods to ensure that the remaining worker nodes can handle the load in case of failures.
* **Automated Failover:** Use a load balancer or service mesh for ingress controllers to ensure automatic failover.
* **Disaster Recovery:**  Have a plan for restoring your cluster from backups in case of catastrophic failures.  Consider a multi-region setup for higher availability.
* **Regular Testing:** Simulate failures in a non-production environment to validate your resilience strategy.