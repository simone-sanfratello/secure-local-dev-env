CREATE TABLE IF NOT EXISTS ai_items (
  id UUID PRIMARY KEY,
  prompt TEXT NOT NULL,
  openai_text TEXT NOT NULL,
  openai_raw JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_items_created_at_idx ON ai_items (created_at DESC);
