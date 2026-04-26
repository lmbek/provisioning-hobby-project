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
- **Automated Secrets**: Generates a unique, secure root password for each instance, stored locally in `secrets/passwords`.

### 2. Security & Configuration Layer (Cloud-Init)
Upon initial boot, each server undergoes rigorous configuration via cloud-init:
- **Authentication**: Supports both project-specific SSH keys and secure root passwords.
- **Anti-Brute Force**: Implementation of `fail2ban` to monitor SSH logs and automatically ban malicious IP addresses.
- **MFA Readiness**: Configuration of PAM (Pluggable Authentication Modules) with `libpam-google-authenticator` for future Multi-Factor Authentication integration.
- **Firewall**: Hardened via Uncomplicated Firewall (UFW), restricting access to OpenSSH and the application ports (80, 443).
- **Service Management**: Environment variable configuration and systemd service initialization.

### 3. Application Layer (Go)
The application is a modular HTTP server written in Go that follows modern architectural standards and clean code principles.
- **Modular Architecture**: The codebase is separated into distinct files with specific responsibilities:
  - `app/main.go`: Minimal entry point handling configuration and application lifecycle.
  - `app/server.go`: Orchestrates the `WebServer` abstraction, routing, and port management.
  - `app/handlers.go`: Contains the business logic for request processing.
  - `app/types.go`: Defines the core data structures and interfaces.
- **Dynamic Theming**: The application supports server-specific color themes. For example, `hello-app-1` automatically applies a unique "Cyber Pink" theme to differentiate instances visually.
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

## Infrastructure Lifecycle and Maintenance

### Server Replacement (Forces Replacement)
In the Terraform output, you may see the message `user_data = (sensitive value) # forces replacement`. This is an important aspect of how cloud infrastructure works:

1.  **Sensitive Value**: The `user_data` contains the generated root password. To keep your terminal logs secure, Terraform hides this value.
2.  **Forces Replacement**: The `user_data` script (cloud-init) is only executed by the server during its **very first boot**. If you change anything in the infrastructure configuration that affects `user_data` (like changing the password or adding a new package to `cloud-init.yaml`), Terraform must destroy the existing server and create a new one to ensure the new configuration is applied.

### Persistent vs. Ephemeral Data
Because the servers are replaced when infrastructure configuration changes, you should treat the server's local storage as **ephemeral**. Any data you want to keep (like databases or user uploads) should be stored on external volumes or remote databases (which can be added as next steps in the project's evolution).

## Security Best Practices
- **Multi-Layered Authentication**: The system prioritizes SSH key authentication but maintains a secure root password as a secondary method, aligning with robust recovery standards.
- **SSH Hardening**: `fail2ban` protects against automated brute-force attacks by enforcing rate-limiting on authentication attempts.
- **MFA Integration**: The server is pre-configured for PAM-based MFA. To finalize, run `google-authenticator` interactively on the server.
- **Secret Isolation**: API tokens, private keys, and generated passwords are never committed to version control.

## Troubleshooting
If the application is unreachable, verify the status of the cloud-init process. Initial security hardening and package installation may take up to 90 seconds. Access each instance via its respective IP: `http://<server-ip>`.
