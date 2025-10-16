#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed

# --- Configuration ---
# Load from .env file if it exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Check for required variables
: "${VW_URL:?VW_URL is not set. Please set it in your .env file or environment.}"
: "${VW_CLIENT_ID:?VW_CLIENT_ID is not set.}"
: "${VW_CLIENT_SECRET:?VW_CLIENT_SECRET is not set.}"

# The script now expects a space-separated string of names.
# Example: "gemini_env_file wger_env_file"
SECRET_NAMES="$1"
if [ -z "${SECRET_NAMES}" ]; then
  echo "❌ Error: No secret names provided."
  echo "Usage: $0 \"gemini_env_file [wger_env_file]\""
  exit 1
fi

# --- Main Script ---

echo "🔐 Authenticating with Vaultwarden at ${VW_URL}..."
TOKEN_RESPONSE=$(curl -s -X POST "${VW_URL}/identity/connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${VW_CLIENT_ID}&client_secret=${VW_CLIENT_SECRET}&scope=api")

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r .access_token)

if [ "${ACCESS_TOKEN}" == "null" ] || [ -z "${ACCESS_TOKEN}" ]; then
  echo "❌ Failed to get access token. Response: ${TOKEN_RESPONSE}"
  exit 1
fi
echo "✅ Authentication successful."

# Loop through each name provided in the argument
for name in ${SECRET_NAMES}; do
  echo "-----------------------------------------------------"
  
  # Use the same name for all three variables
  DOCKER_SECRET_NAME="$name"
  VW_ITEM_NAME="$name"
  VW_ATTACHMENT_NAME="$name"
  
  echo "▶️  Processing Secret: '${name}'"

  # 1. Find the Cipher (Item) ID
  echo "   🔎 Searching for item named '${VW_ITEM_NAME}'..."
  CIPHER_ID=$(curl -s -X GET "${VW_URL}/api/ciphers" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" | \
    jq -r --arg ITEM_NAME "${VW_ITEM_NAME}" '.data[] | select(.name == $ITEM_NAME) | .id')

  if [ -z "${CIPHER_ID}" ]; then
    echo "   ❌ Could not find an item named '${VW_ITEM_NAME}'. Skipping."
    continue
  fi
  echo "   ✅ Found item with ID: ${CIPHER_ID}."

  # 2. Find the Attachment ID
  echo "   🔎 Searching for attachment named '${VW_ATTACHMENT_NAME}'..."
  ATTACHMENT_ID=$(curl -s -X GET "${VW_URL}/api/ciphers/${CIPHER_ID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" | \
    jq -r --arg ATTACHMENT_NAME "${VW_ATTACHMENT_NAME}" '.attachments[] | select(.fileName == $ATTACHMENT_NAME) | .id')

  if [ -z "${ATTACHMENT_ID}" ]; then
    echo "   ❌ Could not find an attachment named '${VW_ATTACHMENT_NAME}' in item '${VW_ITEM_NAME}'. Skipping."
    continue
  fi
  echo "   ✅ Found attachment with ID: ${ATTACHMENT_ID}."

  # 3. Download the attachment content
  echo "   📥 Downloading attachment content..."
  ATTACHMENT_CONTENT=$(curl -s -L -X GET "${VW_URL}/api/ciphers/${CIPHER_ID}/attachments/${ATTACHMENT_ID}/download" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")

  if [ -z "${ATTACHMENT_CONTENT}" ]; then
      echo "   ❌ Attachment content is empty. Cannot create secret. Skipping."
      continue
  fi

  # 4. Manage Docker secret
  echo "   🐳 Managing Docker secret..."
  if docker secret inspect "${DOCKER_SECRET_NAME}" > /dev/null 2>&1; then
    echo "      - Secret exists. Removing old version..."
    docker secret rm "${DOCKER_SECRET_NAME}"
  fi

  echo "${ATTACHMENT_CONTENT}" | docker secret create "${DOCKER_SECRET_NAME}" -
  echo "   🎉 Successfully created/updated Docker secret '${DOCKER_SECRET_NAME}'."
done

echo "-----------------------------------------------------"
echo "✅ All tasks completed."
