#!/bin/bash
# linux-run.sh with predefined values for krish

# Exit on any error
set -e

# Predefined environment variables (these will be overridden by GitHub secrets passed in blank.yml)
# It's good practice to keep them for local testing, but remember secrets take precedence.
LINUX_USER_PASSWORD="${LINUX_USER_PASSWORD:-krish}" # Use default if not set by env
NGROK_AUTH_TOKEN="${NGROK_AUTH_TOKEN:-YOUR_DEFAULT_NGROK_TOKEN_HERE}" # Use default if not set by env
LINUX_USERNAME="${LINUX_USERNAME:-krish}" # Use default if not set by env
LINUX_MACHINE_NAME="${LINUX_MACHINE_NAME:-krish}" # Use default if not set by env

# Check for required environment variables (these will typically be set by GitHub Actions secrets)
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

# Start ngrok in the background and log to .ngrok.log
./ngrok tcp 22 --log ".ngrok.log" &

# Wait for ngrok to initialize and write the tunnel URL to the log
echo "Waiting for ngrok to initialize..."
sleep 15 # Increased sleep to ensure URL is written

# Check for errors in ngrok log
if grep -q "command failed" .ngrok.log; then
  echo "Error: ngrok failed to start. Log content:"
  cat .ngrok.log # Print log for debugging
  exit 6
fi

# --- START OF MODIFIED/ADDED CODE FOR NGROK URL EXTRACTION ---

# This part is crucial for passing the URL to GitHub Actions

# Get the "To connect" line from the log. Use '-m 1' for the first match.
NGROK_CONNECT_LINE=$(grep -m 1 "To connect: ssh" .ngrok.log)

if [[ -z "$NGROK_CONNECT_LINE" ]]; then
    echo "Error: 'To connect: ssh' line not found in .ngrok.log. Ngrok may not have fully started or outputted the URL."
    echo "Contents of .ngrok.log for debugging:"
    cat .ngrok.log
    exit 7 # Exit with a new error code to differentiate
fi

# Extract the SSH URL using sed. This regex is robust for the format.
# Example: "ssh ***@4.tcp.us-cal-1.ngrok.io -p 12767"
EXTRACTED_SSH_URL=$(echo "$NGROK_CONNECT_LINE" | sed -E 's/.*(ssh [^ ]+@[^ ]+ -p [0-9]+).*/\1/')

if [[ -z "$EXTRACTED_SSH_URL" ]]; then
    echo "Error: Failed to extract SSH URL from the 'To connect' line: $NGROK_CONNECT_LINE"
    exit 8 # Exit with a new error code
fi

# Original echo for visual confirmation in the workflow logs
echo ""
echo "=========================================="
echo "To connect: $EXTRACTED_SSH_URL"
echo "=========================================="

# >>> THIS IS THE CRITICAL LINE TO PASS THE URL TO BLANK.YML <<<
echo "::set-output name=ngrok_ssh_url::${EXTRACTED_SSH_URL}"

# --- END OF MODIFIED/ADDED CODE ---

# No need for the old NGROK_URL/SSH_ADDRESS variables and logic anymore,
# as EXTRACTED_SSH_URL now holds the correct string.
# Also removed the old exit 7 because the new checks handle it more granularly.

# Keep the script running (this usually isn't necessary in linux-ssh.sh
# as blank.yml has the sleep 6h, but if it was meant to keep this script alive, keep it)
# while true; do sleep 3600; done # If this was intended for a long-running service, otherwise remove.
