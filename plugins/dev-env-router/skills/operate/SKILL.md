---
name: operate
description: "Day-to-day start/stop/restart rules for a project already onboarded to dev-env-router (has a docker-compose.yml with Traefik labels), and how to report its URL. Use this skill whenever starting, stopping, or restarting a dev service in an already-onboarded project, or when asked what a specific onboarded project's URL is. Triggers on: 'start the dev server', 'run the app', 'stop this project's containers'. Do NOT use for first-time setup of a project without Traefik labels (use onboard instead), or for a broad 'what's running across all my projects' question (check the Traefik dashboard directly per this skill's own instructions, that is not a separate trigger)."
---

# dev-env-router: Day-to-Day Operating Rules

Applies to projects already onboarded to the router via the `onboard` skill.

## Pre-check: Confirm the Project Is Onboarded First

Before running any start/stop command, confirm that the target project has actually been onboarded to this setup. Do not assume it is onboarded just because "the user said start/run it":

```bash
grep -q 'traefik.enable=true' docker-compose.yml compose.yml 2>/dev/null && echo onboarded || echo not-onboarded
```

If the result is `not-onboarded`, do not add labels on the spot or force `docker compose up` here; instead, guide the user through the `onboard` skill to complete onboarding.

## Start / Stop

You must use Docker Compose commands from the project root. Starting a bare process instead (e.g. running `npm run dev` or `python manage.py runserver` directly) is **not allowed**:

```bash
docker compose up -d      # start
docker compose down       # stop
docker compose restart    # restart
```

Rationale: `COMPOSE_PROJECT_NAME` (and therefore the domain) is derived from the current working directory, so commands must run from the project root to guarantee the correct routing identity; bare processes also bypass Traefik, which defeats this routing setup.

## Reporting the Address: Domain Only, Never a Port

Whenever you tell the user "where the service is", always use a URL of the form `http://${COMPOSE_PROJECT_NAME}.localhost`. Do not report or ask about any port number — ports should not be something the user needs to care about.

`${COMPOSE_PROJECT_NAME}` is the project directory name (as normalized by Compose). If you are unsure of the actual domain, confirm it in the dashboard; do not report a guess. If the dashboard has no route for the project, first check whether the `traefik.enable=true` label is missing (go back to the pre-check step above) rather than repeatedly guessing domains.

## Viewing Global State

Do not use `docker ps` to guess container ownership one by one. Every project onboarded to the router automatically appears in the shared Traefik dashboard:

```
http://traefik.localhost
```

Logging in requires the basicauth credentials corresponding to `~/.local/share/dev-env/traefik/.htpasswd`. There you can see all currently running projects, their domain routes, and backend health.

## Boundaries

- This skill does not handle first-time onboarding (see `onboard`), nor cleanup of orphaned containers from deleted worktrees (see `cleanup`; it is destructive and outside the scope of day-to-day operations).
- If the project has no Traefik labels yet (not onboarded to this setup), guide the user through the `onboard` skill first; do not add labels on the spot during operate.
- This skill does not handle restarting/upgrading/rotating credentials for the shared router (Traefik itself) — that is machine-level infrastructure the user sets up and maintains manually per the plugin's `USAGE.md`, and is not the responsibility of any skill. When the user says "restart Traefik" rather than "restart this project of mine", do not run `docker compose restart` in the project directory; if the router itself needs restarting, guide the user to do it themselves following `USAGE.md` (the service's start command is idempotent and simply reuses the existing config).
