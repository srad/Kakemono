#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
docker build -t kakemono-dev:latest -f Dockerfile.dev .
