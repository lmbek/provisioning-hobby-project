#!/bin/bash

set -e

APP_NAME=helloworld
# SSH_KEY and SSH_PORT should be passed from Makefile. Defaulting if not set.
SSH_KEY=${SSH_KEY:-$HOME/.ssh/first-time-provisioning/id_ed25519}
SSH_PORT=${SSH_PORT:-22}
SSH_CONFIG="secrets/ssh_config"

IP_FILE=secrets/ips
PASS_FILE=secrets/deployer_passwords
PAM_FILE=secrets/pam_tokens
SSH_PASSPHRASE_FILE=secrets/ssh_key_passphrase

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

mfa_auth() {
    local ip=$1
    local password=$2
    local pam_secret=$3
    local ssh_passphrase=$4
    
    # Generate TOTP code
    local totp_code=$(oathtool --base32 --totp "$pam_secret")
    
    # We use expect to handle the multiple prompts non-interactively
    # We pass variables as environment variables to avoid shell escaping issues in the expect script
    export EXPECT_PASSWORD="$password"
    export EXPECT_TOTP="$totp_code"
    export EXPECT_IP="$ip"
    export EXPECT_SSH_CONFIG="$SSH_CONFIG"
    export EXPECT_SSH_PASSPHRASE="$ssh_passphrase"
    
    expect <<'EOF'
        set timeout 20
        set password $env(EXPECT_PASSWORD)
        set totp $env(EXPECT_TOTP)
        set ip $env(EXPECT_IP)
        set ssh_config $env(EXPECT_SSH_CONFIG)
        set ssh_passphrase $env(EXPECT_SSH_PASSPHRASE)
        
        spawn ssh -F $ssh_config deployer@$ip "true"
        expect {
            "Enter passphrase for key" {
                send "$ssh_passphrase\r"
                exp_continue
            }
            "Password:" {
                send "$password\r"
                exp_continue
            }
            "Verification code:" {
                send "$totp\r"
                exp_continue
            }
            "Permission denied" {
                exit 1
            }
            timeout {
                exit 1
            }
            eof
        }
EOF
}

echo "🔧 building app..."
go mod tidy
GOOS=linux GOARCH=amd64 go build -o $APP_NAME ./app

# Read IPs into an array
IPS=($(cat $IP_FILE))

for i in "${!IPS[@]}"; do
    IP=${IPS[$i]}
    echo "🌐 Processing server: $IP"

    # Read password and pam secret for this instance
    PASSWORD=$(sed -n "$((i+1))p" $PASS_FILE | tr -d '\r\n')
    PAM_SECRET=$(sed -n "$((i+1))p" $PAM_FILE | tr -d '\r\n')
    SSH_PASSPHRASE=$(cat $SSH_PASSPHRASE_FILE | tr -d '\r\n')

    echo "⏳ waiting for SSH to be ready on $IP (port $SSH_PORT)..."
    until nc -zvw3 $IP $SSH_PORT > /dev/null 2>&1; do
        echo "..."
        sleep 5
    done
    echo "🚀 SSH is up!"
    
    # Establish a multiplexed connection using 3-factor authentication
    echo "🔐 Establishing secure 4-factor tunnel..."
    mfa_auth "$IP" "$PASSWORD" "$PAM_SECRET" "$SSH_PASSPHRASE" > /dev/null

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
            printf '[Unit]\nDescription=Helloworld Go App\nAfter=network.target\n\n[Service]\nExecStart=/opt/app/helloworld\nUser=deployer\nGroup=deployer\nEnvironmentFile=/etc/helloworld.env\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n' | sudo tee /etc/systemd/system/helloworld.service > /dev/null
            sudo systemctl daemon-reload
            sudo systemctl enable helloworld
        fi
        sudo systemctl restart helloworld
    "
    echo "✅ deployed to http://$IP:$APP_PORT"
done