import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";
import postgres from "postgres";
import type { AppConfig } from "./config.ts";
import { registerRoutes } from "./routes.ts";

export async function createApp(config: AppConfig): Promise<FastifyInstance> {
  const sql = postgres(config.databaseUrl, { max: 10 });

  try {
    await sql`SELECT 1`;
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown error";
    console.error(
      JSON.stringify({
        level: "error",
        message: `database connection failed: ${message}`,
      }),
    );
    process.exit(1);
  }

  const app = Fastify({ logger: false });

  await app.register(cors, {
    origin: config.corsAllowedOrigin,
    methods: ["GET", "POST", "OPTIONS"],
  });

  await registerRoutes(app, { config, sql });

  app.setNotFoundHandler((_request, reply) =>
    reply.status(404).send({ error: { message: "not found" } }),
  );

  const shutdown = async (): Promise<void> => {
    await app.close();
    await sql.end({ timeout: 5 });
    process.exit(0);
  };

  process.on("SIGINT", () => {
    void shutdown();
  });
  process.on("SIGTERM", () => {
    void shutdown();
  });

  return app;
}
