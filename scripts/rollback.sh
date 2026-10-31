#!/usr/bin/env bash
set -euo pipefail
NAMESPACE=${NAMESPACE:-gen-ai-labs}
kubectl -n "$NAMESPACE" rollout undo deployment/gen-ai-labs-api
kubectl -n "$NAMESPACE" rollout undo deployment/gen-ai-labs-web
kubectl -n "$NAMESPACE" rollout status deployment/gen-ai-labs-api
kubectl -n "$NAMESPACE" rollout status deployment/gen-ai-labs-web
