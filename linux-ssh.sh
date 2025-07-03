#!/bin/bash
# linux-run.sh with predefined values for krish

# Exit on any error
set -e

# Predefined environment variables
LINUX_USER_PASSWORD="krish"
NGROK_AUTH_TOKEN="2zJgnsgGG3PTixaZZBAq4pEpBly_6qF99CKTjXTxC8tCMLg1D"
LINUX_USERNAME="krish"
LINUX_MACHINE_NAME="krish"

# Check for required environment variables
if [[ -z "$NGROK_AUTH_TOKEN" ]]; then
  echo "Error: NGROK_AUTH_TOKEN is not set"
  exit 2
fi

if [[ -z "$LINUX_USER_PASSWORD" ]]; then
  echo "Error: LINUX_USER_PASSWORD is not set for user: $LINUX_USERNAME"
  exit 3
fi

if [[ -z "$LINUX_USERNAME" ]]; then
  echo "Error: LINUX_USERNAME is not set"
  exit 4
fi

if [[ -z "$LINUX_MACHINE_NAME" ]]; then
  echo "Error: LINUX_MACHINE_NAME is not set"
  exit 5
fi

echo "### Creating user: $LINUX_USERNAME ###"
# Create user with home directory and add to sudo group
sudo useradd -m -s /bin/bash "$LINUX_USERNAME"
sudo usermod -aG sudo "$LINUX_USERNAME"
echo "$LINUX_USERNAME:$LINUX_USER_PASSWORD" | sudo chpasswd

# Set hostname
sudo hostnamectl set-hostname "$LINUX_MACHINE_NAME"

echo "### Installing ngrok ###"
# Download and install the latest ngrok version
wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip
unzip -o ngrok-v3-stable-linux-amd64.zip
chmod +x ./ngrok
rm ngrok-v3-stable-linux-amd64.zip

echo "### Starting ngrok proxy for port 22 ###"
# Remove old log file if exists
rm -f .ngrok.log

# Set ngrok authtoken
./ngrok authtoken "$NGROK_AUTH_TOKEN" > /dev/null 2>&1

# Start ngrok in the background
./ngrok tcp 22 --log ".ngrok.log" &

# Wait for ngrok to initialize
sleep 10

# Check for errors in ngrok log
if grep -q "command failed" .ngrok.log; then
  echo "Error: ngrok failed to start"
  cat .ngrok.log
  exit 6
fi

# Extract and display SSH connection details
NGROK_URL=$(grep -o -E "tcp://(.+)" .ngrok.log | head -1)
if [[ -n "$NGROK_URL" ]]; then
  SSH_ADDRESS=$(echo "$NGROK_URL" | sed "s/tcp:\/\//ssh $LINUX_USERNAME@/" | sed "s/:/ -p /")
  echo ""
  echo "=========================================="
  echo "To connect: $SSH_ADDRESS"
  echo "=========================================="
else
  echo "Error: Could not retrieve ngrok URL"
  exit 7
fi
