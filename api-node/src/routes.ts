import crypto from "node:crypto";
import type { FastifyInstance } from "fastify";
import type postgres from "postgres";
import type { AppConfig } from "./config.ts";
import { callOpenAI, extractOpenAIText } from "./openai.ts";

type StoredItem = {
  id: string;
  prompt: string;
  openai_text: string;
  openai_raw: unknown;
  created_at: string;
};

type Row = {
  id: string;
  prompt: string;
  openai_text: string;
  openai_raw: unknown;
  created_at: Date;
};

export type RegisterRoutesParams = {
  config: AppConfig;
  sql: postgres.Sql;
};

function formatCreatedAt(value: Date): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export async function registerRoutes(
  app: FastifyInstance,
  { config, sql }: RegisterRoutesParams,
): Promise<void> {
  app.get("/", async () => ({ service: config.appName }));

  app.get(config.httpHealthPath, async () => ({ status: "ok" }));

  app.get(`${config.httpApiV1Prefix}/items`, async (_request, reply) => {
    try {
      const rows = await sql<Row[]>`
        SELECT id, prompt, openai_text, openai_raw, created_at
        FROM ai_items
        ORDER BY created_at DESC
      `;

      const items: StoredItem[] = rows.map((row) => ({
        id: row.id,
        prompt: row.prompt,
        openai_text: row.openai_text,
        openai_raw: row.openai_raw,
        created_at: formatCreatedAt(row.created_at),
      }));

      return items;
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown error";
      return reply.status(500).send({
        error: { message: `failed reading items from postgres: ${message}` },
      });
    }
  });

  app.post<{
    Body: { prompt?: string };
  }>(`${config.httpApiV1Prefix}/items`, async (request, reply) => {
    const prompt = String(request.body?.prompt ?? "").trim();
    if (prompt === "") {
      return reply
        .status(400)
        .send({ error: { message: "prompt is required" } });
    }

    try {
      const openaiRaw = await callOpenAI(config, prompt);
      const openaiText = extractOpenAIText(openaiRaw);

      const item: StoredItem = {
        id: crypto.randomUUID(),
        prompt,
        openai_text: openaiText,
        openai_raw: openaiRaw,
        created_at: new Date().toISOString(),
      };

      await sql`
        INSERT INTO ai_items (id, prompt, openai_text, openai_raw, created_at)
        VALUES (
          ${item.id},
          ${item.prompt},
          ${item.openai_text},
          ${sql.json(item.openai_raw as postgres.JSONValue)},
          ${item.created_at}
        )
      `;

      return reply.status(201).send(item);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown error";
      return reply.status(500).send({
        error: { message: `failed creating item: ${message}` },
      });
    }
  });
}
