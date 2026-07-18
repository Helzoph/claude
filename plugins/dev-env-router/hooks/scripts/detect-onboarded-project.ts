// Reminds Claude to use dev-env-router (docker compose, not bare processes)
// when the session starts inside a project that already has Traefik labels.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

type HookInput = {
  cwd?: string;
};

type HookOutput = {
  hookSpecificOutput: {
    hookEventName: "SessionStart";
    additionalContext: string;
  };
};

const COMPOSE_FILENAMES = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"];

function readStdin(): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function isOnboarded(cwd: string): boolean {
  for (const filename of COMPOSE_FILENAMES) {
    const path = join(cwd, filename);
    if (!existsSync(path)) continue;
    const content = readFileSync(path, "utf8");
    if (/traefik\.enable=true/.test(content)) return true;
  }
  return false;
}

async function main(): Promise<void> {
  const raw = await readStdin();
  const input: HookInput = raw ? JSON.parse(raw) : {};
  const cwd = input.cwd ?? process.cwd();

  if (!isOnboarded(cwd)) {
    process.exit(0);
  }

  const output: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext:
        "This project is onboarded to dev-env-router (Traefik labels found in its Compose file). " +
        "Start/stop/restart it with `docker compose up -d` / `down` / `restart` — never a bare process " +
        "(e.g. `npm run dev`, `python manage.py runserver`), since that bypasses Traefik and breaks routing. " +
        "Report its URL as `http://<project-dir-name>.localhost` — never a port number. " +
        "See the dev-env-router plugin's `operate` skill for the full rules.",
    },
  };
  process.stdout.write(JSON.stringify(output));
  process.exit(0);
}

main();
