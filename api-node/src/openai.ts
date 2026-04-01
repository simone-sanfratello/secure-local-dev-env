import type { AppConfig } from "./config.ts";

function truncateForError(input: string, maxChars: number): string {
  if (input.length <= maxChars) {
    return input;
  }
  return `${input.slice(0, maxChars)}... (truncated)`;
}

export function extractOpenAIText(openaiResponse: unknown): string {
  const response = openaiResponse as {
    output_text?: string | string[];
    output?: Array<{ content?: Array<{ text?: string }> }>;
    choices?: Array<{ message?: { content?: string }; text?: string }>;
  };

  if (typeof response.output_text === "string") {
    return response.output_text;
  }

  if (Array.isArray(response.output_text)) {
    const joined = response.output_text
      .filter((value): value is string => typeof value === "string")
      .join("\n");
    if (joined.trim() !== "") {
      return joined;
    }
  }

  const nestedOutputText = response.output?.[0]?.content?.[0]?.text;
  if (typeof nestedOutputText === "string") {
    return nestedOutputText;
  }

  const chatMessageContent = response.choices?.[0]?.message?.content;
  if (typeof chatMessageContent === "string") {
    return chatMessageContent;
  }

  const completionText = response.choices?.[0]?.text;
  if (typeof completionText === "string") {
    return completionText;
  }

  return "No output text found in OpenAI response.";
}

export async function callOpenAI(
  config: AppConfig,
  prompt: string,
): Promise<unknown> {
  const response = await fetch(
    `${config.openaiBaseUrl.replace(/\/+$/, "")}/v1/responses`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${config.openaiApiKey}`,
      },
      body: JSON.stringify({
        model: config.openaiModel,
        input: prompt,
      }),
    },
  );

  const body = await response.text();
  if (!response.ok) {
    throw new Error(
      `OpenAI request failed with status ${response.status}: ${truncateForError(body, 512)}`,
    );
  }

  try {
    return JSON.parse(body);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "unknown JSON parse error";
    throw new Error(`invalid OpenAI JSON response: ${message}`);
  }
}
