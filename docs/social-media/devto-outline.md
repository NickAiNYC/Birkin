# Dev.to Article Outline

**Title:** Why I added a kill‑switch and hash‑chained audit logs to my AI agent (and why you should too)

**Tags:** `ai`, `security`, `autonomousagents`, `opensource`

**Canonical URL:** (your GitHub Pages or personal blog URL, if cross-posting)

---

## Structure

### 1. The fear (250 words)

Open with a concrete scenario: you wake up and your agent has been running overnight. It had access to your file system, your APIs, your shell. How do you know what it did?

- "Logs can be deleted. grep is not a chain of custody."
- Personal story: what prompted building this
- The specific failure modes that kept me up: hallucination → destructive action; prompt injection → secret exfiltration

### 2. Requirements I set before writing a line of code (150 words)

List what "provably safe" means, operationally:

- Every agent action must be recorded in a way that can't be silently mutated after the fact
- The verification must work even if the attacker has bypassed normal safeguards (DB triggers, etc.)
- I must be able to pull the plug at any time and prove I did
- Behavioral drift must be detectable before it becomes a problem

### 3. How Birkin solves each requirement (600 words)

**Hash-chained audit log**
- SHA-256(prev_hash || payload) at the row level
- SQLite triggers enforce append-only at DB layer
- But: triggers can be bypassed — the chain is independent of triggers by design
- Show the tamper-test output

**5-gate governance check**
- Walk through each gate
- Emphasize: deterministic, not probabilistic — no AI checking on AI

**Kill switches**
- agent-stop.sh and agent-lockdown.sh
- Both logged: you know who pulled the plug and when

**Drift detection**
- 5 benchmark questions, bigram cosine similarity
- Honest about what it catches and doesn't

### 4. Live demo (200 words + embed)

- Embed asciinema recording
- Walk through: governance-check → tamper simulation → detection → verify-chain output
- Show the kill switch firing

### 5. The honest threat model (250 words)

- What the hash chain catches
- What it explicitly does NOT catch (full DB replacement, log omission, host compromise)
- How Tier 1 roadmap (remote attestation) closes the DB replacement gap

### 6. What's next (100 words)

- HITL proxy (pre-execution gatekeeping) — the thing that makes Birkin a control plane
- Supply chain skill signing
- Embedding-based drift detection

### 7. Ask for feedback (100 words)

- Link to THREAT_MODEL.md
- Specific questions: attack vectors missed? Better drift detection approach? Would you use this?
- GitHub link
- Note: not a crypto project (head off the Hermes confusion)

---

## Estimated length: ~1,650 words

## Images needed
- Tamper-test GIF (already in repo: `static/tamper-demo.gif`)
- Architecture diagram (convert ASCII to image or use as code block)
- Governance check output screenshot
