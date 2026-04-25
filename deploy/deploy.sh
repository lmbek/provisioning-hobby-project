#!/bin/bash

set -e

APP_NAME=helloworld
# SSH_KEY should be passed from Makefile. Defaulting if not set.
SSH_KEY=${SSH_KEY:-$HOME/.ssh/first-time-provisioning/id_ed25519}

if [ ! -f .ip ]; then
    echo "❌ Error: .ip file not found."
    echo "This usually means you haven't created the infrastructure yet."
    echo "Please run 'make bootstrap' to create the server first."
    exit 1
fi

IP=$(cat .ip)

# NEW: Remove old host keys to prevent "REMOTE HOST IDENTIFICATION HAS CHANGED" error
# This happens often when destroying and recreating servers with the same IP
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" > /dev/null 2>&1 || true

echo "⏳ waiting for SSH to be ready on $IP..."
until nc -zvw3 $IP 22 > /dev/null 2>&1; do
    echo "..."
    sleep 5
done
echo "🚀 SSH is up!"

# Ensure SSH key has correct permissions (this should work since it's in ~/.ssh/)
chmod 600 $SSH_KEY

echo "🔧 building app..."
go mod tidy
GOOS=linux GOARCH=amd64 go build -o $APP_NAME ./app

# Ensure target directory exists and has correct permissions
# We do this via SSH before SCPing
echo "📁 preparing server directory..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$IP "mkdir -p /opt/app"

echo "🚀 uploading..."
scp -i $SSH_KEY -o StrictHostKeyChecking=no $APP_NAME root@$IP:/opt/app/

echo "🔁 restarting service..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$IP "
    if [ ! -f /etc/systemd/system/helloworld.service ]; then
        echo 'Creating systemd service...'
        printf '[Unit]\nDescription=Helloworld Go App\nAfter=network.target\n\n[Service]\nExecStart=/opt/app/helloworld\nEnvironmentFile=/etc/helloworld.env\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/helloworld.service
        systemctl daemon-reload
        systemctl enable helloworld
    fi
    systemctl restart helloworld
"

echo "✅ deployed to http://$IP:8080"