# Reddit Post Drafts

---

## r/LocalLLaMA and r/MachineLearning

**Title:**
I was worried my local AI agent would go rogue, so I built a hash‑chained audit log with a kill switch. Open source—looking for feedback on the threat model.

**Body:**

I've been running a local AI agent (Hermes from Nous Research) to handle real tasks: competitor monitoring, daily briefings, code governance checks. It has shell access, web access, file access.

That scared me. An agent that can do things can also do the wrong things.

So I built **Birkin** — a governance layer that wraps any Hermes-compatible agent without modifying the agent itself.

**What it does:**

- **Hash-chained SQLite audit log**: every action the agent takes is SHA-256 chained (`SHA-256(prev_hash || payload)`). Mutate any row — even after bypassing database triggers — and `verify-chain.py` catches it. CI-tested on every push.
- **5-gate deterministic governance check**: process liveness, audit chain integrity, skill version pinning, behavioral drift against a signed baseline, health endpoint.
- **Kill switches**: `agent-stop.sh` (graceful) and `agent-lockdown.sh` (network isolation). Both writes are themselves audit-logged.
- **Drift detection**: 5 benchmark questions, bigram cosine similarity, threshold 0.85. Catches model swaps and config changes that shift behavior.
- **iPhone PWA**: full-screen Open WebUI from Safari home screen.

**The honest threat model** (from THREAT_MODEL.md):

- ✅ Catches: row mutation, deletion, mid-chain insertion, mutation after trigger bypass
- ❌ Does NOT catch: attacker replacing the entire DB, log omission (agent action never logged), root-level host compromise, prompt injection on the agent itself

The DB replacement attack is the one I'm most worried about. The Tier 1 roadmap item is posting the chain tip hash to Telegram/Nostr hourly — so a full replacement produces a tip that doesn't match published history.

**Demo** (asciinema): [LINK]

**GitHub**: https://github.com/NickAiNYC/Birkin

**Not crypto**: I'm aware there's a "Hermes" crypto project. This is completely unrelated — no tokens, no DAO, no blockchain. Just agentic AI security tooling.

---

**What I'm genuinely looking for:**

1. Attack vectors I haven't thought of in the threat model
2. Opinions on the drift detection approach (bigram cosine vs. embedding similarity)
3. Anyone who's tried to solve the "prove your agent didn't do something bad" problem differently

Happy to discuss the architecture in comments.
