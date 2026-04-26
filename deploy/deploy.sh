#!/bin/bash

set -e

APP_NAME=helloworld
# SSH_KEY should be passed from Makefile. Defaulting if not set.
SSH_KEY=${SSH_KEY:-$HOME/.ssh/first-time-provisioning/id_ed25519}

IP_FILE=secrets/ips

if [ ! -f $IP_FILE ]; then
    echo "❌ Error: $IP_FILE file not found."
    echo "This usually means you haven't created the infrastructure yet."
    echo "Please run 'make bootstrap' to create the server first."
    exit 1
fi

# Ensure SSH key has correct permissions
chmod 600 $SSH_KEY

echo "🔧 building app..."
go mod tidy
GOOS=linux GOARCH=amd64 go build -o $APP_NAME ./app

# Read IPs into an array
IPS=($(cat $IP_FILE))

for IP in "${IPS[@]}"; do
    echo "🌐 Processing server: $IP"

    # Remove old host keys to prevent "REMOTE HOST IDENTIFICATION HAS CHANGED" error
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" > /dev/null 2>&1 || true

    echo "⏳ waiting for SSH to be ready on $IP..."
    until nc -zvw3 $IP 22 > /dev/null 2>&1; do
        echo "..."
        sleep 5
    done
    echo "🚀 SSH is up!"

    # Stop service if it exists to unlock the binary for overwrite
    echo "⏹ stopping service on $IP (if running)..."
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$IP "systemctl stop helloworld 2>/dev/null || true"

    # Ensure target directory exists and write environment file
    echo "📁 preparing server directory and configuration..."
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$IP "
        mkdir -p /opt/app/templates
        mkdir -p /opt/app/static/css
        printf \"APP_PORTS=$APP_PORTS\n\" > /etc/helloworld.env
    "

    echo "🚀 uploading to $IP..."
    scp -i $SSH_KEY -o StrictHostKeyChecking=no $APP_NAME root@$IP:/opt/app/
    scp -i $SSH_KEY -o StrictHostKeyChecking=no app/templates/index.html root@$IP:/opt/app/templates/
    scp -r -i $SSH_KEY -o StrictHostKeyChecking=no app/static root@$IP:/opt/app/

    echo "🔁 restarting service on $IP..."
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$IP "
        # Ensure the binary has permissions to bind to privileged ports after upload
        setcap 'cap_net_bind_service=+ep' /opt/app/helloworld
        
        if [ ! -f /etc/systemd/system/helloworld.service ]; then
            echo 'Creating systemd service...'
            printf '[Unit]\nDescription=Helloworld Go App\nAfter=network.target\n\n[Service]\nExecStart=/opt/app/helloworld\nEnvironmentFile=/etc/helloworld.env\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/helloworld.service
            systemctl daemon-reload
            systemctl enable helloworld
        fi
        systemctl restart helloworld
    "
    echo "✅ deployed to http://$IP:$APP_PORT"
done