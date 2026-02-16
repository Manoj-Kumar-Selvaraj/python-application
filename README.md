# Wikipedia-like API Service

This repository contains the application logic for a simplified Wikipedia-like API:

- Users and posts CRUD-style endpoints
- PostgreSQL-backed persistence
- Prometheus metrics via `/metrics`
- Health endpoints for Kubernetes probes

Deployment / Kubernetes / Docker-in-Docker details live in `ASSIGNMENT_REPORT.md` (the assignment limits docs to two files).

## API overview

Base URL (when deployed behind ingress): `http://localhost:8080`

### Endpoints

- `GET /users` — list users
- `POST /users` — create a user
- `GET /posts` — list posts
- `POST /posts` — create a post
- `GET /metrics` — Prometheus metrics

### Health

- `GET /health/live` — liveness
- `GET /health/ready` — readiness (DB connectivity)
- `GET /health/startup` — startup

## Example requests

### Create user

```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice"}'
```

### Create post

```bash
curl -X POST http://localhost:8080/posts \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"content":"Hello"}'
```

### Metrics

```bash
curl -s http://localhost:8080/metrics | head
```

## Application structure

- `wiki-service/app/main.py` — FastAPI routes + health + metrics wiring
- `wiki-service/app/models.py` — DB models
- `wiki-service/app/database.py` — async SQLAlchemy engine/session
- `wiki-service/app/metrics.py` — `users_created_total`, `posts_created_total`
