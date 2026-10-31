#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] || { echo 'Create .env from .env.example and set GROQ_API_KEY + JWT_SECRET'; exit 1; }
docker compose up --build -d
echo 'Frontend: http://localhost:8080 | API docs: http://localhost:8000/docs'
