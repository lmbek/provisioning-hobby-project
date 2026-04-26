#!/bin/bash

# Script to establish multiplexed SSH tunnels for all provisioned servers.
# This ensures that subsequent SSH/Ansible commands can bypass MFA prompts.

set -e

IP_FILE="state/ips"
SSH_CONFIG="state/ssh_config"
PASS_FILE="state/deployer_passwords"
PAM_FILE="state/pam_tokens"
SSH_PASSPHRASE_FILE="state/ssh_key_passphrase"

if [ ! -f "$IP_FILE" ]; then
    echo "❌ Error: $IP_FILE not found."
    exit 1
fi

mfa_auth() {
    local ip=$1
    local password=$2
    local pam_secret=$3
    local ssh_passphrase=$4
    
    # Check if tunnel already exists
    if ssh -F "$SSH_CONFIG" -O check "deployer@$ip" 2>/dev/null; then
        echo "✅ Tunnel to $ip already active."
        return 0
    fi

    echo "🌐 Establishing tunnel to $ip..."
    local totp_code=$(oathtool --base32 --totp "$pam_secret")
    
    export EXPECT_PASSWORD="$password"
    export EXPECT_TOTP="$totp_code"
    export EXPECT_IP="$ip"
    export EXPECT_SSH_CONFIG="$SSH_CONFIG"
    export EXPECT_SSH_PASSPHRASE="$ssh_passphrase"
    
    expect <<'EOF'
        log_user 0
        set timeout 30
        set password $env(EXPECT_PASSWORD)
        set totp $env(EXPECT_TOTP)
        set ip $env(EXPECT_IP)
        set ssh_config $env(EXPECT_SSH_CONFIG)
        set ssh_passphrase $env(EXPECT_SSH_PASSPHRASE)
        
        spawn ssh -F $ssh_config deployer@$ip "true"
        expect {
            -re "Enter passphrase for key|Passphrase for key" {
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
                puts "\n❌ Error: Permission denied (check passwords/MFA)"
                exit 1
            }
            timeout {
                puts "\n❌ Error: Connection timeout"
                exit 1
            }
            eof
        }
EOF
}

IPS=($(cat "$IP_FILE"))
SSH_PASSPHRASE=$(cat "$SSH_PASSPHRASE_FILE" | tr -d '\r\n')

echo "🔐 Opening secure 4-factor tunnels for all servers..."

for i in "${!IPS[@]}"; do
    IP=${IPS[$i]}
    PASSWORD=$(sed -n "$((i+1))p" "$PASS_FILE" | tr -d '\r\n')
    PAM_SECRET=$(sed -n "$((i+1))p" "$PAM_FILE" | tr -d '\r\n')

    mfa_auth "$IP" "$PASSWORD" "$PAM_SECRET" "$SSH_PASSPHRASE"
done

echo "✅ All tunnels established."
