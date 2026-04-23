#!/bin/bash
# =============================================================================
# nexus-setup.sh — Configure Nexus Docker repository after first boot
# =============================================================================

set -e

NEXUS_URL="http://192.168.56.20:8081"
NEW_PASSWORD="admin123"

echo "=== Waiting for Nexus to be ready ==="
until curl -sf "${NEXUS_URL}/service/rest/v1/status" > /dev/null 2>&1; do
    echo "  Nexus not ready yet, waiting 10s..."
    sleep 10
done
echo "  Nexus is ready!"

echo ""
echo "=== Checking admin password ==="
if curl -sf -u "admin:${NEW_PASSWORD}" "${NEXUS_URL}/service/rest/v1/status" > /dev/null; then
    echo "  Password is already '${NEW_PASSWORD}'. Skipping reset."
else
    echo "  Retrieving initial admin password..."
    if ! docker exec nexus test -f /nexus-data/admin.password; then
        echo "  ERROR: admin.password file missing and 'admin123' doesn't work."
        echo "  Did you change the password to something else?"
        exit 1
    fi
    INIT_PASSWORD=$(docker exec nexus cat /nexus-data/admin.password)
    
    echo "  Changing admin password..."
    curl -sf -X PUT "${NEXUS_URL}/service/rest/v1/security/users/admin/change-password" \
        -H "Content-Type: text/plain" \
        -u "admin:${INIT_PASSWORD}" \
        -d "${NEW_PASSWORD}"
    echo "  Admin password changed to '${NEW_PASSWORD}'."
fi

echo ""
echo "=== Creating Docker hosted repository 'docker-private' on port 8082 ==="
curl -sf -X POST "${NEXUS_URL}/service/rest/v1/repositories/docker/hosted" \
    -H "Content-Type: application/json" \
    -u "admin:${NEW_PASSWORD}" \
    -d '{
        "name": "docker-private",
        "online": true,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true,
            "writePolicy": "ALLOW"
        },
        "docker": {
            "v1Enabled": false,
            "forceBasicAuth": true,
            "httpPort": 8082
        }
    }' || echo "  Repository already exists or unable to create (ignoring)."
echo "  Docker repository configured."

echo ""
echo "=== Enabling Docker Bearer Token realm ==="
curl -sf -X PUT "${NEXUS_URL}/service/rest/v1/security/realms/active" \
    -H "Content-Type: application/json" \
    -u "admin:${NEW_PASSWORD}" \
    -d '[
        "NexusAuthenticatingRealm",
        "NexusAuthorizingRealm",
        "DockerToken"
    ]'
echo "  Docker Bearer Token realm enabled."

echo ""
echo "=== Nexus setup complete! ==="
echo "  Docker registry available at: 192.168.56.20:8082"
