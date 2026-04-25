#!/bin/bash

set -e

APP_NAME=helloworld
IP=$(cat .ip)

echo "🔧 building app..."
GOOS=linux GOARCH=amd64 go build -o $APP_NAME ./app

echo "🚀 uploading..."
scp $APP_NAME root@$IP:/opt/app/

echo "🔁 restarting service..."
ssh root@$IP "systemctl restart helloworld || true"

echo "✅ deployed to http://$IP:8080"