// Block direct edits to lockfiles, and dependency-block edits inside package.json.
// Prefer: pnpm add/remove/update, bun add/remove/update, npm install <pkg>

import { basename } from "node:path";

type HookInput = {
  tool_input?: {
    file_path?: string;
    new_string?: string;
    content?: string;
  };
};

type HookOutput = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse";
    permissionDecision: "deny";
    permissionDecisionReason: string;
  };
};

const LOCKFILE_NAMES = new Set([
  "package-lock.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lockb",
  "bun.lock",
  "npm-shrinkwrap.json",
]);

const DEPENDENCY_BLOCK_PATTERN =
  /"(dependencies|devDependencies|peerDependencies|optionalDependencies)"/;

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

function deny(reason: string): never {
  const output: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  };
  process.stdout.write(JSON.stringify(output));
  process.exit(0);
}

async function main(): Promise<void> {
  const raw = await readStdin();
  const input: HookInput = raw ? JSON.parse(raw) : {};
  const filePath = input.tool_input?.file_path ?? "";
  const baseName = filePath ? basename(filePath) : "";

  if (LOCKFILE_NAMES.has(baseName)) {
    deny(
      `BLOCKED: direct edit of lockfile '${baseName}' not allowed. Lockfiles are generated artifacts — run 'pnpm install' / 'bun install' / 'npm install' instead.`,
    );
  }

  if (baseName === "package.json") {
    const payload = `${input.tool_input?.new_string ?? ""}\n${input.tool_input?.content ?? ""}`;
    if (DEPENDENCY_BLOCK_PATTERN.test(payload)) {
      deny(
        "BLOCKED: direct dependency-block edit in package.json not allowed. Use 'pnpm add/remove/update <pkg>' or 'bun add/remove/update <pkg>' instead of hand-editing dependencies.",
      );
    }
  }

  process.exit(0);
}

main();
