FROM python:3.11-slim

# 1. Install System Dependencies
# - OpenJDK: Required for jarsigner/keytool (APK signing)
# - git, curl, wget: Utilities
# - aapt: Android Asset Packaging Tool (often needed by fdroidserver)
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    git \
    curl \
    wget \
    unzip \
    apksigner \
    && rm -rf /var/lib/apt/lists/*

# 2. Install F-Droid Server & Androguard
# We install directly into the system environment
RUN pip install --no-cache-dir fdroidserver androguard

# 3. Create Repo Directory
WORKDIR /repo

# 4. Fake Android SDK (Crucial for fdroidserver)
# fdroidserver insists on finding aapt/apksigner in ANDROID_HOME/build-tools/VERSION/
RUN mkdir -p /opt/android-sdk/build-tools/33.0.0 \
    && ln -s /usr/bin/aapt /opt/android-sdk/build-tools/33.0.0/aapt \
    && ln -s /usr/bin/apksigner /opt/android-sdk/build-tools/33.0.0/apksigner

ENV ANDROID_HOME=/opt/android-sdk

# 5. Set Environment
# Ensure UTF-8 for encoding issues
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 5. Default Command (can be overridden by docker-compose)
CMD ["fdroid", "update", "-c"]
