# 🛠 Commands to be Run

This file contains the commands needed to set up your local development environment.

## 🚀 The Fast Way (Automated)
If you are on **macOS** or **Linux**, you can run:
```bash
make setup
```
*(This script requires `curl` and `sudo` access)*

---

## 🏗 The Manual Way

### 1. Install Terraform
Terraform is used to create and manage your Hetzner infrastructure.

#### **macOS (Homebrew)**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

#### **Windows (Chocolatey)**
```powershell
choco install terraform
```

#### **Linux (Ubuntu/Debian)**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

---

### 2. Install Go
Go is the language used for the application.

#### **macOS**
```bash
brew install go
```

#### **Windows**
Download the installer from [go.dev/dl](https://go.dev/dl/)

#### **Linux (Ubuntu)**
```bash
sudo apt update
sudo apt install golang-go
```

---

### 3. Install Make, jq, and Netcat
Make is used to run the project commands, jq is for processing data, and netcat is for health checks.

#### **macOS**
```bash
brew install make jq netcat
```

#### **Windows**
```powershell
choco install make jq
# Note: Netcat is usually available in WSL or can be installed via 'make setup'
```

#### **Linux**
```bash
sudo apt update
sudo apt install build-essential jq netcat-openbsd
```
