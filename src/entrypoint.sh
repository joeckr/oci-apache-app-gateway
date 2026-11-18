#!/bin/bash
set -e

OIDC_CONF="/etc/apache2/conf-enabled/oidc.conf"

if [ "$OIDC_ENABLED" == "true" ]; then
    echo "OIDC is enabled. Generating Apache config..."
    
    REQUIRED_VARS=(
        "OIDC_ISSUER"
        "OIDC_CLIENT_ID"
        "OIDC_CLIENT_SECRET"
        "OIDC_REDIRECT_URI"
        "OIDC_SSL_VERIFY"
        "OIDC_SESSION_SECRET"
    )
    missing=false

    for v in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!v}" ]; then
            echo "Error: Missing required environment variable: $v"
            missing=true
        fi
    done

    if [ "$missing" = true ]; then
        echo "Aborting due to missing configuration. Please set all required environment variables."
        exit 1
    fi
    cat <<EOF > "$OIDC_CONF"

OIDCProviderMetadataURL ${OIDC_ISSUER}
OIDCClientID ${OIDC_CLIENT_ID}
OIDCClientSecret ${OIDC_CLIENT_SECRET}
OIDCRedirectURI ${OIDC_REDIRECT_URI}/redirect_uri
OIDCSSLValidateServer ${OIDC_SSL_VERIFY}
OIDCCryptoPassphrase ${OIDC_SESSION_SECRET}
OIDCForwardedHeaders X-Forwarded-Proto X-Forwarded-Host
OIDCSessionType server-cache

<VirtualHost *:8080>
    ServerName ${SERVER_NAME:-local}

    <Location />
        AuthType openid-connect
        Require valid-user
    </Location>

    OIDCRemoteUserClaim preferred_username
    IncludeOptional /etc/apache2/conf.d/*.conf
</VirtualHost>

EOF
    echo Apache config generated
else
    echo "OIDC disabled. Skipping OIDC config."
    rm -f "$OIDC_CONF" || true
fi

echo "Starting Apache..."
exec "$@"
