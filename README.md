# OCI Apache Gateway

This repository builds a hardened, rootless-ready **Apache / PHP OIDC Gateway** container image (`ghcr.io/joeckr/apache`) based on `php:<version>-apache-trixie` and engineered to build and run cleanly in restricted container and Kubernetes environments.

## Purpose

Standard `php:<version>-apache-trixie` images listen on privileged port `80` by default, do not bundle OpenID Connect (OIDC) authentication modules, and rely on Debian `apt-get` / `dpkg` operations (`seteuid` to `_apt` and `chown` on unpacked package directories) that fail in unprivileged container builders where `CAP_SETUID`, `CAP_DAC_OVERRIDE`, `CAP_CHOWN`, and `CAP_FOWNER` are dropped.

This project provides:
- Pre-installed and enabled Apache `auth_openidc` (`libapache2-mod-auth-openidc`), `rewrite`, and `apache2-utils` modules on `php:8.5-apache-trixie`.
- Capability-free rootless image builds using `APT::Sandbox::User=root` and `Dpkg::Options::=--force-not-root` so builds succeed even when all capabilities except `NET_BIND_SERVICE` are dropped.
- Unprivileged port configuration (`8080` for HTTP, `8443` for HTTPS) and root-group (`GID 0`) write permissions (`chgrp -R 0` and `chmod -R g+rwX`) on `/var/www/html` and `/etc/apache2/conf-enabled/`.
- Dynamic OIDC virtual host configuration at container startup via `src/entrypoint.sh`.

## Features

- **OpenID Connect (OIDC) Authentication**:
  - Dynamically generates `/etc/apache2/conf-enabled/oidc.conf` when `OIDC_ENABLED=true`.
  - Validates required OIDC environment variables on startup and fails fast if any are missing.
  - Configures `mod_auth_openidc` with `OIDCSessionType server-cache`, `OIDCForwardedHeaders X-Forwarded-Proto X-Forwarded-Host`, and `OIDCRemoteUserClaim preferred_username`.
  - Automatically skips and cleans up OIDC configuration when `OIDC_ENABLED` is unset or not `"true"`.
- **Rootless & Restricted Builder Compatible**:
  - Removes `_apt`-owned partial directories (`/var/lib/apt/lists/*`, `/var/cache/apt/archives/partial`) prior to running `apt-get`.
  - Runs `apt-get` with `-o APT::Sandbox::User=root` and `-o Dpkg::Options::=--force-not-root` to avoid privilege-drop (`seteuid`/`setgroups`) and `chown` failures during rootless Podman/Buildah builds.
- **Hardened Permissions & Unprivileged Ports**:
  - Listens on port `8080` (`8443` for SSL/GnuTLS) via `src/ports.conf`.
  - Configures group `0` (`root` group) ownership and `g+rwX` permissions on `/var/www/html` and `/etc/apache2/conf-enabled/` to support arbitrary runtime UIDs.
- **Modular VirtualHost Extensions**:
  - Includes `IncludeOptional /etc/apache2/conf.d/*.conf` inside the `:8080` VirtualHost when OIDC is enabled so additional routes or proxy rules can be mounted cleanly.

## Repository Structure

- `Dockerfile`: Builds the hardened Apache / PHP OIDC gateway image from `php:8.5-apache-trixie`.
- `src/entrypoint.sh`: Startup script that validates OIDC environment variables, generates `/etc/apache2/conf-enabled/oidc.conf`, and launches `apache2-foreground`.
- `src/ports.conf`: Apache port configuration listening on unprivileged ports `8080` and `8443`.
- `src/index.html`: Default landing page served from `/var/www/html/index.html`.
- `compose.yml`: Local Podman/Docker Compose stack for building and testing the gateway image on port `8080`.
- `compose.upstream.yml`: Baseline Compose configuration using the unmodified upstream `php:8.5-apache-trixie` image.
- `mise.toml`: Task runner definitions for local builds, compose workflows, linting, and Trivy security scans.
- `.github/workflows/`: Automated CI/CD workflows for linting, security auditing, and multi-arch image releases.

## Configuration & Environment Variables

The gateway is configured at runtime via environment variables passed to the container:

| Variable | Default | Description |
|---|---|---|
| `OIDC_ENABLED` | *(unset)* | Set to `"true"` to generate `/etc/apache2/conf-enabled/oidc.conf` and enforce OIDC authentication on `<Location />`. When unset or not `"true"`, OIDC configuration is skipped. |
| `OIDC_ISSUER` | *(required when enabled)* | OIDC provider metadata URL (`OIDCProviderMetadataURL`, e.g., `https://idp.example.com/realms/main/.well-known/openid-configuration`). |
| `OIDC_CLIENT_ID` | *(required when enabled)* | OIDC relying party client ID (`OIDCClientID`). |
| `OIDC_CLIENT_SECRET` | *(required when enabled)* | OIDC relying party client secret (`OIDCClientSecret`). |
| `OIDC_REDIRECT_URI` | *(required when enabled)* | Base application URL (`OIDCRedirectURI` appends `/redirect_uri`, e.g., `https://app.example.com`). |
| `OIDC_SSL_VERIFY` | *(required when enabled)* | Controls TLS certificate validation for the OIDC provider (`OIDCSSLValidateServer`, e.g., `On` or `Off`). |
| `OIDC_SESSION_SECRET` | *(required when enabled)* | Crypto passphrase used by `mod_auth_openidc` (`OIDCCryptoPassphrase`). |
| `SERVER_NAME` | `local` | Apache `ServerName` directive for `<VirtualHost *:8080>`. |

## Security & Hardened Image Architecture

Building and running container images in restricted environments (such as rootless Podman configured with `userns = "auto"` and `default_capabilities = ["NET_BIND_SERVICE"]`, or Kubernetes clusters enforcing **Pod Security Standards**) requires eliminating privileged build and runtime assumptions:

- **Capability-Free Package Installation**: Standard Debian base images pre-create `/var/lib/apt/lists/partial` and `/var/cache/apt/archives/partial` owned by `_apt:root` (`42:0`, mode `0700`), and `.deb` packages like `libapache2-mod-auth-openidc` unpack cache directories owned by `www-data`. The `Dockerfile` removes pre-existing `_apt` directories and passes `-o APT::Sandbox::User=root` and `-o Dpkg::Options::=--force-not-root` so package installation succeeds without `CAP_SETUID`, `CAP_SETGID`, `CAP_DAC_OVERRIDE`, or `CAP_CHOWN`.
- **Group `0` Runtime Permissions**: Recreates `/var/www/html` and configures `/var/www/html` and `/etc/apache2/conf-enabled/` with `chgrp -R 0` and `chmod -R g+rwX` without relying on `chown` to non-root UIDs.
- **Unprivileged Ports**: Reconfigures Apache to bind to port `8080` (`8443` for TLS) instead of privileged ports `80`/`443`.

### Compliance Matrix

| Security Dimension | Restricted Standard Requirement | Implementation in This Repo |
|---|---|---|
| **Build Execution** | Unprivileged / rootless builder compatible | Builds cleanly under rootless Podman/Buildah with dropped capabilities (`mise run build` / `mise run compose`) |
| **APT / Dpkg Sandboxing** | No `CAP_SETUID` / `CAP_CHOWN` during build | `APT::Sandbox::User=root` & `Dpkg::Options::=--force-not-root` |
| **Group Permissions** | GID `0` (`root` group) with `g+rwX` | `chgrp -R 0` & `chmod -R g+rwX` on `/var/www/html` and `/etc/apache2/conf-enabled/` |
| **Port Binding** | Unprivileged (`> 1024`) | Listens on port `8080` (`EXPOSE 8080`) |

---

## Local Testing & Development

### 1. Build and Run with Podman Compose (`compose.yml`)

```sh
# Build and start the gateway container
mise run compose
# or: podman compose up -d --build

# View container logs
mise run logs
# or: podman compose logs -f

# Verify connectivity (with OIDC_ENABLED unset, returns index.html)
curl http://localhost:8080

# Stop the stack
mise run down
# or: podman compose down
```

### 2. Baseline Upstream Comparison (`compose.upstream.yml`)

To compare against the unmodified upstream `php:8.5-apache-trixie` image:

```sh
podman compose -f compose.upstream.yml up -d
podman compose -f compose.upstream.yml down
```

### 3. Linting & Security Scanning

```sh
# Run pre-commit and linter checks (hadolint, shellcheck, actionlint, zizmor, etc.)
mise run hk

# Build local test image and scan with Trivy
mise run trivy-fs
mise run trivy-i
```

---

## Mise Tasks Quick Reference

| Task | Description | Command |
|---|---|---|
| `install` | Install Git hooks (`pre-commit` and `commit-msg`). | `hk install --mise` |
| `hk` (or `check`) | Run all repository pre-commit and formatting checks. | `hk check --all` |
| `build` | Build local test container image for `linux/amd64`. | `podman buildx build --platform linux/amd64 -t ghcr.io/joeckr/oci-modified:test . --load` |
| `compose` | Build and run the gateway image in Podman Compose. | `podman compose up -d --build` |
| `down` | Stop and remove the Podman Compose stack. | `podman compose down` |
| `logs` | Follow logs from the Podman Compose stack. | `podman compose logs -f` |
| `trivy-fs` | Scan repository filesystem for security vulnerabilities. | `trivy fs .` |
| `trivy-i` | Scan the built container image with Trivy. | `trivy image ghcr.io/joeckr/oci-modified:test` |

## Support

If you find this project useful, consider supporting my work on [Ko-fi](https://ko-fi.com/joeckr):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/joeckr)

## License

Please refer to the [LICENSE](LICENSE) file for details.
