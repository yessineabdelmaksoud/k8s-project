# Backend Service

## Purpose
This service exposes a small Node.js API for the Kubernetes application stack. It is the backend that Jenkins builds and deploys into the `backend` namespace.

## Runtime Behavior
- Starts an Express server on `PORT` or `8080`.
- Opens a MySQL connection pool using environment variables.
- Exposes three endpoints:
  - `GET /api/health` for Kubernetes readiness checks.
  - `GET /api/db-test` to verify the MySQL connection.
  - `GET /api` for a simple API response.

## Environment Variables
- `PORT`: HTTP port for the server.
- `DB_HOST`: MySQL host, typically `mysql-svc.database.svc.cluster.local`.
- `DB_PORT`: MySQL port, usually `3306`.
- `DB_USER`: MySQL username.
- `DB_PASSWORD`: MySQL password.
- `DB_NAME`: MySQL database name.

## Data Flow
1. The frontend sends a request to `/api/db-test` through the Nginx proxy.
2. Kubernetes routes the request to the backend Service.
3. The backend opens a pooled MySQL connection.
4. The backend runs a trivial query to confirm database connectivity.
5. The JSON response is returned to the frontend.

## Implementation Notes
- Uses `express` for HTTP routing.
- Uses `mysql2/promise` for async database access.
- Keeps the code intentionally small so deployment behavior is easy to validate in Kubernetes.

## Jenkins Integration
The `Jenkinsfile` builds the Docker image, pushes it to Nexus, and updates the Kubernetes deployment image tag.
