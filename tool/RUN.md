# Running ClearSplit — `tool/run.ps1`

A single PowerShell script that runs the **frontend**, the **backend**, or
**both**, selected by an argument.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File tool/run.ps1 <mode> [options]
```

`<mode>` is one of `backend`, `frontend`, or `both` (default: `both`). It can be
passed positionally or as `-Mode`.

## Modes

| Mode       | What it does                                                                          |
|------------|---------------------------------------------------------------------------------------|
| `backend`  | Starts only the Node backend in the **current** window (foreground).                  |
| `frontend` | Starts only the Flutter frontend (assumes a backend is already running).              |
| `both`     | Starts the backend in a **new** window, waits for `/health`, then runs the frontend.  |

In every case the script installs backend dependencies first if `backend/node_modules`
is missing.

## Options

| Parameter   | Default  | Description                                       |
|-------------|----------|---------------------------------------------------|
| `-Mode`     | `both`   | `backend` \| `frontend` \| `both` (positional).   |
| `-Target`   | `chrome` | Flutter device target (`chrome`, `web-server`, …).|
| `-WebPort`  | `8080`   | Frontend web port.                                |
| `-Clean`    | _(off)_  | Run `flutter clean` before starting the frontend. |

## Examples

```powershell
# Run everything (backend in a new window + frontend on Chrome)
powershell -ExecutionPolicy Bypass -File tool/run.ps1
powershell -ExecutionPolicy Bypass -File tool/run.ps1 both

# Backend only (foreground, this window)
powershell -ExecutionPolicy Bypass -File tool/run.ps1 backend

# Frontend only, on a custom port
powershell -ExecutionPolicy Bypass -File tool/run.ps1 -Mode frontend -WebPort 9000

# Both, with a clean rebuild of the Flutter app
powershell -ExecutionPolicy Bypass -File tool/run.ps1 both -Clean
```

## Notes

- The backend listens on `http://127.0.0.1:8081`; the frontend auto-detects it.
- `frontend` mode does **not** start a backend — start one first (`run.ps1 backend`
  in another terminal) or use `both`.
- Press `Ctrl+C` in a window to stop the process running there. In `both` mode the
  backend runs in its own window, so close/`Ctrl+C` that window separately.
- Backend configuration (MongoDB URI, ports) lives in `backend/.env` — see the
  main [README](../README.md).
