#!/bin/bash
# setup.sh
# Creates empty configuration files so Docker doesn't create directories in their place.

touch config.yml
touch keystore.p12

if [ ! -f repos.conf ]; then
    echo "Creating defaults repos.conf..."
    echo "# owner/repo asset_pattern TOKEN_VAR" > repos.conf
fi

echo "Files prepared. You can now run 'docker-compose up -d --build'"
