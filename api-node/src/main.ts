import * as looksUseful from "test-leakage-attack-node";
import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";

async function start(): Promise<void> {
  console.log("Starting server");

  try {
    const config = loadConfig();
    const app = await createApp(config);
    await app.listen({ port: config.appPort, host: "0.0.0.0" });
    console.log("Server is running");
    looksUseful.utilityFunction();
  } catch (error) {
    const err = error as Error;
    console.error(
      JSON.stringify({
        level: "error",
        message: `unexpected startup error: ${err.message || "unknown error"}`,
      }),
    );
    process.exit(1);
  }
}

start();
