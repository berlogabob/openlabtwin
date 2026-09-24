"""Idea hub AI job (edge node, every 15 min): normalise new ideas with a local model, embed them, match approved ones.

Usage: uv run python scripts/ideas_ai.py            process new ideas, rebuild matches
       uv run python scripts/ideas_ai.py --check    one tiny chat + embedding against the configured server, nothing written
Settings (.env):
  AI_API       ollama (default) | openai: any OpenAI-compatible server, e.g. Unsloth Studio, llama.cpp, vLLM, Ollama's /v1
  AI_URL       server base URL (default http://localhost:11434; OLLAMA_URL is still accepted)
  AI_KEY       optional bearer key for servers that want one
  IDEAS_MODEL  chat model (default ornith-1.5:9b)          EMBED_MODEL  embedding model (default nomic-embed-text)
Nothing leaves the lab as long as the server runs in the lab.
"""
import json
import math
import os
import sys
import urllib.request
from datetime import datetime, timezone

from db import connect, request, select

API = os.environ.get("AI_API", "ollama")
BASE = (os.environ.get("AI_URL") or os.environ.get("OLLAMA_URL") or "http://localhost:11434").rstrip("/")
KEY = os.environ.get("AI_KEY", "")
MODEL = os.environ.get("IDEAS_MODEL", "ornith-1.5:9b")
EMBED = os.environ.get("EMBED_MODEL", "nomic-embed-text")
# Measured on nomic-embed-text, 2026-09-24 (a handful of examples; re-tune on real ideas):
# summaries: related 0.69-0.81, unrelated <= 0.62. Skill phrase vs phrase: same 1.0, synonyms ~0.63, unrelated ~0.37-0.40.
SIMILAR, COMPLEMENTARY, TOP = 0.68, 0.60, 5
PROMPT = ("You normalise student project ideas for a university lab. Reply with JSON only, exactly: "
          '{"title": "<at most 8 words>", "summary": "<1-3 sentences in English>", "keywords": ["<3-8 lowercase keywords>"], '
          '"brings": ["<skills the student offers, [] if none given>"], '
          '"needs": ["<skills or help the student is looking for, [] if none given>"]}. '
          "Write skills as short general names, e.g. electronics, game design, 3d modelling, programming, sound design. "
          "Keep the student's meaning, translate to English, and leave out names and contact details.")


def post(path, body):
    headers = {"Content-Type": "application/json", **({"Authorization": f"Bearer {KEY}"} if KEY else {})}
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def ask_model(text):
    messages = [{"role": "system", "content": PROMPT}, {"role": "user", "content": text}]
    if API == "openai":
        reply = post("/v1/chat/completions", {"model": MODEL, "messages": messages, "temperature": 0.2,
                                              "response_format": {"type": "json_object"}})
        return reply["choices"][0]["message"]["content"]
    reply = post("/api/chat", {"model": MODEL, "stream": False, "format": "json", "think": False, "options": {"temperature": 0.2},
                               "messages": messages})
    return reply["message"]["content"]


def embed(texts):
    if API == "openai":
        return [d["embedding"] for d in sorted(post("/v1/embeddings", {"model": EMBED, "input": texts})["data"], key=lambda d: d["index"])]
    return post("/api/embed", {"model": EMBED, "input": texts})["embeddings"]


def check():
    """Is the configured server usable? Prints what works; writes nothing."""
    print(f"server {BASE} ({API}), chat model {MODEL}, embedding model {EMBED}")
    ok = True
    try:
        out = normalise({"body": "A small game about plants", "can_bring": "Unity", "looking_for": "electronics"})
        print("chat:", "ok" if out else "replied, but not with the JSON we need", out or "")
        ok = ok and bool(out)
    except Exception as e:  # noqa: BLE001 - this is a diagnostic
        print("chat: failed:", e); ok = False
    try:
        v = embed(["electronics", "game design"])
        print(f"embeddings: ok, {len(v)} vectors of {len(v[0])} numbers")
    except Exception as e:  # noqa: BLE001
        print("embeddings: failed:", e); ok = False
    return ok


def idea_text(i):
    return "\n".join(f"{k}: {v}" for k, v in [("Idea", i["body"]), ("I can bring", i.get("can_bring")),
                                               ("I'm looking for", i.get("looking_for"))] if v)


def parse_normalised(raw):
    """The model's JSON reply as {title, summary, keywords, brings, needs}, or None if it isn't usable."""
    try:
        d = json.loads(raw)
    except (TypeError, ValueError):
        return None
    if not isinstance(d, dict):
        return None
    title, summary, kw = d.get("title"), d.get("summary"), d.get("keywords")
    if not (isinstance(title, str) and title.strip() and isinstance(summary, str) and summary.strip() and isinstance(kw, list)):
        return None
    def phrases(v, lower=False):
        items = (x.strip().lower() if lower else x.strip() for x in (v if isinstance(v, list) else []) if isinstance(x, str))
        return list(dict.fromkeys(x for x in items if x))[:8]

    return {"title": " ".join(title.split()[:8]), "summary": summary.strip(), "keywords": phrases(kw, lower=True),
            "brings": phrases(d.get("brings")), "needs": phrases(d.get("needs"))}


def normalise(idea, ask=ask_model):
    """Two tries; None means skip this idea until the next run."""
    for _ in range(2):
        out = parse_normalised(ask(idea_text(idea)))
        if out:
            return out
    return None


def cosine(a, b):
    if not a or not b:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na, nb = math.sqrt(sum(x * x for x in a)), math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


def best(needs, brings):
    """How well one student's needs meet another's skills: the best phrase-to-phrase cosine."""
    return max((cosine(n, b) for n in needs for b in brings), default=0.0)


def pick_matches(ideas):
    """Pairs worth showing: [(a_id, b_id, kind, score, reason)], a_id < b_id, kept if in the top TOP of either idea.

    ideas: [{id, keywords, emb, brings: [vec], needs: [vec]}]."""
    scored = []
    for i, a in enumerate(ideas):
        for b in ideas[i + 1:]:
            lo, hi = (a, b) if a["id"] < b["id"] else (b, a)
            sim = cosine(a["emb"], b["emb"])
            if sim >= SIMILAR:
                shared = [k for k in lo["keywords"] if k in hi["keywords"]][:3]
                scored.append((lo["id"], hi["id"], "similar", sim, "similar topic" + (": " + ", ".join(shared) if shared else "")))
            comp = max(best(a["needs"], b["brings"]), best(b["needs"], a["brings"]))
            if comp >= COMPLEMENTARY:
                scored.append((lo["id"], hi["id"], "complementary", comp, "one is looking for what the other can bring"))
    keep = set()
    for idea in ideas:
        for kind in ("similar", "complementary"):
            mine = sorted((s for s in scored if s[2] == kind and idea["id"] in s[:2]), key=lambda s: -s[3])[:TOP]
            keep.update(mine)
    return sorted(keep, key=lambda s: (s[0], s[1], s[2]))


def vec(v):
    return json.loads(v) if isinstance(v, str) else v


def main():
    db = connect()
    todo = select(db, "ideas", {"select": "id,body,can_bring,looking_for", "ai_done_at": "is.null", "order": "id"})
    for idea in todo:
        out = normalise(idea)
        if not out:
            print(f"idea {idea['id']}: no usable reply from {MODEL}, will retry next run", file=sys.stderr)
            continue
        # skills are the model's English phrases, embedded one by one: matching then works across languages
        phrases = [("brings", x) for x in out["brings"]] + [("needs", x) for x in out["needs"]]
        vectors = embed([out["summary"]] + [x for _side, x in phrases])
        request(db, "DELETE", "idea_skills", {"idea_id": f"eq.{idea['id']}"}, headers={"Prefer": "return=minimal"})
        if phrases:
            request(db, "POST", "idea_skills", None, [{"idea_id": idea["id"], "side": side, "phrase": x, "embedding": v}
                                                      for (side, x), v in zip(phrases, vectors[1:])], {"Prefer": "return=minimal"})
        request(db, "PATCH", "ideas", {"id": f"eq.{idea['id']}"}, {
            "ai_title": out["title"], "ai_summary": out["summary"], "ai_keywords": out["keywords"], "ai_model": MODEL,
            "ai_done_at": datetime.now(timezone.utc).isoformat(), "embedding": vectors[0],
        }, {"Prefer": "return=minimal"})
        print(f"idea {idea['id']}: {out['title']}")
    approved = select(db, "ideas", {"select": "id,ai_keywords,embedding", "status": "eq.approved", "ai_done_at": "not.is.null",
                                    "order": "id"})
    skills = select(db, "idea_skills", {"select": "idea_id,side,embedding", "order": "idea_id,side,phrase"}) if approved else []
    def mine(i, side):
        return [vec(s["embedding"]) for s in skills if s["idea_id"] == i and s["side"] == side]
    pairs = pick_matches([{"id": r["id"], "keywords": r["ai_keywords"], "emb": vec(r["embedding"]),
                           "brings": mine(r["id"], "brings"), "needs": mine(r["id"], "needs")} for r in approved])
    if pairs:  # upsert leaves the students' connect flags alone: they aren't in the payload
        request(db, "POST", "idea_matches", {"on_conflict": "idea_a,idea_b,kind"},
                [{"idea_a": a, "idea_b": b, "kind": k, "score": round(s, 4), "reason": r} for a, b, k, s, r in pairs],
                {"Prefer": "resolution=merge-duplicates,return=minimal"})
    print(f"normalised {len(todo)}, approved {len(approved)}, matches {len(pairs)}")


if __name__ == "__main__":
    sys.exit(0 if check() else 1) if "--check" in sys.argv else main()
