"""Run: uv run python tests/test_ideas_ai.py"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import ideas_ai as ai  # noqa: E402

# parsing the model's JSON
good = json.dumps({"title": "A plant game with real soil sensors today and more", "summary": "A game.",
                   "keywords": ["Game", "sensors", "game", " "], "brings": ["Unity", "Unity", "3D modelling"], "needs": "electronics"})
p = ai.parse_normalised(good)
assert p == {"title": "A plant game with real soil sensors today", "summary": "A game.", "keywords": ["game", "sensors"],
             "brings": ["Unity", "3D modelling"], "needs": []}, p
for bad in ["not json", "[]", json.dumps({"title": "", "summary": "x", "keywords": []}), json.dumps({"title": "t", "summary": "s"})]:
    assert ai.parse_normalised(bad) is None, bad

# one retry, then give up
replies = iter(["oops", good])
assert ai.normalise({"body": "x"}, ask=lambda _t: next(replies))["keywords"] == ["game", "sensors"]
assert ai.normalise({"body": "x"}, ask=lambda _t: "still not json") is None
assert ai.idea_text({"body": "Idea", "can_bring": None, "looking_for": "help"}) == "Idea: Idea\nI'm looking for: help"

# cosine
assert abs(ai.cosine([1, 0], [1, 0]) - 1) < 1e-9 and ai.cosine([1, 0], [0, 1]) == 0 and ai.cosine(None, [1]) == 0

# matching: A~B similar, A needs what C brings, D unrelated
# the best phrase pair counts, not the whole list
assert ai.best([[1, 0], [0, 1]], [[0, 1]]) == 1.0 and ai.best([], [[1, 0]]) == 0.0
ideas = [
    {"id": 1, "keywords": ["plants", "game"], "emb": [1, 0, 0], "brings": [[0, 1, 0]], "needs": [[0.1, 0, 0], [0, 0, 1]]},
    {"id": 2, "keywords": ["plants", "robot"], "emb": [0.95, 0.1, 0], "brings": [], "needs": []},
    {"id": 3, "keywords": ["sound"], "emb": [0, 1, 0], "brings": [[0, 0, 1]], "needs": []},
    {"id": 4, "keywords": ["x"], "emb": [0, 0, 1], "brings": [], "needs": [[1, 0, 0]]},
]
m = ai.pick_matches(ideas)
kinds = {(a, b, k) for a, b, k, _s, _r in m}
assert (1, 2, "similar") in kinds and (1, 3, "complementary") in kinds, m
assert not any(4 in (a, b) for a, b, _k, _s, _r in m), "unrelated idea gets no match"
assert next(r for a, b, k, _s, r in m if (a, b, k) == (1, 2, "similar")) == "similar topic: plants"
assert all(a < b for a, b, *_ in m)
same = [i | {"person": 7} for i in ideas[:2]]
assert ai.pick_matches(same) == [], "one person's ideas are never matched with each other"
# both server styles send the right request and read the right reply
sent = []
def fake_post(path, body, base=None):
    sent.append((path, body))
    return {"/api/chat": {"message": {"content": good}}, "/api/embed": {"embeddings": [[1, 0]]},
            "/v1/chat/completions": {"choices": [{"message": {"content": good}}]},
            "/v1/embeddings": {"data": [{"index": 1, "embedding": [0, 1]}, {"index": 0, "embedding": [1, 0]}]}}[path]
ai.post = fake_post
ai.API = "ollama"
assert ai.ask_model("x") == good and ai.embed(["a"]) == [[1, 0]] and sent[0][1]["format"] == "json"
ai.API = "openai"
assert ai.ask_model("x") == good and sent[-1][1]["response_format"] == {"type": "json_object"}
ai.EMBED_API = "openai"
assert ai.embed(["a", "b"]) == [[1, 0], [0, 1]], "openai embeddings come back in input order"
ai.EMBED_API = "ollama"  # chat on an OpenAI-style server (Unsloth Studio), embeddings from Ollama
assert ai.embed(["a"]) == [[1, 0]] and sent[-1][0] == "/api/embed"
print("ok")
