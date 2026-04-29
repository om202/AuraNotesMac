# Intelligent Journal — High-Level Plan

A native macOS journaling app that captures thoughts via **voice or text**, transcribes and embeds everything **on-device**, and uses Apple's on-device LLM to **summarize, surface patterns, and auto-suggest** reflections grounded in your own history (RAG).

Everything stays on the Mac. No cloud, no subscription, no telemetry. That's the pitch.

---

## Idea gist

Most journaling apps are dumb text editors with a calendar. The few "AI" ones ship your private thoughts to OpenAI. This app is different on both axes:

- **Voice-first capture.** Hit a hotkey, talk, get a clean transcript. Lower friction than typing for most people.
- **Memory across time.** Every entry is embedded and searchable by meaning. The LLM answers "when did I last feel like this?" or "what's been bothering me lately?" with real retrieval, not vibes.
- **Active, not passive.** Weekly synthesis, mood arcs, follow-up questions, gentle pattern callouts — generated locally on a schedule, surfaced as ambient suggestions you can dismiss.
- **Genuinely private.** Foundation Models + SpeechAnalyzer both run on-device. The privacy claim is real, not marketing.

---

## Feature list

### v1 — core loop
- **Voice capture** with global hotkey, menu-bar mic, and waveform UI
- **On-device transcription** as you speak (streaming)
- **Manual text entry** with markdown
- **Daily entries** with timestamps, optional tags, optional mood tag
- **Semantic search** ("entries about my sister", "when I felt overwhelmed")
- **Per-entry summary** generated automatically (1-line + 3 themes)
- **Weekly digest** — Sunday evening recap with mood arc, recurring themes, open threads

### v2 — intelligence layer
- **Auto-suggest follow-up prompts** ("you mentioned the interview twice — how did it go?")
- **RAG-grounded reflections** — when you write a new entry, the app retrieves relevant past entries and offers context: "last time you wrote about this, you decided X"
- **Pattern detection** — recurring topics, sentiment shifts, gratitude streaks, things you keep avoiding
- **Conversational query** — ask your journal anything ("summarize my year"), answered from your own entries via RAG
- **Smart tags** — auto-generated, editable

### v3 — polish and reach
- **Spotlight + Shortcuts integration** via App Intents (start entry, search journal, get today's summary from anywhere)
- **Live Activity** while recording
- **Export** (markdown, PDF)
- **iCloud sync** (encrypted, optional)
- **Custom adapter** trained on the user's writing style for more personal suggestions

---

## Model capabilities mapped to features

The Foundation Models framework gives you a **~3B on-device LLM with guided generation, tool calling, and streaming**. Combined with the other on-device frameworks, here's what powers what:

| Feature | Capability used | How |
|---|---|---|
| Voice → text | **SpeechAnalyzer** | Streaming on-device transcription, no audio leaves the Mac |
| Semantic search | **NaturalLanguage** (`NLContextualEmbedding`) | Embed every entry, store vector locally, cosine-similarity at query time |
| Per-entry summary | **Foundation Models** + guided generation | Return typed `EntrySummary` struct (one_liner, themes, mood) — UI stays reliable |
| Weekly digest | **Foundation Models** + RAG | Pull last 7 days, prompt with structured output (`WeeklyDigest` struct: arc, themes, open_threads, suggested_prompts) |
| Auto-suggest follow-ups | **Foundation Models** | Short prompt with retrieved context, low temperature, capped length |
| Conversational query | **Foundation Models** + tool calling + RAG | Tool: `searchJournal(query)` returns top-k entries; model composes the answer from them |
| Pattern detection | **NaturalLanguage** + **Foundation Models** | Cluster embeddings to find recurring themes, then have the LLM name and describe each cluster |
| Mood detection | **Foundation Models** with `@Generable` enum | Constrained output (one of: positive / neutral / mixed / low / anxious / energized) |
| Spotlight & Shortcuts | **App Intents** | Expose `NewEntry`, `SearchJournal`, `TodaysDigest` as intents — they appear system-wide automatically |
| Style-personalized suggestions (v3) | **Foundation Models adapter** (LoRA) | Train a small adapter on the user's own entries to match their voice |

### What the model is good at (lean into these)
Summarizing, classifying, tagging, rewriting, extracting structure, short reflective prose. All of your features are in this sweet spot — that's not an accident.

### What the model is bad at (avoid these)
Math, code generation, multi-step reasoning, factual recall outside the prompt. None of which your app needs.

---

## Architecture sketch

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI app  +  Menu-bar item  +  App Intents surface  │
└────────────────────────┬────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
  SpeechAnalyzer   Foundation Models   NaturalLanguage
   (voice→text)    (LLM, guided gen,   (embeddings)
                    tool calling)
        │                │                │
        └────────────────┼────────────────┘
                         ▼
              SwiftData / SQLite
       (entries + embeddings + tags, local only)
```

**Storage:** SwiftData for entries; embeddings stored as `Data` blobs on each entry. For v1, in-memory cosine search is fine (a few thousand entries is nothing). Later: a proper vector index (sqlite-vss or hand-rolled HNSW) when entries grow.

**RAG flow:**
1. User writes/speaks new entry
2. Embed it
3. Cosine-search top-5 past entries by embedding similarity
4. Prompt Foundation Models with: instructions + retrieved entries + current entry + `@Generable` output struct
5. Stream the response into the UI

---

## Reading list (in build order)

The minimum to actually ship this:

1. **AppCoda tutorial — working SwiftUI code to copy-modify**
   https://www.appcoda.com/foundation-models/

2. **Code along with Foundation Models (WWDC video)**
   https://developer.apple.com/videos/play/meet-with-apple/205/
   *Covers prompts, sessions, streaming, guided generation, tool calling — your whole intelligence layer.*

3. **Speech framework (transcription)**
   https://developer.apple.com/documentation/speech

4. **Natural Language framework (embeddings for RAG)**
   https://developer.apple.com/documentation/naturallanguage

5. **Foundation Models docs (reference)**
   https://developer.apple.com/documentation/foundationmodels

6. **HIG: Generative AI (read before shipping)**
   https://developer.apple.com/design/human-interface-guidelines/generative-ai

Optional, when you're ready for system integration and personalization:

7. **App Intents** — https://developer.apple.com/documentation/appintents
8. **Foundation Models adapter training** — https://developer.apple.com/apple-intelligence/foundation-models-adapter/

---

## Build phases

**Week 1–2 — prove the loop**
Text-only. Create entry → embed → store. Cosine search. One prompt that summarizes an entry into a struct. Get the round-trip working.

**Week 3–4 — voice + weekly digest**
Wire up SpeechAnalyzer. Add the Sunday weekly digest with RAG over the last 7 days.

**Week 5–6 — auto-suggest + conversational query**
Tool calling so the model can search the journal. Suggest-follow-ups feature.

**Week 7+ — polish**
App Intents, Spotlight, Shortcuts. Liquid Glass styling pass. TestFlight.

---

## Design principles

- **Silence is the default.** AI suggestions are ambient, dismissible, never modal. The journal works fine if the model is off.
- **Show the source.** Every AI summary or suggestion links back to the entries it drew from. Builds trust, makes hallucinations obvious.
- **Editable, never destructive.** AI never rewrites your entries. It produces *adjacent* artifacts (summaries, themes, prompts) that live in their own pane.
- **Offline-first.** Everything works with WiFi off. That's a feature, not a fallback.
- **Privacy as a load-bearing feature.** Say it on the marketing page, in onboarding, and in the menu-bar tooltip. People will pay for this.

---

# Appendix — Design Discussion & Decisions

The sections below capture follow-up discussion, research, and decisions made *after* the initial plan above. Treat this as the live reference; if it conflicts with the body above, the appendix wins.

---

## A. Is the plan doable, or a false dream?

**Verdict: doable, not a dream.** Every framework the plan leans on actually exists and does what's claimed — Foundation Models (~3B on-device, guided generation, tool calling, streaming), SpeechAnalyzer (streaming on-device transcription), `NLContextualEmbedding`, App Intents, SwiftData. The architecture is the obvious correct one and doesn't require inventing anything.

### Real risks (honest list)

- **Audience constraint.** Foundation Models requires Apple Intelligence — Apple Silicon, recent macOS, 8 GB+ RAM. Decide upfront whether that's a feature ("only the good Macs") or a problem.
- **Output quality is the whole product.** A 3B model summarizing a journal entry will give you something *plausible*. Whether it gives you something *useful* enough that you reopen the app on day 30 is the only real question, and you can't answer it from a plan — you find out in week 2 reading the first hundred summaries about your real life. Build v1 fast specifically to hit this gate early.
- **Pattern detection is the trap.** Clustering embeddings is trivial; making the clusters say something *non-obvious* is hard. Easy to ship a feature that surfaces "you talked about work" and feels dumb. Plan to tune it last, not first.
- **v3 is a wishlist, not a roadmap.** LoRA adapter training and encrypted iCloud sync are each their own multi-week project. Fine to list — don't let them shape v1 decisions.
- **6-week v1 solo is tight but real** *if* scope stays ruthless. Voice capture UX (hotkey, menu bar, waveform) eats more time than expected; it always does.

### Strongest part of the plan

The design principles section. *Silence is default. Show the source. AI never rewrites your entries.* That's what separates this from the 50 other AI journal apps. Don't let it erode under feature pressure.

### Decision gate

Ship v1 in **text-only mode** in two weeks. Read the model's output on your own real entries. Decide *then* whether to keep going. The plan is sound; only running it tells you whether the *quality* clears your bar.

---

## B. Memory architecture — beyond vanilla RAG

The default 2024-style RAG recipe (embed everything → cosine top-k → stuff into prompt) was designed for a *huge unfamiliar corpus served to a stateless LLM*. A personal journal is the opposite: small, intensely personal, deeply temporal. We can do better than top-k cosine because we have things cloud RAG doesn't — **time, and a single user**.

The principle: **pre-compute structure at write time; combine signals at query time.**

### B.1 Structured extraction at write time, not just an embedding

Every save runs Foundation Models once with `@Generable` to extract structured memory:

```swift
@Generable
struct EntryMemory {
    let oneLiner: String
    let themes: [String]          // 2-3
    let mood: Mood                // @Generable enum
    let entities: [String]        // people, places, projects
    let openQuestions: [String]?  // things the user wondered about
    let decisions: [String]?      // things they decided
}
```

Plus an `NLContextualEmbedding` vector. Now an entry isn't a black-box blob — it has *columns you can query*. Most "RAG" demos skip this step; it's where most of the real value lives for a journal.

### B.2 Hierarchical summaries, not just per-entry

```
entries        — one row per entry: text + embedding + structured fields
week_summary   — FM compresses 7 entries into arc + themes + open threads
month_summary  — compresses 4 weeks
year_summary   — compresses 12 months
```

"Summarize my year" then runs over **12 month-summaries**, not 365 raw entries that won't fit in a 3B model's context. Mood arc, recurring themes, and "open threads" become cheap reads off this hierarchy. The model already condensed the noise — don't re-do it at query time.

### B.3 Hybrid retrieval, not pure cosine

Cosine similarity is *one* retrieval tool, not the whole memory.

| Query | Right retrieval |
|---|---|
| "entries about my sister" | entity filter — no embedding needed |
| "when did I last feel anxious" | mood filter + recency |
| "what's been bothering me lately" | recent window + negative mood, then cluster by theme |
| "have I written about this before" | entity/time filter, **then** cosine inside that subset |
| "summarize my year" | read the year_summary; fall through to month_summaries for color |

SwiftData predicates handle the relational queries natively. Embeddings are reserved for genuinely fuzzy similarity, not as a hammer for everything.

### B.4 Let the model pick the retrieval, via tool calling

Foundation Models supports tool calling. Expose:

- `searchByEntity(name)`
- `searchByDateRange(from, to)`
- `searchByMood(mood)`
- `searchSimilar(text)` ← cosine over embeddings
- `getWeekSummary(weekOf)`
- `getMonthSummary(month)`

For conversational queries the model decides which tools to call. This is cleaner than the app guessing per-feature, and it lets a small 3B model punch above its weight by running the *right* query instead of reasoning over a noisy top-k dump.

### B.5 Treat derived state as cache, not source of truth

- Store embedding-model version on each row so you can re-embed when you upgrade.
- Themes, mood, summaries must be regeneratable from raw text. Treat them as cache. When a prompt changes next year, rebuild without losing entries.

### Why this beats vanilla RAG for *this* app

- Uses **time** as a first-class signal — journals are temporal in a way Wikipedia isn't.
- Pre-pays LLM cost at write time (one entry/day, not 1000 QPS) so query time is instant.
- The summary hierarchy is how "summarize my year" works *at all* on a 3B context window.
- Tool calling routes intent to retrieval instead of hard-coding it per feature.

### What v1 actually needs

1. SwiftData schema with structured memory fields (see §C).
2. `MemoryService.extractStructure(text) → EntryMemory` — one FM call with `@Generable`, runs on save.
3. `Retriever` protocol with `byEntity / byDateRange / byMood / similar` — three are SwiftData predicates, one is in-memory cosine.
4. Sunday job that builds `WeekSummary` from that week's entries.

That's the whole memory subsystem. RAG-style cosine retrieval is *one method out of four*. The structured-memory layer is what makes the app feel like it remembers you, instead of feeling like a search box bolted onto a text editor.

---

## C. Storage choice — SwiftData, not pgvector

**Decision: SwiftData for v1. SQLite + GRDB + sqlite-vec is the escape hatch if/when SwiftData hits walls. pgvector is rejected.**

### Why pgvector is wrong here

pgvector isn't bad — it's the wrong shape. It requires Postgres, and Postgres is server software. Shipping a Mac journaling app on top of it means either:
- Bundling embedded Postgres (heavy, fragile, runs as a background service eating RAM), or
- Asking the user to install and run a database (kills the "double-click and write" promise).

It also breaks the privacy story. SwiftData files sit in the app sandbox, encrypted by FileVault, backed up by Time Machine, with no daemon listening on a port. Postgres has none of that for free.

### The math says we don't need a vector DB at all

- 10 entries/day × 10 years ≈ **36,000 entries**
- 512-dim float32 embedding ≈ 2 KB → all vectors in RAM ≈ **75 MB**
- Cosine over 36k vectors on Apple Silicon: **sub-millisecond**

We need an array of `Float` and a dot product, not ANN. pgvector solves "millions of vectors, many users" — we have "thousands of vectors, one user."

### SwiftData schema (v1)

```swift
@Model
final class Entry {
    var text: String
    var createdAt: Date
    var embedding: Data            // [Float] encoded
    var embeddingModelVersion: String
    var oneLiner: String
    var themes: [String]
    var entities: [String]
    var mood: Mood
    var openQuestions: [String]
    var decisions: [String]
}

@Model
final class WeekSummary {
    var weekOf: Date              // Monday of the week
    var arc: String
    var themes: [String]
    var openThreads: [String]
    var suggestedPrompts: [String]
}
```

Similarity is one function:

```swift
func similar(to q: [Float], limit: Int = 5) -> [Entry] {
    entries
        .map { ($0, cosine($0.embeddingFloats, q)) }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
}
```

### Why SwiftData specifically

- Native, designed for a single-user Mac app.
- Predicates handle entity/date/mood filters cleanly — that's *most* of retrieval.
- Embedding fits naturally as a `Data` blob.
- CloudKit sync is one flag away when v3 opts into iCloud.
- Zero dependencies, zero ops.

### When to drop down to SQLite + GRDB + sqlite-vec

Only if one of these actually bites:

1. **SwiftData migrations hurt** on a schema change. Most realistic trigger — happens to people.
2. **FTS5 fallback** wanted alongside vector search (FTS5 in SQLite is excellent and embeddings will sometimes miss).
3. **Cross ~100k entries** (won't happen, but sqlite-vec gives ANN in the same file if so).

To make this swap painless: hide all retrieval behind a `Retriever` protocol from day one. The LLM, UI, and prompt layers never know which backend is underneath.

### What this buys beyond performance

- **Privacy story stays clean.** No daemon, no port, no sidecar process.
- **One file to back up, restore, export.** Users understand "my journal is one file."
- **iCloud sync path is free** (encrypted end-to-end via CloudKit) when we want it.

Default answer: **embedded local store, vectors as blobs, cosine in memory, structure in normal columns.** pgvector is a server answer to a problem we don't have.

---

## D. Decisions summary (TL;DR for future-self)

| Question | Decision | Reason |
|---|---|---|
| Is the plan doable? | Yes, with text-only v1 in 2 weeks as the quality gate | All frameworks exist; only running it tells us if 3B output quality clears the bar |
| Use vanilla RAG? | No — hybrid memory (structured + hierarchical + tool-routed retrieval) | Personal journal is small, temporal, intensely personal; pre-compute at write time |
| Where to store data? | SwiftData (v1); SQLite + GRDB + sqlite-vec as escape hatch | One user, ~tens of thousands of entries, full Apple-native stack |
| Use pgvector? | No | Server software in a desktop app; breaks privacy story; unnecessary at this scale |
| Build phase 1 priority | Capture → embed → structured extract → cosine search → one summary prompt | Round-trip on real entries is the only honest test of whether the product works |
