# Dockerized F-Droid Repository Server

A self-hosted, Docker-based F-Droid repository that automatically fetches APKs from GitHub releases and serves them.

## Features

- **Multi-Repository Support**: Fetch APKs from multiple GitHub repositories.
- **Automatic Updates**: Periodically checks for new releases (every hour).
- **Flexible Authentication**: Support for individual GitHub tokens per repository (via environment variables or raw tokens).
- **Customizable**: Configure the repository name and credentials easily.
- **Multi-Instance Ready**: Run multiple independent instances on the same machine.

## Setup

### 1. Configuration (`repos.conf`)

Create a `repos.conf` file in the project root to list the repositories you want to track.

**Format:**
```
owner/repo asset_pattern TOKEN_SOURCE
```

- **owner/repo**: The GitHub repository (e.g., `username/my-app`).
- **asset_pattern**: The filename pattern to match in releases (e.g., `app-release.apk`).
- **TOKEN_SOURCE**: 
    - A reference to an environment variable name (e.g., `CR_PAT`).
    - OR a raw GitHub Personal Access Token (e.g., `ghp_...`).

**Example `repos.conf`:**
```text
# Use an env var defined in docker-compose.yml
username/my-app app-release.apk CR_PAT

# Use a raw token directly
my-org/private-app app-release.apk ghp_SecretToken123
```
### 3. Signing Key (Keystore)

The repository needs a cryptographic signing key to sign the F-Droid index. You have two options:

#### Option A: Automatic Generation (Recommended for testing)
If you do not provide a `keystore.p12`, the system will **automatically generate one** for you on the first run.
- **Algorithm**: RSA 2048-bit
- **Validity**: 10,000 days (~27 years)
- **Subject**: `CN=<FDROID_REPO_NAME>, OU=F-Droid, O=F-Droid...`
- **Password**: Uses the `FDROID_REPO_PASS` environment variable.

#### Option B: Manual Generation (Recommended for production)
If you want control over the key (e.g., using your own organization details), generate it manually **on the server** (or copy it there).

```bash
# 1. Set the password env var
export FDROID_REPO_PASS="your_secure_password"

# 2. Generate the keystore
keytool -genkeypair -v -keystore keystore.p12 \
  -alias fdroid -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$FDROID_REPO_PASS" -keypass "$FDROID_REPO_PASS" \
  -dname "CN=My Repo, OU=My Org, O=My Company, L=City, ST=State, C=US"
```

*Note: This key signs the **repository index**, verifying that the list of apps comes from your server. It is separate from the keys used to sign individual APKs.*



### 3. Docker Compose (`docker-compose.yml`)

Configure your environment variables in `docker-compose.yml`.

- **FDROID_REPO_NAME**: The name of your F-Droid repository (default: "My F-Droid Repo").
- **FDROID_REPO_PASS**: Password for the keystore (used for signing APKs).
- **UPDATE_INTERVAL**: Time in seconds between update checks (default: 300).
- **Token Variables**: Define any environment variables you referenced in `repos.conf`.

**Example:**
```yaml
services:
  worker:
    environment:
      - FDROID_REPO_NAME="My Custom App Store"
      - FDROID_REPO_PASS=mysecretpassword
      - CR_PAT=${CR_PAT} # Pass the host env var or set it here
```

## Usage

### 4. Initialize Files
Run the setup script to create necessary configuration files (prevents Docker from creating directories in their place):
```bash
./setup.sh
```

### 5. Start Services
Start the services:

```bash
docker-compose up -d --build
```

This will start two containers:
1.  **worker**: Downloads APKs and updates the F-Droid index.
2.  **web**: Serves the repository files via Nginx.

### Accessing the Repository

The repository is served at:
`http://localhost:8888/fdroid/repo`

You can add this URL to your F-Droid client on Android by scanning the QR code (if you generate one) or manually entering the address.

## Directory Structure

- `data/`: Stores the downloaded APKs and the F-Droid repository index (persisted).
- `config.yml`: F-Droid server configuration (auto-generated/injected).
- `keystore.p12`: Signing keystore (persisted).
- `repos.conf`: Your repository list.

## Logs

Check the logs to see the update process:

```bash
# Note: The container name includes the directory name (e.g. f-droid-local-worker-1)
docker logs -f f-droid-local-worker-1
```
