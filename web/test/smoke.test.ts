import assert from "node:assert";
import { test } from "node:test";

test("Next.js config loads with expected output mode", async () => {
  const { default: config } = await import("../next.config.ts");
  assert.strictEqual(config.output, "standalone");
});
