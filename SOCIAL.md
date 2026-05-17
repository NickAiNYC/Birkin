# Birkin — Social Media Threads & Marketing Copy

## 🐦 X Thread #1: Technical Deep Dive (For Builders)

> Every AI agent shipped today **trusts itself.** "We log everything. We won't drift. You can reproduce us."
> 
> None of them prove it.
> 
> I built Birkin differently. It doesn't ask for trust. It proves integrity via cryptographic gates that run every hour.
> 
> **The 5-gate governance pipeline:**
> 
> [1/5] Hermes Gateway Process
> - PID running? ✅
> - API responding? ✅
> 
> [2/5] Append-Only Audit Integrity
> - SQLite audit log: never modified, monotonic timestamps
> - 0 tampered entries
> 
> [3/5] Skill Version Consistency
> - All SKILL.md files git-tracked
> - No uncommitted changes in production
> - Exact behavior reproducibility
> 
> [4/5] Drift Detection
> - 5 benchmark questions run weekly
> - Cosine similarity ≥ 0.85 = safe
> - < 0.85 = alert immediately, stop execution
> 
> [5/5] Health Endpoint
> - JSON governance status
> - Uptime, audit count, last action, drift status
> - 200 OK = integrity intact
> 
> **One command proves all 5 gates:**
> ```
> ./scripts/governance-check.sh
> ```
> 
> Output: ✅ BIRKIN GOVERNANCE INTACT
> 
> This isn't theoretical. It catches real failures. The audit log is append-only. Skills are git-signed. Drift is detected weekly. This is what happens when you apply production clinical governance to an autonomous agent.
> 
> Open source. MIT licensed. Deploy to Hetzner (€13/month) or run locally in Docker (5 minutes).
> 
> If you believe AI agents should be governed like production systems, this is for you.
> 
> 🔗 github.com/NickAiNYC/birkin

---

## 🐦 X Thread #2: Hype + Narrative (For Everyone)

> I built an AI agent that governs itself.
> 
> Not "we logged it." Not "trust us."
> 
> **Cryptographic proof. Every hour.**
> 
> Here's what it does:
> 
> 🛡️ **Append-only audit log** — every action logged once, never rewritten, monotonic timestamps
> 
> 📊 **Git-versioned skills** — `git diff` the agent's brain, see every decision change ever made
> 
> 📈 **Drift detection** — 5 benchmarks run weekly, flags if behavior changes > 15%
> 
> 🏥 **Health check** — JSON governance status, one command proves integrity
> 
> ⚡ **iPhone control** — full-screen PWA, voice input, Telegram alerts, €13/month
> 
> It's not a chatbot wrapper. It's the infrastructure pattern you'd build if you took agent safety seriously.
> 
> Shipped with 5 production skills:
> - Daily intelligence briefing (7 AM ET)
> - Supplier sourcing + veto scoring (Monday mornings)
> - Competitor monitoring (weekly)
> - Directora health watch (6-hourly)
> - Code governance gates (on push)
> 
> Deploy in 10 minutes:
> ```
> ./deploy.sh --hetzner-token ... --cf-token ... --domain ... --openrouter-key ...
> ```
> 
> Try locally in 5 minutes:
> ```
> git clone github.com/NickAiNYC/birkin
> docker compose up -d
> open http://localhost:3000
> ```
> 
> Open source. MIT. No pitch. Just proof.
> 
> 🔗 github.com/NickAiNYC/birkin

---

## 🎯 First Tweet (With Banner)

**Use with the GitHub banner image:**

> I built a self-governing AI agent.
> 
> Not trust. Proof. 
> 
> Governed like clinical infrastructure. Controlled from your iPhone. €13/month.
> 
> github.com/NickAiNYC/birkin
> 
> ⭐ if you want agents that prove their integrity instead of just claiming it.

---

## 🎯 Reply Hooks (Responding to Interest)

If someone replies "This is cool, how do I try it?"

> Clone the repo and run locally in 5 minutes (no server needed):
> ```
> git clone github.com/NickAiNYC/birkin
> cd birkin
> export OPENROUTER_API_KEY=sk-or-v1-xxx
> docker compose up -d && open http://localhost:3000
> ```
> 
> Then run: `docker compose exec hermes ./scripts/governance-check.sh`
> 
> All 5 governance gates work exactly as they do in production.

If someone replies "Can I add my own skill?"

> Yes. Create a SKILL.md file, commit it, deploy it:
> ```
> cd ~/.hermes/skills
> cat > my-skill.md <<'SKILL'
> ---
> name: my-skill
> version: 1.0.0
> ---
> # My Skill
> ...
> SKILL
> 
> git add my-skill.md && git commit -m "Add my-skill v1.0.0"
> ```
> 
> Hermes auto-discovers it. Governance gates validate it. It's immediately audited and versioned.
> 
> See the template: [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md)

If someone replies "How is this different from [competitor]?"

> Competing agents ask for trust.
> 
> Birkin proves integrity:
> 
> ✅ Append-only audit log (can't rewrite history)
> ✅ Git-versioned skills (can't hide what changed)
> ✅ Weekly drift detection (catches behavior change before it breaks things)
> ✅ 5-gate governance check (one command proves everything works)
> 
> No faith required. Just proof.

---

## 📍 LinkedIn Post

> **Built a self-governing AI agent. Here's what I learned about infrastructure governance.**
> 
> Most AI agents today operate on trust. "We log everything. We won't drift. You can reproduce us."
> 
> None of them prove it.
> 
> I spent the last month building Birkin — an autonomous Hermes agent that governs itself like production clinical infrastructure.
> 
> **The architecture:**
> - Append-only SQLite audit (every action logged once, never rewritten)
> - Git-versioned skills (you can `git diff` the agent's decision-making)
> - Weekly drift detection (5 benchmarks, flags behavior change > 15%)
> - 5-gate governance check (one command proves integrity)
> - iPhone PWA control (voice input, Telegram alerts, €13/month)
> 
> **What surprised me:**
> 
> The hardest part wasn't building the agent. It was building the governance layer *around* the agent. Most engineers skip this because it feels like overhead.
> 
> But once you have append-only audit logs + git-versioned skills + automated drift detection, you realize this is the *only* way to run production AI at scale.
> 
> Clinical infrastructure taught me this. Directora (my ledger-based compliance engine) runs on these exact patterns. Turns out they transfer directly to agent infrastructure.
> 
> **Open source. MIT licensed. Deploy in 10 minutes.**
> 
> If you're thinking about autonomous agents at scale, this repo is the governance playbook.
> 
> [Link to GitHub]

---

## 🎬 Suggested Video Title (for demo)

> "Birkin: The First Self-Governing AI Agent | Append-Only Audit, Git-Versioned Skills, Drift Detection"

---

## 📧 HN / Reddit Post Title

> **Birkin: An Autonomous Hermes Agent with Append-Only Governance — Deploy in 10 Minutes**

Description:
> A self-governing AI agent that runs on €13/month, is controlled entirely from your iPhone, and proves its integrity via cryptographic governance gates — append-only audit logs, git-versioned skills, weekly drift detection, and 5-gate validation. Built to show that agent infrastructure can be governed like production clinical systems. Open source, MIT licensed, includes 5 production skills + full deployment automation.

---

## ⭐ Call-to-Action Variants

**For stargazers:**
> ⭐ If you believe AI agents should be governed like production systems, star this repo.

**For builders:**
> 🍴 Building your own skills? Fork this repo and submit a PR.

**For the curious:**
> 🐦 If this changes how you think about agent safety, let me know [@NickAiNYC](https://x.com/NickAiNYC)

---

## 🎯 Hashtag Strategy

Primary: `#AIGovernance` `#HermesAgent` `#OpenSource`

Secondary: `#SelfImprovingAI` `#DevOps` `#InfrastructureAsCode` `#Hermes` `#AgentSafety`

---

## 📊 Metrics to Track

- GitHub stars (daily)
- Forks
- Mentions on X, HN, Reddit
- Deploy.sh runs (via analytics)
- Docker pulls

