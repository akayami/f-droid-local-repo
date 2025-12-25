#!/bin/bash
set -e

# ==========================================
# F-Droid Repo Updater (Multi-Repo)
# ==========================================

# Ensure PATH includes standard locations
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

echo "Starting F-Droid Updater..."

# 1. Initialize & Configure Repo
CONFIG_FILE="/repo/config.yml"
REPOS_CONF="/repo/repos.conf"

# If config doesn't exist or is empty (result of 'touch'), write a clean config
if [ ! -s "$CONFIG_FILE" ]; then
    echo "Writing fresh F-Droid repo config..."
    
    # Sanitize Repo Name (strip leading/trailing quotes to avoid YAML errors)
    CLEAN_REPO_NAME=$(echo "$FDROID_REPO_NAME" | sed -e 's/^"//' -e 's/"$//')
    
    cat <<EOF > $CONFIG_FILE
repo_url: "http://example.com/fdroid/repo"
archive_url: "http://example.com/fdroid/archive"
repo_name: "$CLEAN_REPO_NAME"
keystore: "/repo/keystore.p12"
repo_keyalias: "fdroid"
keystorepass: "$FDROID_REPO_PASS"
keypass: "$FDROID_REPO_PASS"
accepted_formats: ["txt", "yml", "xml"]
EOF
fi

# Ensure keystore exists and is valid
KEYSTORE_FILE="/repo/keystore.p12"
if [ ! -f "$KEYSTORE_FILE" ] || [ ! -s "$KEYSTORE_FILE" ]; then
    echo "Generating new keystore (keystore.p12 is missing or empty)..."
    
    # We cannot rm the file because it is bind-mounted (Device or resource busy).
    # We must generate to a temp file and overwrite the content.
    TMP_KEYSTORE="/tmp/keystore.tmp"
    
    # Use CLEAN_REPO_NAME for CN as well
    CLEAN_REPO_NAME=$(echo "$FDROID_REPO_NAME" | sed -e 's/^"//' -e 's/"$//')
    
    keytool -genkeypair -v -keystore "$TMP_KEYSTORE" -alias fdroid -keyalg RSA -keysize 2048 -validity 10000 -storepass "$FDROID_REPO_PASS" -keypass "$FDROID_REPO_PASS" -dname "CN=$CLEAN_REPO_NAME, OU=F-Droid, O=F-Droid, L=Internet, ST=Internet, C=US"
    
    # Overwrite the mounted file with the new content
    cat "$TMP_KEYSTORE" > "$KEYSTORE_FILE"
    rm "$TMP_KEYSTORE"
    echo "Keystore generated and written to $KEYSTORE_FILE"
fi

# Ensure directories exist
mkdir -p /repo/repo

if [ ! -f "$REPOS_CONF" ]; then
    echo "ERROR: $REPOS_CONF not found. Please mount it in docker-compose.yml."
    exit 1
fi

while true; do
    echo "----------------------------------------"
    echo "Checking for updates at $(date)..."
    
    UPDATES_FOUND=false

    # Read repos.conf line by line
    while read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse line: repo asset [token_var]
        parts=($line)
        REPO_NAME="${parts[0]}"
        ASSET_PATTERN="${parts[1]}"
        TOKEN_VAR="${parts[2]}"
        
        # Validate token variable presence
        if [ -z "$TOKEN_VAR" ]; then
            echo "Skipping $REPO_NAME: Token variable is missing in repos.conf (MANDATORY)."
            continue
        fi
        
        # Resolve token value
        # 1. Try to read as environment variable
        RESOLVED_ENV_VAR="${!TOKEN_VAR}"
        
        if [ -n "$RESOLVED_ENV_VAR" ]; then
            REPO_TOKEN="$RESOLVED_ENV_VAR"
            # echo "  Using token from environment variable: $TOKEN_VAR"
        else
            # 2. Fallback: Use the string literal as the token
            REPO_TOKEN="$TOKEN_VAR"
            echo "  Note: '$TOKEN_VAR' not found as env var (or empty). Using as raw token."
        fi
        
        if [ -z "$REPO_TOKEN" ]; then
            echo "Skipping $REPO_NAME: Resolved token is empty."
            continue
        fi
        
        echo "Processing $REPO_NAME (Asset: $ASSET_PATTERN)..."
        
        # 2. Get Release Info (JSON)
        RELEASE_JSON=$(curl -s -H "Authorization: token $REPO_TOKEN" "https://api.github.com/repos/$REPO_NAME/releases/latest")
        
        # Extract Tag
        LATEST_TAG=$(echo "$RELEASE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tag_name', ''))")
        
        if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "None" ]; then
            echo "Error: Could not fetch latest tag for $REPO_NAME."
            # echo "$RELEASE_JSON" | head -n 5
            continue
        fi
        
        echo "  Latest version: $LATEST_TAG"
        
        # Determine target filename
        # We sanitize the repo name (replace / with _) to avoid directory issues
        SAFE_REPO_NAME=$(echo "$REPO_NAME" | tr '/' '_')
        TARGET_NAME="${SAFE_REPO_NAME}_${LATEST_TAG}.apk"
        TARGET_PATH="/repo/repo/$TARGET_NAME"
        
        if [ -f "$TARGET_PATH" ]; then
            echo "  Already have $TARGET_NAME. Skipping."
            continue
        fi
        
        echo "  New version found! Looking for asset '$ASSET_PATTERN'..."
        
        # Find asset URL
        ASSET_URL=$(echo "$RELEASE_JSON" | python3 -c "import sys, json; 
data = json.load(sys.stdin); 
print(next((a['url'] for a in data.get('assets', []) if a['name'] == '$ASSET_PATTERN'), ''))")
        
        if [ -z "$ASSET_URL" ]; then
             echo "  Error: Asset '$ASSET_PATTERN' not found in release $LATEST_TAG."
             continue
        fi
        
        echo "  Downloading asset..."
        
        # Secure Download Strategy
        REDIRECT_URL=$(curl -v -H "Authorization: token $REPO_TOKEN" -H "Accept: application/octet-stream" -w "%{redirect_url}" -o /dev/null "$ASSET_URL" 2>/dev/null)
        
        if [ -z "$REDIRECT_URL" ]; then
            # Fallback to Python
            python3 -c "
import urllib.request, shutil
req = urllib.request.Request('$ASSET_URL')
req.add_header('Authorization', 'token $REPO_TOKEN')
req.add_header('Accept', 'application/octet-stream')
with urllib.request.urlopen(req) as response, open('$TARGET_PATH', 'wb') as out_file:
    shutil.copyfileobj(response, out_file)
"
        else
            curl -fL "$REDIRECT_URL" -o "$TARGET_PATH"
        fi
        
        if [ -f "$TARGET_PATH" ]; then
            echo "  Download successful: $TARGET_NAME"
            UPDATES_FOUND=true
        else
            echo "  Download failed."
        fi
        
    done < "$REPOS_CONF"
    
    # Update Repo Index
    # Always run update to ensure index exists (even if repo is empty)
    if [ -d "/repo/repo" ]; then
        echo "Updating F-Droid index..."
        
        # We run from /repo (WORKDIR), where config.yml acts on local 'repo/' folder
        fdroid update -c --pretty
        
        echo "Index update complete."
    else
        echo "ERROR: /repo/repo directory missing."
    fi
    
    # Default refresh interval: 5 minutes (300 seconds)
    INTERVAL="${UPDATE_INTERVAL:-300}"
    echo "Sleeping for $INTERVAL seconds..."
    sleep "$INTERVAL"
done
