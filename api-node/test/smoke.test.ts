import assert from "node:assert";
import { test } from "node:test";
import { createApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";

test("service starts and responds to health check", async () => {
  const config = loadConfig();
  const app = await createApp(config);
  await app.ready();

  const response = await app.inject({
    method: "GET",
    url: config.httpHealthPath,
  });

  assert.strictEqual(response.statusCode, 200);
  const body = JSON.parse(response.body) as { status: string };
  assert.strictEqual(body.status, "ok");

  await app.close();
});
