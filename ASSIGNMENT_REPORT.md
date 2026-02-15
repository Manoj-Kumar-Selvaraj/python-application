# Nebula Aurora Assignment Report

---

## 1. Overview

This document outlines how the assignment requirements were implemented, along with the architectural decisions and operational considerations taken during development.

The implementation was executed in structured, incremental stages:

1. PostgreSQL migration
2. Containerization (Docker + Gunicorn)
3. Helm-based Kubernetes deployment (in progress)
4. Observability integration (pending)
5. k3d Docker-in-Docker cluster (pending)

The goal was to preserve all existing application logic and API contracts while evolving the system into a production-ready, containerized, Kubernetes-deployable service.

---

## 2. Requirement Mapping

| Requirement                                                | Implementation                                                                                                                                                                                                                                                                                         |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Replace SQLite with PostgreSQL                             | Migrated to PostgreSQL using `asyncpg` and SQLAlchemy async engine. `DATABASE_URL` is fully environment-driven. Verified locally and inside Docker container.                                                                                                                                          |
| Dockerize FastAPI                                          | Production-ready Dockerfile created using **Python 3.10-slim**. Python 3.10 was intentionally selected for ecosystem stability and predictable container behavior rather than using a bleeding-edge runtime. Container runs as a non-root user and uses Gunicorn with a single Uvicorn worker per pod. |
| Deploy via Helm (FastAPI, PostgreSQL, Prometheus, Grafana) | In progress. Helm chart skeleton to be implemented next.                                                                                                                                                                                                                                               |
| Prometheus scrapes `/metrics`                              | `/metrics` endpoint implemented using `prometheus_client`. Custom counters verified locally and inside container. Helm-level scraping configuration pending.                                                                                                                                           |
| Grafana dashboard at `/d/creation-dashboard-678/creation`  | Pending. Dashboard JSON and UID configuration to be implemented during observability stage.                                                                                                                                                                                                            |
| Ingress routing                                            | Pending. Will be implemented using path-based routing in Helm.                                                                                                                                                                                                                                         |
| Resource constraints (2 CPU / 4GB RAM / 5GB disk)          | Architecture intentionally designed with 1 worker per pod and horizontal scaling via replicas. Resource limits will be enforced at Helm level.                                                                                                                                                         |
| Docker-in-Docker using k3d                                 | Pending. Final stage will include root-level cluster bootstrap Dockerfile.                                                                                                                                                                                                                             |
| Image configurable via Helm values                         | Docker image built as `wiki-service`. Helm values will expose configurable image repository and tag.                                                                                                                                                                                                   |

---

## 3. Architecture Decisions

### Execution Model

* Gunicorn managing a Uvicorn worker
* 1 worker per pod
* Horizontal scaling preferred over vertical scaling
* Async FastAPI for I/O-bound workload
* Kubernetes responsible for replica-level scaling

Given the 2 CPU cluster constraint, this model avoids excessive worker processes inside a single pod and aligns better with Kubernetes-native scaling patterns.

---

### Health Probe Strategy

* **Startup probe**: Ensures database schema initialization completes successfully.
* **Readiness probe**: Validates PostgreSQL connectivity.
* **Liveness probe**: Restricted to process-level health only.

Database checks were intentionally excluded from liveness to prevent crash loops during temporary database outages. This ensures graceful isolation rather than aggressive restarts.

---

### Database Lifecycle

* Async SQLAlchemy engine
* Lazy connection handling
* Environment-driven configuration via `DATABASE_URL`
* Fail-fast behavior during startup if DB is unreachable
* Clean session lifecycle using FastAPI dependency injection

The database layer remains fully asynchronous and production-aligned.

---

### Metrics Strategy

* Prometheus `Counter` metrics implemented:

  * `users_created_total`
  * `posts_created_total`
* `/metrics` endpoint exposed via FastAPI
* Default Python process metrics automatically included
* Metrics validated locally and inside container

This ensures immediate compatibility with Prometheus scraping.

---

### Resource Tuning Decisions

Cluster constraints:

* 2 CPU
* 4GB RAM
* 5GB disk

Chosen design:

* 1 worker per pod
* 2 replicas (horizontal scaling)
* Avoided multi-worker vertical scaling inside a single pod
* Relied on Kubernetes CPU throttling and scheduling

This keeps resource consumption predictable and within the defined constraints while preserving availability.

---

## 4. Challenges Faced

* Networking differences between host and container during PostgreSQL connectivity
* Container-to-host communication issues (`host.docker.internal` vs host networking)
* Ensuring PostgreSQL container state during Docker testing
* Gunicorn control socket permission warning under non-root execution
* Aligning Python runtime versions between local and container environments

Each issue was resolved without modifying core application logic.

---

## 5. Potential Production Improvements

* Add connection retry logic for transient DB failures
* Deploy PostgreSQL as StatefulSet with persistent volumes
* Introduce structured logging
* Implement circuit breaker pattern for database dependency
* Add Horizontal Pod Autoscaler
* Use multi-stage Docker build to further reduce image size
* Integrate centralized logging (e.g., Loki or ELK stack)

---
