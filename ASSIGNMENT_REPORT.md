# Nebula Aurora Assignment Report

This document describes how the assignment was implemented, the reasoning behind key design decisions, and how the system can be validated.

The goal was not only to meet the functional requirements, but to ensure the system behaves predictably under Kubernetes constraints and startup race conditions.

---

## 1. Repository Structure

The repository is organized to clearly separate responsibilities:

```
/
├── wiki-service/     # FastAPI application + Docker image
├── wiki-chart/       # Helm chart (API, PostgreSQL, Prometheus, Grafana)
├── Dockerfile        # Docker-in-Docker runner (Part 2)
└── entrypoint.sh     # Bootstraps k3d + Helm installation
```

This separation allows:

* Independent image building and versioning
* Clean Helm templating
* Reproducible “cluster-in-a-container” execution for Part 2

---

## 2. Architectural Overview

The system consists of:

* FastAPI (async)
* PostgreSQL (StatefulSet + PVC)
* Prometheus (scraping `/metrics`)
* Grafana (dashboard provisioning)
* Ingress (path-based routing)
* k3d cluster (resource constrained)
* Docker-in-Docker wrapper for reproducibility

Each component was chosen and configured with operational behavior in mind.

---

## 3. Application Layer Decisions

### Async FastAPI + async SQLAlchemy

The API uses async FastAPI with SQLAlchemy’s async engine and `asyncpg`.

**Why async?**

* The workload is I/O-bound (database calls).
* Async allows a single worker to handle concurrent requests efficiently.
* Under a constrained 2 CPU environment, async is more resource-efficient than increasing worker count.

---

### Gunicorn + Single Uvicorn Worker Per Pod

The container runs:

* Gunicorn
* `uvicorn.workers.UvicornWorker`
* 1 worker per pod

**Why 1 worker per pod?**

Instead of vertical scaling (multiple workers inside a pod), the design prefers horizontal scaling (multiple replicas). This aligns with Kubernetes-native scaling patterns and avoids CPU oversubscription within a constrained node.

Replica count is set to 2 to:

* Support rolling updates
* Avoid single-point failure
* Stay within the 2 CPU cluster budget

---

## 4. Database Deployment

PostgreSQL is deployed as a StatefulSet with a PersistentVolumeClaim.

**Why StatefulSet?**

* Databases are stateful workloads.
* Stable network identity and storage binding are required.
* PVC ensures data survives pod restarts.

Storage is explicitly defined (1Gi) to respect the overall 5GB disk constraint.

---

## 5. Health Probe Strategy

Three probes are implemented:

### `/health/live`

* Process-level only.
* Does not check the database.
* Prevents crash loops if DB is temporarily unavailable.

### `/health/ready`

* Verifies database connectivity.
* If DB becomes unavailable, the pod is removed from Service.
* Does not restart the container.

### `/health/startup`

* Indicates application boot readiness.
* Used to gate readiness and liveness during initialization.

**Justification**

Separating liveness and readiness avoids unnecessary restarts during DB outages.
This mirrors real production probe design rather than simplistic health checks.

---

## 6. Startup Race Condition Handling

During testing, a startup race condition was observed:

* Kubernetes starts API and PostgreSQL simultaneously.
* API attempted DB connection before PostgreSQL was ready.
* Result: CrashLoopBackOff.

This was resolved by adding retry logic in the FastAPI startup hook.

**Why implement retry in application code?**

Kubernetes does not guarantee workload startup ordering. Relying on Helm ordering alone is not sufficient. Services should tolerate transient dependency unavailability.

This makes the system resilient and production-aligned.

---

## 7. Observability

The API exposes:

* `users_created_total`
* `posts_created_total`

Prometheus scrapes `/metrics`.

Grafana dashboard is provisioned and accessible via:

```
/grafana/d/creation-dashboard-678/creation
```

Grafana login:

* Username: `admin`
* Password: `admin`

**Why include application-level counters?**

Infrastructure health alone is insufficient. Application metrics validate real functionality (user creation, post creation), not just container uptime.

---

## 8. Resource Constraints

Cluster budget:

* 2 CPU
* 4GB RAM
* 5GB disk

Design choices made with this in mind:

* 1 worker per pod
* 2 replicas only
* Explicit resource requests/limits on all workloads
* Lightweight Python base image
* Minimal Prometheus/Grafana configuration

The system remains stable within the constrained environment.

---

## 9. Helm Design

Key principles:

* All configurable values exposed via `values.yaml`
* Image name configurable (set `fastapi.image_name` in `wiki-chart/values.yaml`)
* Resource limits configurable
* Credentials defined centrally
* Minimal templating complexity

This keeps the chart readable and review-friendly.

---

## 10. Docker-in-Docker (Part 2)

The root Dockerfile:

* Starts `dockerd`
* Creates a k3d cluster inside the container
* Installs ingress-nginx
* Installs the Helm chart
* Waits for workloads

No host Docker socket is mounted.

The container is run with:

```
--privileged --cgroupns=host -p 8080:8080
```

This ensures k3s can detect cgroup controllers on modern hosts.

Note: some environments may work without `--cgroupns=host` (for example, if the host is using cgroup v1 or if cgroup v2 controllers are delegated differently). For reproducibility across modern Linux hosts, `--cgroupns=host` is included in the documented run command.

**Why DinD instead of docker.sock?**

Mounting the host socket would break isolation and violate the requirement. Running Docker inside the container ensures full self-containment.

---

## 11. Verification

After startup (~2–3 minutes):

API:

```
http://localhost:8080/users
http://localhost:8080/posts
```

Metrics:

```
http://localhost:8080/metrics
```

Grafana:

```
http://localhost:8080/grafana/
```

Required dashboard path:

```
http://localhost:8080/grafana/d/creation-dashboard-678/creation
```

Functional validation examples:

* Create users/posts via `/users` and `/posts`
* Confirm counters increase in `/metrics`
* Confirm Grafana dashboard loads at `/grafana/d/creation-dashboard-678/creation`

Scripted smoke checks:

* `wiki-service/test_api.sh` exercises the ingress-routed endpoints (`/users/*`, `/posts/*`, `/metrics`, `/grafana`) and exits non-zero on any unexpected HTTP status.
* `entrypoint.sh` runs this script after the Helm install/upgrade; if it fails, the container exits with a non-zero status (so CI/autograding can detect failures).

Optional resilience checks (if you want to demonstrate self-healing):

* Delete an API pod and observe it get recreated
* Restart PostgreSQL and observe the API recover

---

## 12. Summary

This implementation focuses on:

* Async I/O efficiency
* Proper probe separation
* Stateful workload handling
* Resilience against startup races
* Observability integration
* Resource constraint awareness
* Reproducible DinD execution

The system is fully containerized, Helm-packaged, observable, and operationally resilient.

---
