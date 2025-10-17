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

# The script expects a space-separated string of names.
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
  
  # Use the same name for the Docker secret and the Vaultwarden item
  DOCKER_SECRET_NAME="$name"
  VW_ITEM_NAME="$name"
  
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

  # 2. Get the content from the 'notes' field of the item
  echo "   📥 Retrieving content from the 'Notes' field..."
  SECRET_CONTENT=$(curl -s -X GET "${VW_URL}/api/ciphers/${CIPHER_ID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" | \
    jq -r '.notes')

  # Check if the notes field is empty or null
  if [ "${SECRET_CONTENT}" == "null" ] || [ -z "${SECRET_CONTENT}" ]; then
      echo "   ❌ The 'Notes' field for item '${VW_ITEM_NAME}' is empty or null. Skipping."
      continue
  fi

  # 3. Manage Docker secret
  echo "   🐳 Managing Docker secret..."
  if docker secret inspect "${DOCKER_SECRET_NAME}" > /dev/null 2>&1; then
    echo "      - Secret exists. Removing old version..."
    docker secret rm "${DOCKER_SECRET_NAME}"
  fi

  echo "${SECRET_CONTENT}" | docker secret create "${DOCKER_SECRET_NAME}" -
  echo "   🎉 Successfully created/updated Docker secret '${DOCKER_SECRET_NAME}'."
done

echo "-----------------------------------------------------"
echo "✅ All tasks completed."
