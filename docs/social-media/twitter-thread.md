# Twitter / X Thread Draft

Ready to post. Replace `[LINK]` with your GitHub URL and `[GIF_LINK]` with your asciinema/GIF link.

---

**Tweet 1 — Hook**

Giving an AI agent access to your files, APIs, and shell is terrifying.

Hallucinations become destructive actions. A prompt injection can exfiltrate your secrets.

So I built Birkin: a hash-chained audit log + kill switch for local AI agents.

Open source. No tokens. Just provable safety. 🧵

---

**Tweet 2 — Demo**

Here's what it looks like when Birkin catches a tamper attempt:

[GIF_LINK]

Every row in the audit DB stores SHA-256(prev_hash || payload). Mutate one byte anywhere — even after bypassing database triggers — and verification fails.

One command proves it: `./tests/tamper-test.sh`

---

**Tweet 3 — The 5-Gate Governance Check**

Birkin runs a 5-gate governance check against your agent:

1. Is the agent process running and responding?
2. Is the audit chain intact? (no tampered rows)
3. Are all skills git-versioned with committed changes?
4. Has the model drifted from its signed behavioral baseline?
5. Is the health endpoint reporting clean?

Pure deterministic logic. No AI guessing about AI.

`./governance-check.sh` → "BIRKIN GOVERNANCE INTACT"

---

**Tweet 4 — Remote Attestation (the hard problem)**

The weakest link: what if an attacker replaces the entire audit.db?

verify-chain.py would verify the replacement chain as valid.

So Birkin (Tier 1 roadmap) posts the chain tip hash to Telegram/Nostr hourly. Full DB replacement produces a new tip that doesn't match published history.

Tampering becomes provable even after the fact.

---

**Tweet 5 — CTA**

Birkin is open source, MIT licensed, runs on Docker.

If you run a local AI agent (Hermes, anything OpenAI-compatible), Birkin wraps it without touching your install.

GitHub: [LINK]

Looking for feedback on the threat model — especially what attack vectors I missed.

What would you want in a kill switch for your agent?
