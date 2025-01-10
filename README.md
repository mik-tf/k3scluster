<h1> Highly Available (HA) Kubernetes (K3s) Cluster Deployment Script</h1>

<h2>Table of Contents</h2>

- [Introduction](#introduction)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Makefile Targets](#makefile-targets)
- [Script Workflow](#script-workflow)
  - [hacluster.sh Workflow](#haclustersh-workflow)
  - [app\_nginx.sh Workflow](#app_nginxsh-workflow)
- [Cleanup](#cleanup)
- [License](#license)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)
- [Support](#support)

---

## Introduction

This repository provides a comprehensive solution for deploying and managing a Highly Available (HA) Kubernetes (K3s) cluster using Tailscale for secure networking. It simplifies the process of setting up a robust, multi-node Kubernetes cluster with automated deployment, application deployment (NGINX example), and efficient cleanup procedures.

## Features

- **Automated Deployment:** Streamlined setup of a multi-node K3s cluster with multiple control plane and worker nodes.
- **Tailscale Integration:** Leverages Tailscale for secure and reliable communication between cluster nodes.
- **High Availability:** Ensures cluster resilience with multiple control plane nodes.
- **NGINX Deployment Example:** Includes an example for deploying and exposing an NGINX application with Ingress controllers for high availability and load balancing.
- **Automated Cleanup:** Provides scripts for cleaning up the application and the entire cluster, simplifying removal and redeployment.
- **Comprehensive Logging:** Detailed logging with color-coded output for easy monitoring and troubleshooting.
- **Makefile Driven:** Uses a Makefile to organize and execute various deployment and cleanup tasks.

## Architecture

The cluster consists of:

- **Control Plane Nodes:** Multiple K3s server nodes forming the control plane for managing the cluster.
- **Worker Nodes:**  Nodes where workloads (like the NGINX deployment) are scheduled.
- **Tailscale Network:**  Provides a secure mesh network for communication between all nodes.
- **NGINX Deployment:**  Example application deployed as a Deployment with multiple replicas for high availability.
- **Ingress Controllers:**  Multiple Ingress controllers distributed across worker nodes for load balancing and high availability of the NGINX application.


## Prerequisites

1. **Local Machine:** Ubuntu 24.04 with:
   - `kubectl`
   - `helm`
   - `curl`
   - `ssh`
   - `jq` (optional, for JSON parsing)

   These will be installed automatically if not present.

2. **Cluster Configuration File:**  `ha_cluster.txt` (See `ha_cluster_template.txt` for an example and copy it to `ha_cluster.txt`  with your node details).  This file defines the IP addresses and usernames for your control plane and worker nodes.

3. **SSH Access:**
   - Passwordless SSH access to all nodes using an SSH key (default: `~/.ssh/id_ed25519`).
   - SSH public key added to each node's `authorized_keys`.

4. **Node Requirements:**
   - Passwordless `sudo` access on all nodes.
   - Tailscale installed and running on all nodes.
   - Ubuntu/Debian-based Linux distribution recommended.


## Usage

1. **Clone the repository:**

   ```bash
   git clone https://github.com/mik-tf/k3scluster.git
   cd k3scluster
   ```

2. **Configure the cluster:**

   ```bash
   cp ha_cluster_template.txt ha_cluster.txt
   # Edit ha_cluster.txt with your node details (Tailscale IPs and usernames)
   ```

3. **Deploy the cluster:**

   ```bash
   make cluster
   ```

4. **Deploy the NGINX application:**

    ```bash
    make app-nginx
    ```


## Makefile Targets

The Makefile provides the following targets:

- `make cluster`: Deploys the HA K3s cluster.
- `make app-nginx`: Deploys the NGINX application with Ingress controllers.
- `make clean-cluster`: Cleans up the K3s cluster.
- `make clean-app`: Cleans up the NGINX application.
- `make help`: Displays help information about the Makefile targets.

## Script Workflow

### hacluster.sh Workflow

1. **Initialization:** Displays script description and prompts for confirmation.
2. **Prerequisite Check:** Verifies and installs necessary tools on the local machine.
3. **Cluster Configuration:** Parses `ha_cluster.txt` and validates node information.
4. **Connectivity Test:** Checks SSH and Tailscale connectivity to all nodes.
5. **K3s Installation:** Installs and configures K3s on control plane and worker nodes.
6. **Cluster Verification:** Waits for nodes to become ready and labels worker nodes.
7. **Output:** Displays the cluster status.


### app_nginx.sh Workflow

1. **Initialization:**  Displays script description and logs the start of the NGINX deployment.
2. **Cluster Information:** Parses the `ha_cluster.txt` file to get node information.
3. **MagicDNS Domain:** Prompts the user for their Tailscale MagicDNS domain (e.g., `example.ts.net`).
4. **NGINX Deployment Creation:** Creates a Kubernetes Deployment for NGINX with 3 replicas.
5. **LoadBalancer Service:** Creates a LoadBalancer Service to expose the NGINX deployment.  Uses the Tailscale IPs of the worker nodes as `externalIPs`.
6. **Ingress Controller Installation:**
    - Installs `helm`.
    - Sets up `kubeconfig` to communicate with the cluster.
    - Installs the `ingress-nginx` controller on each worker node, configuring them for high availability and assigning different ingress classes.
7. **Verification:** Checks the status of the NGINX pods, services, and ingress classes.
8. **Access Information:** Prints the URLs that can be used to access the NGINX application, including Tailscale IPs and MagicDNS names.
9. **URL Accessibility Test:** Tests the accessibility of the provided URLs using `curl` and displays a summary table with status codes and latency.

## Cleanup

Use the following Makefile targets for cleanup:

- **`make clean-app`**: Removes the NGINX deployment, services, ingress controllers, and related resources.
- **`make clean-cluster`**: Completely removes the K3s cluster from all nodes.


## License

This project is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file for details.

## Contributing

Contributions are welcome! Please fork the repository, create a feature branch, and submit a pull request.

## Disclaimer

This project is provided "as is" without any warranty, express or implied. Use it at your own risk.  The authors and contributors will not be liable for any damages or losses arising from the use of this project.

This script automates the deployment of a Kubernetes cluster and related infrastructure.  While designed for ease of use, it involves potentially destructive actions such as installing software and modifying system configurations on your target nodes.  **Ensure you understand the implications and have backups before proceeding.**

## Support

For support, open an issue in the repository, providing detailed information about your environment and any relevant logs or error messages.