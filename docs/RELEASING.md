# Releasing

Default image: `egori4/rdc-host-admin:0.1.0`. Release images are public and `linux/amd64` only in this initial release. Source repositories never contain device state or credentials.

## Checks before release

Run the CI checks, review the security implications, and test the image on an authorized Linux lab host. Update `VERSION`, package metadata/lockfile, default image examples, and the changelog together. The upstream RDC version is pinned; upgrades are explicit reviewable changes, not automatic `latest` resolution.

For host-admin, `scripts/smoke-test.sh` performs real privileged operations restricted to uniquely named temporary resources. Do not run it on a production host without permission. Browser pairing/end-to-end remote authorization is a separate manual test.

## GitHub Actions

The CI workflow runs on pushes and pull requests without publishing images. Publication is a manual workflow to avoid unintentionally overwriting release tags.

Configure:

- repository variable `DOCKERHUB_USERNAME` (or the existing secret with that name)
- repository secret `DOCKERHUB_TOKEN`, using a persistent Docker Hub personal/organization access token with appropriate push permission and expiry

A development-machine browser/device-login session is not a suitable long-lived CI credential. Never print tokens or copy Docker authentication files into a repository or image.

Create the Docker Hub repository with the intended **public** visibility before publication. Create an annotated `v<VERSION>` Git tag and push it. Dispatch Publish Docker image **at that tag** with the matching version. The workflow validates semantic version syntax, `VERSION`, and tag-to-commit agreement before accepting the publishing credentials. Workflow actions are pinned by commit, and untrusted inputs enter the shell through environment variables rather than direct code interpolation.

Images receive exact-version, minor, and `latest` tags. Use the exact tag/digest when installing. Do not overwrite an already released exact-version tag with different source.

## Maintainer first/manual publication

A maintainer already authenticated to Docker Hub can publish without storing that interactive credential in GitHub:

```bash
version=$(cat VERSION)
revision=$(git rev-parse HEAD)
docker build --build-arg VERSION="$version" --build-arg VCS_REF="$revision" \
  -t egori4/rdc-host-admin:"$version" .
docker push egori4/rdc-host-admin:"$version"
docker tag egori4/rdc-host-admin:"$version" egori4/rdc-host-admin:"${version%.*}"
docker tag egori4/rdc-host-admin:"$version" egori4/rdc-host-admin:latest
docker push egori4/rdc-host-admin:"${version%.*}"
docker push egori4/rdc-host-admin:latest
```

Record the image digest in release notes and verify an anonymous pull if the image is intended to be public. Package source/installer assets with `git archive`, not a filesystem tar that could accidentally include credentials or ignored files. Keep OS and upstream dependency updates current; a passing smoke test is not a security audit.
