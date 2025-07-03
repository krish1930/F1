#!/bin/bash
# linux-run.sh with predefined values for krish

# Exit on any error
set -e

# Enable debugging output - this will print every command executed
set -x

# These environment variables will be populated by GitHub Actions secrets.
# We explicitly check if they are set.

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

./ngrok authtoken "$NGROK_AUTH_TOKEN" > /dev/null 2>&1

# Start ngrok in the background, logging all output to .ngrok.log.
stdbuf -oL ./ngrok tcp 22 > .ngrok.log 2>&1 &

echo "Waiting for ngrok to initialize and output connection details..."
sleep 20 # Increased sleep to 20 seconds, just in case 15s wasn't enough for some runs.

# --- NGROK URL EXTRACTION AND GITHUB ACTIONS OUTPUT ---

# FIRST CHECK: See if ngrok itself reported a failure in its log
if grep -q "command failed" .ngrok.log; then
  echo "NGROK_DEBUG: 'command failed' found in .ngrok.log. Exiting."
  echo "NGROK_DEBUG: Contents of .ngrok.log:"
  cat .ngrok.log # Print the log for debugging
  exit 6
fi

# SECOND CHECK: Look for the specific "To connect: ssh" line
NGROK_CONNECT_LINE=$(grep -m 1 "To connect: ssh" .ngrok.log)

if [[ -z "$NGROK_CONNECT_LINE" ]]; then
    echo "NGROK_DEBUG: 'To connect: ssh' line NOT found in .ngrok.log."
    echo "NGROK_DEBUG: This might mean ngrok didn't start correctly or didn't output the connection details as expected."
    echo "NGROK_DEBUG: Contents of .ngrok.log for debugging:"
    cat .ngrok.log # This is crucial for debugging
    exit 7
fi

# Extract the complete SSH connection string
EXTRACTED_SSH_URL=$(echo "$NGROK_CONNECT_LINE" | sed -E 's/.*(ssh [^ ]+@[^ ]+ -p [0-9]+).*/\1/')

if [[ -z "$EXTRACTED_SSH_URL" ]]; then
    echo "NGROK_DEBUG: Failed to extract SSH URL from the line: '$NGROK_CONNECT_LINE'"
    echo "NGROK_DEBUG: The sed regex might need adjustment if ngrok's output format has changed."
    exit 8
fi

echo ""
echo "=========================================="
echo "Successfully extracted Ngrok SSH URL: $EXTRACTED_SSH_URL"
echo "=========================================="

echo "::set-output name=ngrok_ssh_url::${EXTRACTED_SSH_URL}"

# --- END NGROK URL EXTRACTION AND GITHUB ACTIONS OUTPUT ---
