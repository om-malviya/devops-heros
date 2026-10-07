#!/usr/bin/env bash
# Build script for the Session 16 project.
#   ./build.sh            -> package the app into build/ (always works)
#   ./build.sh --docker   -> additionally build the Docker image
set -euo pipefail
cd "$(dirname "$0")"

IMAGE_NAME="${IMAGE_NAME:-session16-calculator-api}"
GIT_SHA="${GIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "================================="
echo "Starting Application Build"
echo "================================="
rm -rf build
mkdir -p build
cp -R app build/app
find build -name '__pycache__' -type d -prune -exec rm -rf {} +
cp requirements.txt build/
cat > build/build-info.txt <<INFO
Application: Session 16 Calculator API
Git SHA:     ${GIT_SHA}
Build Date:  ${BUILD_DATE}
Build Status: SUCCESS
INFO

echo ""
echo "Build files:"
find build -type f | sort
echo ""
cat build/build-info.txt

if [[ "${1:-}" == "--docker" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found - skipping image build" >&2
    exit 1
  fi
  echo ""
  echo "Building Docker image ${IMAGE_NAME}:${GIT_SHA}"
  docker build --build-arg GIT_SHA="${GIT_SHA}" -t "${IMAGE_NAME}:${GIT_SHA}" -t "${IMAGE_NAME}:latest" .
fi

echo ""
echo "Build completed successfully."
