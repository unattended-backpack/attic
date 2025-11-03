## Attic

Attic is a [self-hostable Nix Binary Cache](https://github.com/zhaofengli/attic). We make extensive use of it to maintain a fully independent supply chain of Nix packages that we have built and cached. We maintain [Granary](https://github.com/unattended-backpack/granary), which is our simple solution for making it easy to host an attic server. Upstream usage documentation is maintained at [docs.attic.rs](https://docs.attic.rs/).

## Building

To build locally, you should simply need to run `make`; you can see more in the [`Makefile`](./Makefile). This will default to building with the maintainer-provided details from [`.env.maintainer`](./.env.maintainer), which we will periodically update as details change.

You can also build a Docker image using `make docker`. The build process uses a multi-stage Dockerfile:
1. **Builder stage**: uses Petros (supply-chain hardened Rust environment) to compile attic.
2. **Runtime stage**: copies binaries to a minimal Debian base image.

Configuration values in `.env.maintainer` may be overridden by specifying them as environment variables:

```bash
IMAGE_NAME=attic
BUILD_IMAGE=registry.digitalocean.com/sigil/petros:latest make build
RUNTIME_IMAGE=debian:bookworm-slim@sha256:... make build
```

## Configuration

Our configuration follows a zero-trust model where all sensitive configuration is stored on the self-hosted runner, not in GitHub. This section documents the configuration required for automated releases via GitHub Actions.

Running attic requires some sensitive configuration to be provided in in `.env` and `server.toml`; you can generate these files from the provided examples with `make init`. The `.env` file contains secrets such as database credentials, while `server.toml` contains the main server configuration including listening addresses, cache storage paths, and database connection details. Review both files carefully and populate all required fields before proceeding.

### Runner-Local Secrets

All secrets must be stored on the self-hosted runner at `/opt/github-runner/secrets/`. These files are mounted read-only into the release workflow container and are never stored in GitHub.

#### Required Secrets

**GitHub Access Tokens** (for creating releases and pushing to GHCR):
- `ci_gh_pat` - A GitHub fine-grained personal access token with repository permissions.
- `ci_gh_classic_pat` - A GitHub classic personal access token for GHCR authentication.

**Registry Access Tokens** (for pushing container images):
- `do_token` - A DigitalOcean API token with container registry write access.
- `dh_token` - A Docker Hub access token.

**GPG Signing Keys** (for signing release artifacts):
- `gpg_private_key` - A base64-encoded GPG private key for signing digests.
- `gpg_passphrase` - The passphrase for the GPG private key.
- `gpg_public_key` - The base64-encoded GPG public key (included in release notes).

**Registry Configuration** (`registry.env` file):

This file contains non-sensitive registry identifiers and build configuration:

```bash
# The Docker image to perform release builds with.
# If not set, defaults to unattended/petros:latest from Docker Hub.
# Examples:
#   BUILD_IMAGE=registry.digitalocean.com/sigil/petros:latest
#   BUILD_IMAGE=ghcr.io/your-org/petros:latest
#   BUILD_IMAGE=unattended/petros:latest
BUILD_IMAGE=unattended/petros:latest

# The runtime base image for the final container.
# If not set, uses the value from from .env.maintainer.
# Example:
#   RUNTIME_IMAGE=debian:trixie-slim@sha256:66b37a5078a77098bfc80175fb5eb881a3196809242fd295b25502854e12cbec
RUNTIME_IMAGE=debian:trixie-slim@sha256:66b37a5078a77098bfc80175fb5eb881a3196809242fd295b25502854e12cbec

# The name of the DigitalOcean registry to publish the built image to.
DO_REGISTRY_NAME=your-registry-name

# The username of the Docker Hub account to publish the built image to.
DH_USERNAME=your-dockerhub-username
```

### Public Configuration

Public configuration that anyone building this project needs is stored in the repository at [`.env.maintainer`](./.env.maintainer):

- `IMAGE_NAME` - The name of the Docker image (default: `attic`).
- `BUILD_IMAGE` - The builder image for compiling Rust code (default: `unattended/petros:latest`).
- `RUNTIME_IMAGE` - The runtime base image (default: pinned `debian:trixie-slim@sha256:...`).

This file is version-controlled and updated by maintainers as infrastructure details change.

## Verifying Release Artifacts

All releases include GPG-signed artifacts for verification. Each release contains:

- `image-digests.txt` - A human-readable list of container image digests.
- `image-digests.txt.asc` - A GPG signature for the digest list.
- `ghcr-manifest.json` / `ghcr-manifest.json.asc` - A GitHub Container Registry OCI manifest and signature.
- `dh-manifest.json` / `dh-manifest.json.asc` - A Docker Hub OCI manifest and signature.
- `do-manifest.json` / `do-manifest.json.asc` - A DigitalOcean Container Registry OCI manifest and signature.

### Quick Verification

Download the artifacts and verify signatures:

```bash
# Import the GPG public key (base64-encoded in release notes).
echo "<GPG_PUBLIC_KEY>" | base64 -d | gpg --import

# Verify digest list.
gpg --verify image-digests.txt.asc image-digests.txt

# Verify image manifests.
gpg --verify ghcr-manifest.json.asc ghcr-manifest.json
gpg --verify dh-manifest.json.asc dh-manifest.json
gpg --verify do-manifest.json.asc do-manifest.json
```

### Manifest Verification

The manifest files contain the complete OCI image structure (layers, config, metadata). To verify that a registry hasn't tampered with an image:

```bash
# Pull the manifest from the registry.
docker manifest inspect ghcr.io/unattended-backpack/attic@sha256:... \
  --verbose > registry-manifest.json

# Compare to the signed manifest.
diff ghcr-manifest.json registry-manifest.json

# If identical, the registry image matches the signed manifest.
```

This provides cryptographic proof that the image structure (all layers and configuration) matches what was signed at release time.

### Cosign Verification (Optional)

Images are also signed with [cosign](https://github.com/sigstore/cosign) using GitHub Actions OIDC for keyless signing. This provides automated verification and build provenance.

To verify with cosign:
```bash
# Verify image signature (proves it was built by GitHub Actions workflow)
cosign verify ghcr.io/unattended-backpack/attic@sha256:... \
  --certificate-identity-regexp='^https://github.com/unattended-backpack/.+' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

Cosign verification provides:
- Automated verification (no manual GPG key management).
- Build provenance (proves image was built by the GitHub Actions workflow).
- Registry-native signatures (stored alongside images).

**Note**: Cosign depends on external infrastructure (GitHub OIDC, Rekor). For maximum trust independence, rely on the GPG-signed manifests as your ultimate root of trust.

## Local Testing

This repository is configured to support testing the release workflow locally using the `act` tool. There is a corresponding goal in the Makefile, and instructions for further management of secrets [here](./docs/WORKFLOW_TESTING.md). This local testing file also shows how to configure the required secrets for building.

# Security

If you discover any bug; flaw; issue; dæmonic incursion; or other malicious, negligent, or incompetent action that impacts the security of any of these projects please responsibly disclose them to us; instructions are available [here](./SECURITY.md).

# License

The [license](./LICENSE) for all of our original work is `LicenseRef-VPL WITH AGPL-3.0-only`. This includes every asset in this repository: code, documentation, images, branding, and more. You are licensed to use all of it so long as you maintain _maximum possible virality_ and our copyleft licenses.

Permissive open source licenses are tools for the corporate subversion of libre software; visible source licenses are an even more malignant scourge. All original works in this project are to be licensed under the most aggressive, virulently-contagious copyleft terms possible. To that end everything is licensed under the [Viral Public License](./licenses/LicenseRef-VPL) coupled with the [GNU Affero General Public License v3.0](./licenses/AGPL-3.0-only) for use in the event that some unaligned party attempts to weasel their way out of copyleft protections. In short: if you use or modify anything in this project for any reason, your project must be licensed under these same terms.

For art assets specifically, in case you want to further split hairs or attempt to weasel out of this virality, we explicitly license those under the viral and copyleft [Free Art License 1.3](./licenses/FreeArtLicense-1.3).

# Original Licenses

We stand on the shoulders of giants. This repository is a fork of upstream which we modify and run for Sigil's own needs. This original project is licensed under the [`APACHE-2.0-only`](./original_licenses/APACHE-2.0-only) licenses, the original text of which has been maintained in the [`original_licenses/`](./original_licenses/LICENSE) directory. The commit hash of initial divergence is `12cbeca141f46e1ade76728bce8adc447f2166c6`; our license only applies to any of our own code or modifications that have not been upstreamed and absolutely does not apply to any original code or future upstream code we may choose to merge.
