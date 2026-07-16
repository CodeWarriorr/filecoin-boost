import type { ScenarioContext } from "../runtime.js";
import { run, runRequired } from "../shell.js";

export function requireDevnet(context: ScenarioContext): void {
  const result = run("docker", ["exec", "lotus", "lotus", "chain", "head"], context.boostRoot);
  if (result.status !== 0) {
    throw new Error("Devnet not running: docker exec lotus lotus chain head failed");
  }
}

export function dockerExec(context: ScenarioContext, container: string, args: string[]): string {
  return runRequired("docker", ["exec", container, ...args], context.boostRoot);
}

export function dockerExecEnv(
  context: ScenarioContext,
  container: string,
  env: Record<string, string>,
  args: string[]
): string {
  const envArgs = Object.entries(env).flatMap(([key, value]) => ["-e", `${key}=${value}`]);
  return runRequired("docker", ["exec", ...envArgs, container, ...args], context.boostRoot);
}

export function dockerExecOk(context: ScenarioContext, container: string, args: string[]): boolean {
  return run("docker", ["exec", container, ...args], context.boostRoot).status === 0;
}
