#!/bin/bash
# linux-run.sh with predefined values for krish

# Exit on any error
set -e

# Enable debugging output - this will print every command executed
set -x

# Check for required environment variables
if [[ -z "$NGROK_AUTH_TOKEN" ]]; then
  echo "Error: NGROK_AUTH_TOKEN is not set. Please add it to GitHub repository secrets."
  exit 2
fi

if [[ -z "$LINUX_USER_PASSWORD" ]]; then
  echo "Error: LINUX_USER_PASSWORD is not set for user: $LINUX_USERNAME. Please add it to GitHub repository secrets."
  exit 3
fi

if [[ -z "$LINUX_USERNAME" ]]; then
  echo "Error: LINUX_USERNAME is not set. Please add it to GitHub repository secrets."
  exit 4
fi

if [[ -z "$LINUX_MACHINE_NAME" ]]; then
  echo "Error: LINUX_MACHINE_NAME is not set. Please add it to GitHub repository secrets."
  exit 5
fi

echo "### Creating user: $LINUX_USERNAME ###"
sudo useradd -m -s /bin/bash "$LINUX_USERNAME"
sudo usermod -aG sudo "$LINUX_USERNAME"
echo "$LINUX_USERNAME:$LINUX_USER_PASSWORD" | sudo chpasswd

# Set hostname
sudo hostnamectl set-hostname "$LINUX_MACHINE_NAME"

echo "### Installing ngrok ###"
wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip
unzip -o ngrok-v3-stable-linux-amd64.zip
chmod +x ./ngrok
rm ngrok-v3-stable-linux-amd64.zip

echo "### Starting ngrok proxy for port 22 ###"
rm -f .ngrok.log
./ngrok authtoken "$NGROK_AUTH_TOKEN"
stdbuf -oL ./ngrok tcp 22 > .ngrok.log 2>&1 &

# Give ngrok time to start and log the info
echo "Waiting for ngrok to output connection string..."
for i in {1..15}; do
  sleep 2
  NGROK_CONNECT_LINE=$(grep -m 1 "To connect: ssh" .ngrok.log || true)
  if [[ -n "$NGROK_CONNECT_LINE" ]]; then
    break
  fi
done

if [[ -z "$NGROK_CONNECT_LINE" ]]; then
  echo "ERROR: Could not find 'To connect: ssh' line in ngrok log."
  cat .ngrok.log
  exit 6
fi

# Extract the SSH connection line
EXTRACTED_SSH_URL=$(echo "$NGROK_CONNECT_LINE" | sed -E 's/.*(ssh [^ ]+@[^ ]+ -p [0-9]+).*/\1/')

if [[ -z "$EXTRACTED_SSH_URL" ]]; then
  echo "ERROR: Failed to extract SSH URL from log line: '$NGROK_CONNECT_LINE'"
  exit 7
fi

echo ""
echo "=========================================="
echo "Successfully extracted Ngrok SSH URL: $EXTRACTED_SSH_URL"
echo "=========================================="

# GitHub Actions output
echo "::set-output name=ngrok_ssh_url::${EXTRACTED_SSH_URL}"
