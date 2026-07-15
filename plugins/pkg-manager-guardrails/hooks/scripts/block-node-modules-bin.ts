// Block direct node_modules/.bin/ invocations.
// Prefer: system-installed commands > pnpm exec/npx/bunx

type HookInput = {
  tool_input?: {
    command?: string;
  };
};

type HookOutput = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse";
    permissionDecision: "deny";
    permissionDecisionReason: string;
  };
};

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

async function main(): Promise<void> {
  const raw = await readStdin();
  const input: HookInput = raw ? JSON.parse(raw) : {};
  const command = input.tool_input?.command ?? "";

  const match = command.match(/node_modules\/\.bin\/(\S+)/);
  if (!match) {
    process.exit(0);
  }

  const binName = match[1];
  const output: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: `BLOCKED: direct node_modules/.bin/ invocation not allowed. Priority: 1) system-installed '${binName}' if available (check with 'which ${binName}'), 2) pnpm exec / npx / bunx. Rewrite and retry.`,
    },
  };
  process.stdout.write(JSON.stringify(output));
  process.exit(0);
}

main();
