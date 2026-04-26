# Infrastructure as Code: Scalable and Hardened Go Deployment on Hetzner Cloud

## Overview
This project demonstrates a professional, automated approach to provisioning scalable cloud infrastructure and deploying a Go-based web application. By utilizing industry-standard tools such as Terraform for infrastructure management and cloud-init for server configuration, the repository provides a fully reproducible environment that adheres to advanced DevOps and security best practices.

The system is designed to handle multiple server instances and incorporates multiple layers of security hardening, including multi-factor authentication (MFA) readiness and anti-brute-force mechanisms.

## System Architecture

### 1. Infrastructure Layer (Terraform)
The infrastructure is managed declaratively using Terraform. It provisions a dynamic number of Virtual Private Servers (VPS) on Hetzner Cloud:
- **State Management**: Terraform state is localized in `infra/state/` to keep the configuration directory clean.
- **Scalability**: Configurable server count (default: 2) via the `SERVER_COUNT` variable in your `.env` file.
- **Operating System**: Ubuntu 22.04 LTS.
- **Server Type**: CX23.
- **Unique Naming**: Servers are prefixed with `first-time-provisioning-app-` to ensure isolation and prevent conflicts with other projects.
- **Automated Secrets**: Generates unique, secure root and deployer passwords for each instance, stored locally in `secrets/passwords` and `secrets/deployer_passwords`.

### 2. Security & Configuration Layer (Cloud-Init)
Upon initial boot, each server undergoes rigorous configuration via cloud-init:
- **Authentication**: Secured via project-specific SSH keys (`first-time-provisioning-key`). Password authentication and root password login are disabled by default.
- **SSH Hardening**: Strict enforcement of modern cryptographic standards (Ed25519, AES-GCM, Curve25519) and connection multiplexing for performance.
- **Anti-Brute Force**: Implementation of `fail2ban` to monitor SSH logs and automatically ban malicious IP addresses.
- **Enforced MFA**: Configuration of PAM (Pluggable Authentication Modules) with `libpam-google-authenticator` and enforcement of 2FA (Key + MFA) via SSH `AuthenticationMethods`.
- **Firewall**: Hardened via Uncomplicated Firewall (UFW), restricting access to OpenSSH and the application ports (80, 443).
- **Service Management**: Environment variable configuration and systemd service initialization.

### 3. Application Layer (Go)
The application is a modular HTTP server written in Go that follows modern architectural standards and clean code principles.
- **Modular Architecture**: The codebase is separated into distinct files with specific responsibilities:
  - `app/main.go`: Minimal entry point handling configuration and application lifecycle.
  - `app/server.go`: Orchestrates the `WebServer` abstraction, routing, and port management.
  - `app/handlers.go`: Contains the business logic for request processing.
  - `app/types.go`: Defines the core data structures and interfaces.
- **Dynamic Theming**: The application supports server-specific color themes. It automatically cycles through high-contrast themes (Cyber Blue, Cyber Pink, Neon Purple, Neon Green, Neon Orange) based on the server instance number, making cluster management visually intuitive.
- **Structured Logging**: Implementation of `log/slog` for high-performance, JSON-formatted structured logs.
- **Interface-Driven Design**: Utilizes Go interfaces (`WebServer`) for better testability and abstraction.
- **Ports**: Configurable via the `APP_PORTS` environment variable (defaults to `80,443`).
- **Privileged Ports**: The deployment process automatically grants the binary `cap_net_bind_service` capabilities to allow binding to ports below 1024 without running as root.
- **Service Management**: Managed by systemd on the remote host to ensure persistence, automatic restarts, and centralized logging.

## Prerequisites
Detailed installation instructions are available in `commands-to-be-run.md`. The local environment can be automatically configured by running:
```bash
make setup
```

## Setup and Deployment

### 1. Secret Management
Configuration is handled through environment variables.

1. **Configuration**: Create a `.env` file in the project root:
   ```env
   APP_PORTS=80,443
   SERVER_COUNT=2
   ```

2. **Infrastructure Secrets**: Create `secrets/hcloud_token` and paste your Hetzner Cloud API token into it.

### 2. Infrastructure Bootstrapping
To provision the hardware, harden the operating systems, and deploy the application across all instances:

```bash
make bootstrap
```

This command automates:
- Generation of project-specific SSH keys (stored in `~/.ssh/` and `secrets/`).
- Terraform initialization and multi-server application.
- Saving instance IPs to `secrets/ips` and root passwords to `secrets/passwords`.
- Concurrent application deployment and systemd service activation.

### 3. Application Updates
To deploy updates to the application code across the cluster without changing the underlying infrastructure:

```bash
make deploy
```

## Workflow Comparison: `make bootstrap` vs. `make deploy`

It is important to understand when to use each command to maintain a professional workflow:

| Feature | `make bootstrap` | `make deploy` |
| :--- | :--- | :--- |
| **Scope** | Full Stack (Keys + Infra + App) | Application Only |
| **Speed** | Slower (minutes) | Fast (seconds) |
| **Infra Changes** | Yes (Updates/Replaces servers) | No (Skips Terraform) |
| **App Changes** | Yes (Builds + Uploads) | Yes (Builds + Uploads) |
| **Risk** | High (Possible server replacement) | Low (Binary update only) |

### When to use what:
*   **Use `make bootstrap`** when you change:
    *   `infra/main.tf` (e.g., adding more servers or changing server type).
    *   `infra/cloud-init.yaml` (e.g., installing new OS packages or changing passwords).
    *   You are setting up the project for the first time.
*   **Use `make deploy`** when you change:
    *   `app/main.go` (any Go code changes).
    *   Port configurations in `.env` (`APP_PORTS`).
    *   The `deploy/deploy.sh` script itself.

### 4. Remote Access
To establish a secure SSH connection to one of the provisioned servers:

```bash
make ssh
```

This script will detect available instances and prompt for selection if multiple servers are active.

### 5. Infrastructure Decommissioning
To remove all provisioned resources and local artifacts:

```bash
make down
```

### Infrastructure Lifecycle and Maintenance

#### Server Replacement (Stability & Safety)
In previous versions, changing any configuration often forced a full server replacement. We have hardened the infrastructure to be more stable:

1.  **Stable Identities**: By using unique, project-specific names for SSH keys and servers, we prevent accidental replacements caused by conflicts in your Hetzner account.
2.  **Optimized Dependency Chain**: The server configuration (`user_data`) is now decoupled from the SSH key resource. Updating the SSH key in Hetzner no longer triggers a mandatory server destruction.
3.  **Manual Refresh**: We use `lifecycle { ignore_changes = [user_data] }` to ensure that small, accidental changes to the infrastructure definition don't destroy your running servers. If you intentionally want to rebuild a server (e.g. to apply new OS patches or passwords), you should run `make down` followed by `make bootstrap`.

#### Persistent vs. Ephemeral Data
Because servers can still be replaced during major infrastructure changes (like changing the server type or OS image), you should treat the server's local storage as **ephemeral**. Any data you want to keep (like databases or user uploads) should be stored on external volumes or remote databases.

## Security Architecture & 2026 Best Practices

This project implements a defense-in-depth security model optimized for 2026 standards. Below are the core considerations and the rationale behind the implementation.

### 1. SSH Hardening 
*   **User Segregation**: All standard operations (deployment, maintenance) are performed via a dedicated `deployer` user with `sudo` privileges. Root access is restricted and intended only as a recovery fallback.
*   **Enforced MFA Readiness**: While we maintain a streamlined key-only approach for deployment automation, the system is pre-configured for PAM-based MFA (Multi-Factor Authentication), allowing for easy transition to high-security human access if required.
*   **Key-Only Authentication**: `PasswordAuthentication` is explicitly disabled. In 2026, passwords for public-facing SSH are considered a legacy risk and a critical failure in modern security architecture. Login is enforced via project-specific Ed25519 keys.
*   **Cryptographic Tightening**: We restrict the server to use only modern, "quantum-resistant" or high-entropy algorithms:
    *   **Kex (Key Exchange)**: `curve25519-sha256` (Efficient and highly secure).
    *   **Ciphers**: `chacha20-poly1305` and `aes-gcm` (Authenticated encryption).
    *   **MACs**: Encrypt-then-MAC (EtM) versions only, to prevent padding oracle attacks.

### 2. Deep Dive: Key-Only vs. SSH + Password + PAM
A common question is why disabling passwords and using only keys (with PAM MFA) is superior to the traditional Password + PAM approach.

*   **Entropy and Brute Force Resistance**: Passwords, even complex ones, are susceptible to dictionary attacks or credential stuffing. An Ed25519 key provides over 256 bits of entropy, making it mathematically impossible to brute-force.
*   **Elimination of the Primary Attack Surface**: Standard SSH password authentication is the #1 target for automated botnets. Disabling it removes the server from 99% of automated "low-hanging fruit" attacks.
*   **Identity vs. Knowledge**: A password is "something you know" (phishable). An SSH key is "something you have" (the private key file). By using **Key-Only Authentication**, we move away from knowledge-based vulnerabilities, relying on cryptographic proof of identity. For high-security environments, we maintain readiness for **Key + MFA** (the "Identity + Token" model) by ensuring the PAM stack is pre-hardened.

### 3. Infrastructure Isolation
*   **Project-Specific SSH Config**: We avoid using the global `~/.ssh/config` or `~/.ssh/known_hosts`. This prevents "lateral movement" or "configuration leakage" where settings for one project might accidentally affect another.
*   **Automated Host Key Lifecycle**: We use automated destroy provisioners to prevent "REMOTE HOST IDENTIFICATION HAS CHANGED" errors while maintaining strict host key checking. When a server is destroyed, its entry is surgically removed from the local `known_hosts` file.
*   **Ephemeral Secrets**: Root and Deployer passwords generated by Terraform are treated as "break-glass" credentials. They are stored in the `secrets/` directory (git-ignored) and are intended to be rotated or deleted after the initial hardening is confirmed.

### 4. Active Defense & Patching
*   **Unattended Upgrades**: The system is configured to automatically apply security patches. In 2026, manual patching is a liability; "auto-patch by default" is the professional standard.
*   **Fail2Ban**: Even with password auth disabled, SSH scanners can cause log bloat. Fail2Ban automatically null-routes IPs that exhibit aggressive scanning behavior.
*   **UFW (Uncomplicated Firewall)**: Strict "Default Deny" policy. Only ports 22 (SSH), 80 (HTTP), and 443 (HTTPS) are exposed.

### 5. Application-Level Security
*   **Non-Root Execution**: The Go binary does not run as root. It uses Linux Capabilities (`cap_net_bind_service`) to bind to port 80/443, ensuring that even if the application is compromised, the attacker does not have immediate root access to the OS.

### 6. Seamless Automation (2026 Best Practice)
*   **Non-Interactive Workflows**: We utilize **Key-Only Authentication** for all automated tasks. By disabling `PasswordAuthentication` and `KbdInteractiveAuthentication` in favor of high-entropy Ed25519 keys, we eliminate all interactive prompts during the deployment pipeline.
*   **Encapsulated Identities**: SSH identities are managed per-project, ensuring that the deployment environment is strictly isolated from the developer's personal SSH configuration.

## Troubleshooting
If the application is unreachable, verify the status of the cloud-init process. Initial security hardening and package installation may take up to 90 seconds. Access each instance via its respective IP: `http://<server-ip>`.
