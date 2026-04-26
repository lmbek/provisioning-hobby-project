#!/bin/bash

# SSH connection helper for the first-time-provisioning project.
# This script reads available server IPs and connects using the project's secure SSH key.

set -e

IP_FILE="../secrets/ips"
SSH_KEY=${SSH_KEY:-$HOME/.ssh/first-time-provisioning/id_ed25519}
SSH_CONFIG="../secrets/ssh_config"

if [ ! -f "$SSH_KEY" ]; then
    echo "❌ Error: SSH key not found at $SSH_KEY"
    exit 1
fi

if [ ! -f "$SSH_CONFIG" ]; then
    echo "❌ Error: SSH config not found at $SSH_CONFIG"
    exit 1
fi

# Ensure correct permissions
chmod 600 "$SSH_KEY"
chmod 600 "$SSH_CONFIG"

DEPLOYER_PASSWORD_FILE="../secrets/deployer_passwords"
PAM_TOKEN_FILE="../secrets/pam_tokens"

if [ ! -f "$IP_FILE" ]; then
    echo "❌ Error: $IP_FILE not found. Have you run 'make bootstrap'?"
    exit 1
fi


IPS=($(cat "$IP_FILE"))
COUNT=${#IPS[@]}

# Username for connection
DEPLOY_USER=${DEPLOY_USER:-deployer}

if [ "$COUNT" -eq 0 ]; then
    echo "❌ Error: No IPs found in $IP_FILE."
    exit 1
fi

if [ "$COUNT" -eq 1 ]; then
    IP=${IPS[0]}
    echo "🌐 Connecting to $IP..."
else
    echo "Found $COUNT servers:"
    for i in "${!IPS[@]}"; do
        echo "[$((i+1))] ${IPS[$i]}"
    done
    read -p "Select a server (1-$COUNT): " CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$COUNT" ]; then
        echo "❌ Invalid selection."
        exit 1
    fi
    IP=${IPS[$((CHOICE-1))]}
    echo "🌐 Connecting to $IP..."
fi

# Display passwords if available
if [ -f "../secrets/deployer_passwords" ]; then
    PASS=$(sed -n "$((CHOICE ? CHOICE : 1))p" "../secrets/deployer_passwords" | tr -d '\r\n' | xargs)
    if [ -n "$PASS" ]; then
        echo "🔑 Deployer Password: $PASS"
    fi
fi
if [ -f "../secrets/passwords" ]; then
    ROOT_PASS=$(sed -n "$((CHOICE ? CHOICE : 1))p" "../secrets/passwords" | tr -d '\r\n' | xargs)
    if [ -n "$ROOT_PASS" ]; then
        echo "🔑 Root Password: $ROOT_PASS"
    fi
fi

if [ -f "$PAM_TOKEN_FILE" ]; then
    PAM_SECRET=$(sed -n "$((CHOICE ? CHOICE : 1))p" "$PAM_TOKEN_FILE" | tr -d '\r\n' | xargs)
    if [ -n "$PAM_SECRET" ]; then
        if command -v oathtool >/dev/null 2>&1; then
            TOKEN=$(oathtool --base32 --totp "$PAM_SECRET")
            echo "🔐 Verification Code: $TOKEN"
        fi
    fi
fi

if [ -f "../secrets/ssh_key_passphrase" ]; then
    KEY_PASS=$(cat "../secrets/ssh_key_passphrase" | tr -d '\r\n')
    echo "🔑 SSH Key Passphrase: $KEY_PASS"
fi

# Connect using the project-specific SSH config
# 2026 Best Practice: Direct Key-Only access
ssh -F $SSH_CONFIG $DEPLOY_USER@$IP
