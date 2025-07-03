#!/bin/bash
# linux-run.sh with predefined values for krish

# Exit on any error
set -e

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
# Remove old log file if exists to ensure a clean capture
rm -f .ngrok.log

# Set ngrok authtoken
./ngrok authtoken "$NGROK_AUTH_TOKEN" > /dev/null 2>&1

# Start ngrok in the background, logging all output (stdout and stderr) to .ngrok.log.
# 'stdbuf -oL' forces line buffering, which helps ensure the "To connect" line is written promptly.
stdbuf -oL ./ngrok tcp 22 > .ngrok.log 2>&1 &

echo "Waiting for ngrok to initialize and output connection details..."
sleep 15 # Give ngrok sufficient time to establish the tunnel and write to its log file.

# Check for common ngrok startup failures in its log
if grep -q "command failed" .ngrok.log; then
  echo "Error: ngrok failed to start or encountered a critical error. Log content:"
  cat .ngrok.log # Print the log for debugging
  exit 6
fi

# --- NGROK URL EXTRACTION AND GITHUB ACTIONS OUTPUT ---

# Get the "To connect" line from the ngrok log file.
# '-m 1' ensures only the first matching line is returned.
NGROK_CONNECT_LINE=$(grep -m 1 "To connect: ssh" .ngrok.log)

if [[ -z "$NGROK_CONNECT_LINE" ]]; then
    echo "Error: 'To connect: ssh' line not found in .ngrok.log."
    echo "This might mean ngrok didn't start correctly, or didn't output the connection details as expected."
    echo "Contents of .ngrok.log for debugging:"
    cat .ngrok.log
    exit 7 # Exit with a specific error code
fi

# Extract the complete SSH connection string (e.g., "ssh user@host -p port")
# using a robust sed regex.
# [^ ]+ matches one or more non-space characters.
EXTRACTED_SSH_URL=$(echo "$NGROK_CONNECT_LINE" | sed -E 's/.*(ssh [^ ]+@[^ ]+ -p [0-9]+).*/\1/')

if [[ -z "$EXTRACTED_SSH_URL" ]]; then
    echo "Error: Failed to extract the SSH URL from the line: '$NGROK_CONNECT_LINE'"
    echo "The regex might need adjustment if ngrok's output format has changed."
    exit 8 # Exit with a specific error code
fi

# Echo the extracted URL for visibility in the GitHub Actions workflow logs
echo ""
echo "=========================================="
echo "Successfully extracted Ngrok SSH URL: $EXTRACTED_SSH_URL"
echo "=========================================="

# Pass the extracted SSH URL as an output variable to the GitHub Actions workflow.
# This is crucial for the 'blank.yml' to access it.
echo "::set-output name=ngrok_ssh_url::${EXTRACTED_SSH_URL}"

# --- END NGROK URL EXTRACTION AND GITHUB ACTIONS OUTPUT ---

# The 'sleep 6h' to keep the VM alive is handled in 'blank.yml',
# so no need for a long-running loop here.
