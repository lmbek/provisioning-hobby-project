#!/bin/bash

set -e

APP_NAME=helloworld
# SSH_KEY should be passed from Makefile. Defaulting if not set.
SSH_KEY=${SSH_KEY:-$HOME/.ssh/first-time-provisioning/id_ed25519}
SSH_CONFIG="secrets/ssh_config"

IP_FILE=secrets/ips

if [ ! -f $IP_FILE ]; then
    echo "❌ Error: $IP_FILE file not found."
    echo "This usually means you haven't created the infrastructure yet."
    echo "Please run 'make bootstrap' to create the server first."
    exit 1
fi

if [ ! -f $SSH_CONFIG ]; then
    echo "❌ Error: $SSH_CONFIG file not found. Run 'make keys' first."
    exit 1
fi

# SSH Command with config
SSH="ssh -F $SSH_CONFIG"
SCP="scp -F $SSH_CONFIG"

# Ensure SSH key has correct permissions
chmod 600 $SSH_KEY

echo "🔧 building app..."
go mod tidy
GOOS=linux GOARCH=amd64 go build -o $APP_NAME ./app

# Read IPs into an array
IPS=($(cat $IP_FILE))

for IP in "${IPS[@]}"; do
    echo "🌐 Processing server: $IP"

    echo "⏳ waiting for SSH to be ready on $IP..."
    until nc -zvw3 $IP 22 > /dev/null 2>&1; do
        echo "..."
        sleep 5
    done
    echo "🚀 SSH is up!"
    
    echo "⏳ waiting for cloud-init to finish on $IP..."
    $SSH deployer@$IP "until [ -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done"

    # Stop service if it exists to unlock the binary for overwrite
    echo "⏹ stopping service on $IP (if running)..."
    $SSH deployer@$IP "sudo systemctl stop helloworld 2>/dev/null || true"

    # Ensure target directory exists and write environment file
    echo "📁 preparing server directory and configuration..."
    $SSH deployer@$IP "
        sudo mkdir -p /opt/app/templates
        sudo mkdir -p /opt/app/static/css
        sudo chown -R deployer:deployer /opt/app
        printf \"APP_PORTS=$APP_PORTS\n\" | sudo tee /etc/helloworld.env > /dev/null
    "

    echo "🚀 uploading to $IP..."
    $SCP $APP_NAME deployer@$IP:/opt/app/
    $SCP app/templates/index.html deployer@$IP:/opt/app/templates/
    $SCP -r app/static deployer@$IP:/opt/app/

    echo "🔁 restarting service on $IP..."
    $SSH deployer@$IP "
        # Ensure the binary has permissions to bind to privileged ports after upload
        sudo setcap 'cap_net_bind_service=+ep' /opt/app/helloworld
        
        if [ ! -f /etc/systemd/system/helloworld.service ]; then
            echo 'Creating systemd service...'
            printf '[Unit]\nDescription=Helloworld Go App\nAfter=network.target\n\n[Service]\nExecStart=/opt/app/helloworld\nEnvironmentFile=/etc/helloworld.env\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n' | sudo tee /etc/systemd/system/helloworld.service > /dev/null
            sudo systemctl daemon-reload
            sudo systemctl enable helloworld
        fi
        sudo systemctl restart helloworld
    "
    echo "✅ deployed to http://$IP:$APP_PORT"
done