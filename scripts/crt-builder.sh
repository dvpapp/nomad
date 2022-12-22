#!/usr/bin/env bash

# The crt-builder is used to detemine build metadata and create Nomad builds.
# We use it in build-nomad.yml for building release artifacts with CRT. 

set -euo pipefail

# We don't want to get stuck in some kind of interactive pager
export GIT_PAGER=cat

# Get the full version information
function version() {
  local version
  local prerelease
  local metadata

  version=$(version_base)
  prerelease=$(version_pre)
  metadata=$(version_metadata)

  if [ -n "$metadata" ] && [ -n "$prerelease" ]; then
    echo "$version-$prerelease+$metadata"
  elif [ -n "$metadata" ]; then
    echo "$version+$metadata"
  elif [ -n "$prerelease" ]; then
    echo "$version-$prerelease"
  else
    echo "$version"
  fi
}

# Get the base version
function version_base() {
  : "${NOMAD_VERSION:=""}"

  if [ -n "$NOMAD_VERSION" ]; then
    echo "$NOMAD_VERSION"
    return
  fi

  : "${VERSION_FILE:=$(repo_root)/version/version.go}"
  awk '$1 == "Version" && $2 == "=" { gsub(/"/, "", $3); print $3 }' < "$VERSION_FILE"
}

# Get the version pre-release
function version_pre() {
  : "${NOMAD_PRERELEASE:=""}"

  if [ -n "$NOMAD_PRERELEASE" ]; then
    echo "$NOMAD_PRERELEASE"
    return
  fi

  : "${VERSION_FILE:=$(repo_root)/version/version.go}"
  awk '$1 == "VersionPrerelease" && $2 == "=" { gsub(/"/, "", $3); print $3 }' < "$VERSION_FILE"
}

# Get the version metadata, which is commonly the edition
function version_metadata() {
  : "${NOMAD_METADATA:=""}"

  if [ -n "$NOMAD_METADATA" ]; then
    echo "$NOMAD_METADATA"
    return
  fi

  : "${VERSION_FILE:=$(repo_root)/version/version.go}"
  awk '$1 == "VersionMetadata" && $2 == "=" { gsub(/"/, "", $3); print $3 }' < "$VERSION_FILE"
}

# Get the build date from the latest commit since it can be used across all
# builds
function build_date() {
  # It's tricky to do an RFC3339 format in a cross platform way, so we hardcode UTC
  : "${DATE_FORMAT:="%Y-%m-%dT%H:%M:%SZ"}"
  git show --no-show-signature -s --format=%cd --date=format:"$DATE_FORMAT" HEAD
}

# Get the revision, which is the latest commit SHA
function build_revision() {
  git rev-parse HEAD
}

# Determine our repository by looking at our origin URL
function repo() {
  basename -s .git "$(git config --get remote.origin.url)"
}

# Determine the root directory of the repository
function repo_root() {
  git rev-parse --show-toplevel
}

# Determine the artifact basename based on metadata
function artifact_basename() {
  : "${PKG_NAME:="nomad"}"
  : "${GOOS:=$(go env GOOS)}"
  : "${GOARCH:=$(go env GOARCH)}"

  echo "${PKG_NAME}_$(version)_${GOOS}_${GOARCH}"
}

# Build the UI
function build_ui() {
  local repo_root
  repo_root=$(repo_root)

  pushd "$repo_root"
  mkdir -p ui/
  popd
  pushd "$repo_root/ui"
  npm install -g yarn
  popd
}

# Build Nomad
function build() {
  local version
  local revision
  local prerelease
  local build_date
  local ldflags
  local msg

  # Get or set our basic build metadata
  version=$(version_base)
  revision=$(build_revision)
  metadata=$(version_metadata)
  prerelease=$(version_pre)
  build_date=$(build_date)
  : "${GO_TAGS:=""}"
  : "${KEEP_SYMBOLS:=""}"

  # Build our ldflags
  msg="--> Building Nomad v$version, revision $revision, built $build_date"

  # Strip the symbol and dwarf information by default
  if [ -n "$KEEP_SYMBOLS" ]; then
    ldflags=""
  else
    ldflags="-s -w "
  fi

  ldflags="${ldflags}-X github.com/hashicorp/nomad/version.Version=$version -X github.com/hashicorp/nomad/version.GitCommit=$revision -X github.com/hashicorp/nomad/version.BuildDate=$build_date"

  if [ -n "$prerelease" ]; then
    msg="${msg}, prerelease ${prerelease}"
    ldflags="${ldflags} -X github.com/hashicorp/nomad/version.VersionPrerelease=$prerelease"
  fi

  if [ -n "$metadata" ]; then
    msg="${msg}, metadata ${NOMAD_METADATA}"
    ldflags="${ldflags} -X github.com/hashicorp/nomad/version.VersionMetadata=$metadata"
  fi

  # Build Nomad
  echo "$msg"
  pushd "$(repo_root)"
  mkdir -p pkg
  mkdir -p out
  set -x
  go build -v -tags "$GO_TAGS" -ldflags "$ldflags" -o pkg/
  echo "HERE"
  contents=$(ls pkg)
  echo "Contents: $contents"
  set +x
  popd
}

# Bundle the pkg directory
function bundle() {
  : "${BUNDLE_PATH:=$(repo_root)/nomad.zip}"
  echo "--> Bundling pkg/* to $BUNDLE_PATH"
  zip -r -j "$BUNDLE_PATH" pkg/
}

# Prepare legal requirements for packaging
function prepare_legal() {
  : "${PKG_NAME:="nomad"}"

  pushd "$(repo_root)"
  mkdir -p pkg
  curl -o pkg/EULA.txt https://eula.hashicorp.com/EULA.txt
  curl -o pkg/TermsOfEvaluation.txt https://eula.hashicorp.com/TermsOfEvaluation.txt
  mkdir -p ".release/linux/package/usr/share/doc/$PKG_NAME"
  cp pkg/EULA.txt ".release/linux/package/usr/share/doc/$PKG_NAME/EULA.txt"
  cp pkg/TermsOfEvaluation.txt ".release/linux/package/usr/share/doc/$PKG_NAME/TermsOfEvaluation.txt"
  popd
}

# Run the CRT Builder
function main() {
  case $1 in
  artifact-basename)
    artifact_basename
  ;;
  build)
    build
  ;;
  build-ui)
    build_ui
  ;;
  bundle)
    bundle $2
  ;;
  date)
    build_date
  ;;
  prepare-legal)
    prepare_legal
  ;;
  revision)
    build_revision
  ;;
  version)
    version
  ;;
  version-base)
    version_base
  ;;
  version-pre)
    version_pre
  ;;
  version-meta)
    version_metadata
  ;;
  *)
    echo "unknown sub-command" >&2
    exit 1
  ;;
  esac
}

main "$@"