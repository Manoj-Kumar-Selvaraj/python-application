# Nebula Aurora Assignment Report

---

## 1. Overview

This document outlines how the assignment requirements were implemented, including architectural decisions and operational considerations.

The implementation was performed in structured stages:

1. PostgreSQL migration
2. Containerization (Docker + Gunicorn)
3. Helm-based Kubernetes deployment (in progress)
4. Observability integration (pending)
5. k3d Docker-in-Docker cluster (pending)

The goal was to maintain production-grade design principles throughout the implementation without touching any logics or API endpoints.

---

## 2. Requirement Mapping

| Requirement                                                | Implementation                                                                                                                                                                  |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Replace SQLite with PostgreSQL                             | Migrated to PostgreSQL using `asyncpg` driver and SQLAlchemy async engine. `DATABASE_URL` configurable via environment variables. Verified locally and inside Docker container. |
| Dockerize FastAPI                                          | Production-ready Dockerfile created using Python 3.10-slim. Runs as non-root user. Gunicorn with Uvicorn worker (1 worker per pod).                                             |
| Deploy via Helm (FastAPI, PostgreSQL, Prometheus, Grafana) | In progress. Helm chart skeleton to be implemented next.                                                                                                                        |
| Prometheus scrapes `/metrics`                              | `/metrics` endpoint implemented using `prometheus_client`. Custom counters verified locally and inside container. Helm-level scraping configuration pending.                    |
| Grafana dashboard at `/d/creation-dashboard-678/creation`  | Pending. Dashboard JSON and UID configuration to be implemented in observability stage.                                                                                         |
| Ingress routing                                            | Pending. To be implemented in Helm using path-based routing.                                                                                                                    |
| Resource constraints (2 CPU / 4GB RAM / 5GB disk)          | Architecture chosen: 1 worker per pod, horizontal scaling via replicas. Resource limits to be enforced at Helm level.                                                           |
| Docker-in-Docker using k3d                                 | Pending. Final stage will include cluster bootstrap Dockerfile.                                                                                                                 |
| Image configurable via Helm values                         | Docker image built as `wiki-service`. Helm values will expose configurable repository and tag.                                                                                  |

---

## 3. Architecture Decisions

### Execution Model

* Gunicorn managing Uvicorn worker
* 1 worker per pod
* Horizontal scaling preferred over vertical scaling
* Async FastAPI for I/O-bound workload
* Kubernetes handles scaling via replicas

This approach aligns with cloud-native principles and respects the 2 CPU cluster constraint.

---

### Health Probe Strategy

* **Startup probe**: Ensures database schema is initialized successfully.
* **Readiness probe**: Validates PostgreSQL connectivity.
* **Liveness probe**: Process-level health only.
* Database checks intentionally excluded from liveness to avoid restart loops during DB outages.

This design ensures graceful isolation instead of unnecessary restarts.

---

### Database Lifecycle

* Async SQLAlchemy engine
* Lazy connection handling
* Environment-driven configuration (`DATABASE_URL`)
* Fail-fast behavior during startup if DB is unreachable
* Clean session lifecycle using dependency injection

---

### Metrics Strategy

* Prometheus `Counter` metrics implemented:

  * `users_created_total`
  * `posts_created_total`
* `/metrics` endpoint exposed via FastAPI
* Default Python process metrics included automatically
* Metrics verified locally and in containerized environment

---

### Resource Tuning Decisions

Cluster constraints:

* 2 CPU
* 4GB RAM
* 5GB disk

Chosen design:

* 1 worker per pod
* 2 replicas (horizontal scaling)
* Avoided over-provisioned multi-worker model
* Relied on Kubernetes CPU throttling and scheduling

This keeps resource usage predictable and controlled.

---

## 4. Challenges Faced

* Networking differences between host and container during PostgreSQL connectivity
* Container-to-host communication issues (`host.docker.internal` vs host networking)
* Ensuring PostgreSQL container was running during Docker testing
* Gunicorn control socket permission warning when running as non-root user
* Aligning Python runtime versions between local and container environments

---

## 5. Potential Production Improvements

* Implement connection retry logic for transient DB failures
* Deploy PostgreSQL as StatefulSet with persistent volumes
* Add structured logging
* Introduce circuit breaker pattern for DB dependency
* Implement Horizontal Pod Autoscaler
* Use multi-stage Docker build for smaller final image
* Add centralized log aggregation (e.g., Loki/ELK)

---

If you'd like, next we can tighten this further to make it sound even more senior-level and concise for reviewer impact.
