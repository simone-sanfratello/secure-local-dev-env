"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

const BLOCKED_PROBE_PATH = "/api/v1/blocked-probe";

function rustApiBase(): string {
  const url = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "");
  if (!url) {
    throw new Error("NEXT_PUBLIC_API_URL is not set");
  }
  return url;
}

export default function BlockedPage() {
  const [text, setText] = useState<string>("Calling api-rust…");
  const [fetchOk, setFetchOk] = useState<boolean | null>(null);

  useEffect(() => {
    let cancelled = false;
    const url = `${rustApiBase()}${BLOCKED_PROBE_PATH}`;
    fetch(url)
      .then(async (res) => {
        const raw = await res.text();
        let pretty = raw;
        try {
          pretty = JSON.stringify(JSON.parse(raw), null, 2);
        } catch {
          /* keep raw */
        }
        if (!cancelled) {
          setFetchOk(res.ok);
          setText(pretty);
        }
      })
      .catch((e: unknown) => {
        if (!cancelled) {
          setFetchOk(false);
          setText(e instanceof Error ? e.message : String(e));
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="min-h-full bg-zinc-100 px-4 py-10 dark:bg-zinc-950">
      <div className="mx-auto flex max-w-3xl flex-col gap-4">
        <p>
          <Link
            href="/"
            className="text-sm text-zinc-600 underline decoration-zinc-400 underline-offset-4 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            ← Home
          </Link>
        </p>
        <header>
          <h1 className="text-2xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
            Blocked egress probe
          </h1>
          <p className="mt-2 text-sm leading-relaxed text-zinc-600 dark:text-zinc-400">
            This page calls{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              GET {BLOCKED_PROBE_PATH}
            </code>{" "}
            on{" "}
            <strong className="text-zinc-800 dark:text-zinc-200">
              api-rust
            </strong>
            , which tries{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              https://www.facebook.com/
            </code>
            . With the repo CoreDNS allowlist, that hostname should not resolve
            from filtered containers, so you typically see{" "}
            <code className="rounded bg-zinc-200 px-1 dark:bg-zinc-800">
              failed_dns_or_block
            </code>
            .
          </p>
        </header>
        {fetchOk != null && (
          <p className="text-sm text-zinc-500">
            HTTP from browser to api-rust:{" "}
            <span
              className={
                fetchOk
                  ? "font-medium text-emerald-700 dark:text-emerald-400"
                  : "font-medium text-amber-700 dark:text-amber-400"
              }
            >
              {fetchOk ? "response received" : "request failed"}
            </span>{" "}
            (api-rust still returns JSON describing the outbound attempt).
          </p>
        )}
        <pre className="overflow-auto rounded-xl border border-zinc-200 bg-white p-4 text-xs text-zinc-800 shadow-sm dark:border-zinc-800 dark:bg-zinc-950 dark:text-zinc-200">
          {text}
        </pre>
      </div>
    </div>
  );
}
