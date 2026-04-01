"use client";

import { useEffect, useState } from "react";

const ITEMS_PATH = "/api/v1/items";

function baseRust(): string {
  const url = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "");
  if (!url) {
    throw new Error("NEXT_PUBLIC_API_URL is not set");
  }
  return url;
}

function baseNode(): string {
  const url = process.env.NEXT_PUBLIC_API_NODE_URL?.replace(/\/$/, "");
  if (!url) {
    throw new Error("NEXT_PUBLIC_API_NODE_URL is not set");
  }
  return url;
}

type ProbeStep = {
  label: string;
  ok: boolean;
  status: number;
  body: string;
};

async function requestStep(
  label: string,
  url: string,
  init?: RequestInit,
): Promise<ProbeStep> {
  try {
    const headers: HeadersInit = {
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...((init?.headers as Record<string, string>) ?? {}),
    };
    const res = await fetch(url, { ...init, headers });
    const text = await res.text();
    let body = text;
    try {
      body = JSON.stringify(JSON.parse(text), null, 2);
    } catch {
      /* keep raw */
    }
    return { label, ok: res.ok, status: res.status, body };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { label, ok: false, status: 0, body: msg };
  }
}

function StepList({ title, steps }: { title: string; steps: ProbeStep[] }) {
  return (
    <section className="rounded-xl border border-zinc-200 bg-white p-4 shadow-sm dark:border-zinc-800 dark:bg-zinc-950">
      <h2 className="mb-3 text-lg font-semibold text-zinc-900 dark:text-zinc-100">
        {title}
      </h2>
      <ol className="flex flex-col gap-4">
        {steps.map((s) => (
          <li key={s.label} className="text-sm">
            <div className="mb-1 flex flex-wrap items-center gap-2">
              <span
                className={
                  s.ok
                    ? "rounded bg-emerald-100 px-2 py-0.5 font-medium text-emerald-900 dark:bg-emerald-950 dark:text-emerald-200"
                    : "rounded bg-red-100 px-2 py-0.5 font-medium text-red-900 dark:bg-red-950 dark:text-red-200"
                }
              >
                {s.status || "—"}
              </span>
              <span className="font-mono text-xs text-zinc-600 dark:text-zinc-400">
                {s.label}
              </span>
            </div>
            <pre className="max-h-64 overflow-auto rounded-lg bg-zinc-100 p-3 text-xs text-zinc-800 dark:bg-zinc-900 dark:text-zinc-200">
              {s.body}
            </pre>
          </li>
        ))}
      </ol>
    </section>
  );
}

export default function Home() {
  const [rustSteps, setRustSteps] = useState<ProbeStep[]>([]);
  const [nodeSteps, setNodeSteps] = useState<ProbeStep[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const br = baseRust();
      const bn = baseNode();
      const postBody = JSON.stringify({
        prompt: `web probe ${new Date().toISOString()}`,
      });

      const r: ProbeStep[] = [];
      r.push(
        await requestStep("GET items (before)", `${br}${ITEMS_PATH}`, {
          method: "GET",
        }),
      );
      r.push(
        await requestStep("POST item (OpenAI)", `${br}${ITEMS_PATH}`, {
          method: "POST",
          body: postBody,
        }),
      );
      r.push(
        await requestStep("GET items (after)", `${br}${ITEMS_PATH}`, {
          method: "GET",
        }),
      );

      const n: ProbeStep[] = [];
      n.push(
        await requestStep("GET items (before)", `${bn}${ITEMS_PATH}`, {
          method: "GET",
        }),
      );
      n.push(
        await requestStep("POST item (OpenAI)", `${bn}${ITEMS_PATH}`, {
          method: "POST",
          body: postBody,
        }),
      );
      n.push(
        await requestStep("GET items (after)", `${bn}${ITEMS_PATH}`, {
          method: "GET",
        }),
      );

      if (!cancelled) {
        setRustSteps(r);
        setNodeSteps(n);
        setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="min-h-full bg-zinc-100 px-4 py-10 dark:bg-zinc-950">
      <div className="mx-auto flex max-w-5xl flex-col gap-6">
        <header>
          <h1 className="text-2xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
            Backend probe
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-zinc-600 dark:text-zinc-400">
            On load, the browser calls{" "}
            <strong className="text-zinc-800 dark:text-zinc-200">
              api-rust
            </strong>{" "}
            and{" "}
            <strong className="text-zinc-800 dark:text-zinc-200">
              api-node
            </strong>{" "}
            each with{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              GET
            </code>{" "}
            items, then{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              POST
            </code>{" "}
            a short prompt (triggers OpenAI), then{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              GET
            </code>{" "}
            items again. URLs come from{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              NEXT_PUBLIC_API_URL
            </code>{" "}
            and{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              NEXT_PUBLIC_API_NODE_URL
            </code>
            .
          </p>
        </header>

        {loading ? (
          <p className="text-sm text-zinc-500">Calling APIs…</p>
        ) : (
          <div className="grid gap-6 md:grid-cols-2">
            <StepList title={`api-rust (${baseRust()})`} steps={rustSteps} />
            <StepList title={`api-node (${baseNode()})`} steps={nodeSteps} />
          </div>
        )}
      </div>
    </div>
  );
}
