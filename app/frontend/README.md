# Frontend Service

## Purpose
This is the React user interface for the application. Jenkins builds it into a container image and deploys it into the `frontend` namespace.

## Runtime Behavior
- Built with Vite and React.
- Displays a simple status page.
- Calls `/api/db-test` on load to verify that the backend and database are reachable.

## Data Flow
1. The browser loads the frontend through the Kubernetes Service.
2. The app renders a status screen.
3. `useEffect` sends a fetch request to `/api/db-test`.
4. Nginx proxies `/api` traffic to the backend service.
5. The backend queries MySQL and returns success or failure.
6. The UI updates the displayed database status.

## Implementation Notes
- `src/main.jsx` bootstraps the React root.
- `src/App.jsx` holds the status logic and the fetch call.
- `vite.config.js` and `nginx.conf` control build-time and runtime delivery behavior.

## Jenkins Integration
The `Jenkinsfile` builds the container image, pushes it to Nexus, and rolls the Kubernetes deployment forward.
