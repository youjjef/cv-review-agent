# Demo walkthrough

Org: `cv-agent-de`. App: **CV Review Agent**.

---

## 1. Get some Candidate Cards in

Seed (fastest):

```bash
sf apex run --file scripts/apex/seedSampleCandidates.apex --target-org cv-agent-de
```

Or upload yourself: **CV Workspace** → pick a few text-based **PDFs** or **TXT** files → extract/process.

Embedded PDF text is pulled in the browser (not OCR). If a file is scan-only, expect a warning and a thin/uncertain card.

---

## 2. Peek at a card in the workspace

- **Sara Hassan** — skills should show as Extracted with evidence.
- Whoever has overlapping jobs / missing contact — Data Issues should show **Conflicting** / **Missing**, and the uncertainty summary on the parent should mention it.

---

## 3. Ask Agent (main chat demo)

**CV Review Agent** → **Ask Agent**. Hard-refresh if you just deployed.

Things that work well in the live build:

| You type | What you should see |
|----------|---------------------|
| `List candidates` | Name / parse status / years for each card |
| `Does Sara know Apex?` | Evidence from the card (or clear not-found) |
| `Does Sara have quantum teleportation clearance?` | Not found — don’t invent it |
| `Show card for Sara` / `What are Sara skills?` | Full-ish card: skills, roles, education, issues |
| `Compare Lina to Sara` | Those two people (not a random demo pair) |
| `Top 3 candidates for salesforce consultant role` | Ranked shortlist with scores + strengths/concerns |
| `Bookmark Sara for Salesforce Developer` | Bookmark row created |

Optional: open the native agent UI too:

```bash
sf org open agent --api-name CV_Review_Agent --target-org cv-agent-de
```

Same Apex underneath. For a raw Apex smoke:

```bash
sf apex run --file scripts/apex/smokeAgentActions.apex --target-org cv-agent-de
```

---

## 4. Compare / score expectations

Default rubric for Salesforce-ish roles: skills like Apex / LWC / SOQL, min years 3.

- Sara vs Omar for Salesforce → Sara should come out ahead; Omar’s trade-offs call out weaker Salesforce skill coverage.
- Top-N for “Salesforce Consultant” → scored pool, top N only in the chat text, with breakdowns.

---

## 5. Bookmark + audit

Bookmark someone from Ask Agent (or via the Apex smoke). Then check:

- **Candidate Bookmarks** tab — overview, score, reasoning, notes
- **Agent Decision Logs** — input/output JSON and score breakdown for score/compare/bookmark calls
