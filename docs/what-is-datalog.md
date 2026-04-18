# What is Datalog?

Datalog is a declarative logic programming language descended from Prolog,
designed for querying and reasoning over relational data. It is the
database-focused cousin of Prolog — stripped of Prolog's arbitrary
side effects and uncontrolled recursion, and fortified with guarantees
that make it suitable for production systems.

This guide covers what Datalog is, where it came from, how it differs from
Prolog, how it is used in industry, and how you can use it — including as a
knowledge storage and reasoning layer for large language models.

---

## A Brief History

### The Logic Programming Lineage

The story begins in 1972 with **Prolog** (Programmation en Logique), created
by Alain Colmerauer and Philippe Roussel at the University of Aix-Marseille.
Prolog brought a radical idea: instead of writing *how* to compute an answer,
you write *what* is true, and the engine figures out the rest.

Prolog's foundation is **Horn clauses** — a restricted form of first-order
logic where each clause has at most one positive literal:

```
mortal(X) :- human(X).
human(socrates).
```

Read: "X is mortal if X is human. Socrates is human." From these two
statements, Prolog derives `mortal(socrates)`.

Prolog spread through AI research, expert systems, and computational
linguistics through the 1980s. Japan's Fifth Generation Computer Systems
project (1982–1992) chose Prolog as its primary language, bringing
significant attention and funding.

But Prolog had problems that made it unsuitable as a general-purpose
database query language:

1. **The negation problem.** Prolog's negation-as-failure (`\+`) depends on
   clause ordering. Reorder your clauses and you get different answers.
2. **Termination.** Left-recursive rules like `path(X,Z) :- path(X,Y), edge(Y,Z)`
   cause infinite loops unless carefully ordered.
3. **Side effects.** Prolog's `cut` (`!`) and `assert/retract` make programs
   unpredictable and non-declarative.
4. **Direction dependence.** Prolog rules can be run "backwards" — given
   `mortal(X)`, you can ask "who is mortal?" or "is Socrates mortal?" — but
   this bidirectionality creates subtle bugs and complicates optimization.

### Datalog Emerges

**Datalog** was defined in the mid-1980s by researchers working at the
intersection of logic programming and database theory, most prominently
**Serge Abiteboul**, **Richard Hull**, and **Victor Vianu**. Their work
appears in *Foundations of Databases* (1995), but the language crystallized
earlier through papers by Ullman, Maier, and others at Stanford and Bell Labs.

The key insight: if you take Prolog and enforce three constraints, you get
something that is **guaranteed to terminate**, has **predictable negation**,
and is **amenable to database-style optimization**:

| Constraint | Prolog | Datalog |
|---|---|---|
| **Range restriction** | Not enforced | All variables in the head must appear in a positive body literal |
| **Stratified negation** | Negation-as-failure, order-dependent | Negation must be stratifiable (no cycles through `not`) |
| **No function symbols** | Any term | Only constants and variables (no compound terms like `f(X)`) |

These constraints are not limitations — they are **design choices** that
trade expressiveness for guarantees. A Datalog program will always
terminate. A Datalog program will always give the same answer regardless
of rule ordering. A Datalog program's negation is well-founded.

### The Fixpoint Connection

Datalog's semantics are rooted in **fixed-point theory**. Given a set of
rules and facts, the "meaning" of a Datalog program is the **least fixpoint**
— the smallest set of facts that makes all rules true simultaneously.

This is computed bottom-up: start with the given facts, apply rules to derive
new facts, repeat until no new facts are produced. This bottom-up approach
is the opposite of Prolog's top-down resolution (where you start from a
query and work backwards to facts), and it is what makes Datalog
terminable by construction.

The **semi-naive evaluation** algorithm (Bancilhon & Ramakrishnan, 1986) is
the standard optimization: instead of re-evaluating all rules against all
facts on each iteration, only consider facts that are *new since the last
iteration*. This turns naive O(n²) evaluation into efficient delta-based
computation.

---

## Datalog vs. Prolog

The comparison is worth making in detail because it clarifies Datalog's
design goals:

| Property | Prolog | Datalog |
|---|---|---|
| **Evaluation** | Top-down (SLD resolution) | Bottom-up (fixpoint) |
| **Termination** | Not guaranteed | Guaranteed |
| **Negation** | Negation-as-failure, order-dependent | Stratified negation, order-independent |
| **Function symbols** | Allowed (`father(X) :- parent(X, Y)`) | Not allowed (only constants and variables) |
| **Direction** | Bidirectional (queries can run "backwards") | Unidirectional (rules derive new facts) |
| **Side effects** | `cut`, `assert`, `retract` | None (pure declarative) |
| **Result** | One answer at a time (backtracking) | All answers at once |
| **Semantics** | Procedural (clause ordering matters) | Declarative (programmer declares what is true) |

The key philosophical difference: Prolog is a *programming language* where
you express algorithms in logic. Datalog is a *query language* where you
express what you want to know, and the engine decides how to compute it.

---

## Core Concepts

### Facts

Facts are ground tuples — unconditional truths about the world:

```elixir
parent(alice, bob).
parent(bob, carol).
parent(carol, dave).
```

In ExDatalog:

```elixir
program
|> Program.add_relation("parent", [:atom, :atom])
|> Program.add_fact("parent", [:alice, :bob])
|> Program.add_fact("parent", [:bob, :carol])
|> Program.add_fact("parent", [:carol, :dave])
```

### Rules

Rules are conditional truths — if the body is true, the head must be true:

```elixir
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z).
```

In ExDatalog:

```elixir
|> Program.add_rule(
     Rule.new(
       Atom.new("ancestor", [Term.var("X"), Term.var("Y")]),
       [{:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])}]
     )
   )
|> Program.add_rule(
     Rule.new(
       Atom.new("ancestor", [Term.var("X"), Term.var("Z")]),
       [
         {:positive, Atom.new("parent", [Term.var("X"), Term.var("Y")])},
         {:positive, Atom.new("ancestor", [Term.var("Y"), Term.var("Z")])}
       ]
     )
   )
```

The first rule says "X is an ancestor of Y if X is a parent of Y."
The second says "X is an ancestor of Z if X is a parent of Y and Y is an
ancestor of Z." This is **recursion** — a rule references its own head
relation.

### Negation

Datalog supports negation through **stratified negation** — you can write
rules that say "X is true if Y is *not* true", as long as there is no
circular dependency through negation:

```elixir
bachelor(X) :- male(X), not married(X, _).
```

In ExDatalog:

```elixir
|> Program.add_rule(
     Rule.new(
       Atom.new("bachelor", [Term.var("X")]),
       [
         {:positive, Atom.new("male", [Term.var("X")])},
         {:negative, Atom.new("married", [Term.var("X"), Term.wildcard()])}
       ]
     )
   )
```

The engine evaluates strata in order: first derive all positive facts in
stratum 0, then use those results when evaluating negated literals in
stratum 1. This guarantees that `not married(X, _)` is evaluated against
a **complete** set of married couples — not a partial set.

### Constraints (Built-in Predicates)

Rules can include comparison and arithmetic constraints:

```elixir
high_earner(X) :- income(X, S), S > 100000.
tax(X, T) := income(X, A), rate(R), T = A * R.
```

In ExDatalog:

```elixir
|> Program.add_rule(
     Rule.new(
       Atom.new("high_earner", [Term.var("X")]),
       [{:positive, Atom.new("income", [Term.var("X"), Term.var("S")])}],
       [Constraint.gt(Term.var("S"), Term.const(100_000))]
     )
   )
```

---

## How Datalog Is Used in Industry

### 1. Static Analysis and Program Verification

Datalog's most successful industrial application is **static analysis**.
The idea: encode a program's structure (calls, data flow, types) as facts,
write rules that detect bugs, and let the engine compute all violations.

**Soufflé** (https://souffle-lang.github.io/) is a Datalog engine developed
at Oracle Labs specifically for static analysis. It is used in production
at Oracle, Facebook (now Meta), and several other companies to analyze Java,
C++, and Go codebases with millions of lines of code.

Real-world examples:
- **Doop** (Bravenboer & Smaragdakis, 2009) uses Datalog to implement
  points-to analysis for Java — determining every object a reference variable
  can point to. A single Doop analysis can process hundreds of thousands of
  methods and produce millions of derived facts.
- **CodeQL** (GitHub) uses a Datalog-derived language for semantic code
  analysis. Security researchers write queries like "find SQL injection
  vulnerabilities" and the engine finds all matches across a repository.
- **Facebook Infer** uses a Datalog-based abstract interpretation to detect
  memory bugs in C++, Objective-C, and Java code before it ships.

### 2. Networking and Access Control

Datalog's recursive Rule evaluation makes it ideal for computing
reachability in graphs — which is exactly what network access control requires.

**CISCO's** network verification tools use Datalog to check whether
access control policies are correct and consistent. A single rule can
express transitively reachable hosts:

```elixir
reachable(X, Y) :- link(X, Y).
reachable(X, Z) :- link(X, Y), reachable(Y, Z).
```

**Google's** Zanzibar paper (2019) describes a system that evaluates
authorization decisions using a relation-based model that is essentially
Datalog. Google Drive, YouTube, and Cloud use it for the "anyone with the
link can view" permission model.

**Open Policy Agent (OPA)** uses a Datalog-like language (Rego) for
policy decisions across cloud-native infrastructure. Rego is not pure
Datalog — it has some extensions — but its evaluation model is fixpoint-
based.

### 3. Data Integration and ETL

Datalog excels at integration because rules can express both schema mapping
and data cleaning logic in a single declarative specification:

```elixir
customer_email(X, E) :- account(X, E, _).
customer_email(X, E) :- legacy_contact(X, E, _, _).
```

This says: "a customer's email is either from the account system or the
legacy system." The engine computes all matches.

**LogicBlox** (later **Reltio**) built a commercial platform on Datalog
that handled data integration, business rules, and analytics for enterprise
customers in healthcare, retail, and finance.

### 4. Knowledge Graphs and Semantic Web

The **RDF** (Resource Description Framework) and **OWL** (Web Ontology
Language) standards underpinning the Semantic Web are closely related to
Datalog. RDF triples `(subject, predicate, object)` map directly to Datalog
facts, and OWL inference rules (subclass, subproperty, transitivity) map
to Datalog rules.

```elixir
subClass(X, Z) :- subClass(X, Y), subClass(Y, Z).
```

This single rule computes transitive subclass closure — find every class
that an entity belongs to, including through inheritance chains.

### 5. Security and Compliance

**Auth0** (now Okta) published work on using Datalog for access control
policy evaluation. **Aserto** builds authorization engines on Datalog-like
evaluation. The pattern: encode your organization's policies as facts and
rules, then query "can this user access this resource?" and get every
reason why or why not.

---

## Domain-Specific Use Case Examples

### Use Case 1: Social Network — Friend-of-Friend Recommendations

```elixir
# Declare relations
relation "friend", [:atom, :atom]
relation "suggested", [:atom, :atom]
relation "blocked", [:atom, :atom]

# Facts
fact "friend", [:alice, :bob]
fact "friend", [:bob, :carol]
fact "friend", [:bob, :dave]
fact "blocked", [:alice, :dave]

# Rules: suggest friends that are 2 hops away but not already friends
rule "suggested(X, Z) <- friend(X, Y), friend(Y, Z), not friend(X, Z), not blocked(X, Z)"
```

This computes every friend-of-friend recommendation, excludes current
friends, and respects block lists. The transitive closure happens
automatically through fixpoint evaluation.

### Use Case 2: Supply Chain — Bill of Materials Explosion

```elixir
# Direct subcomponents
relation "contains", [:atom, :atom]        # product, subcomponent
relation "lead_time", [:atom, :integer]    # part, days to procure
relation "critical", [:atom, :atom]         # part, risk_category

# Derived: transitive bill of materials
rule "bom_contains(X, Z) <- contains(X, Y), contains(Y, Z)"
rule "bom_contains(X, Z) <- contains(X, Z)"

# Derived: longest lead time in a product's BOM
rule "max_lead(P, D) <- bom_contains(P, C), lead_time(C, D), D > 14"
```

The `bom_contains` rule computes the full transitive closure of subcomponents.
If a car contains an engine, and the engine contains a bolt, then the car
*contains* the bolt — derived automatically, no recursive SQL needed.

### Use Case 3: Fraud Detection — Circular Money Flows

```elixir
relation "transfer", [:atom, :atom, :integer]  # from, to, amount
relation "cycle", [:atom, :atom]

# A transfer cycle exists when money flows from A back to A
rule "cycle(X, Z) <- transfer(X, Y, A), transfer(Y, Z, A), transfer(Z, X, _)"
rule "cycle(X, Z) <- transfer(X, Y, _), cycle(Y, Z)"

# Flag suspicious: large cycles where money returns to origin
rule "suspicious(X) <- cycle(X, X), transfer(_, X, A), A > 10000"
```

Datalog's transitive closure makes cycle detection natural — in SQL, this
requires recursive CTEs that most developers find unintuitive.

### Use Case 4: Bioinformatics — Protein Interaction Networks

```elixir
relation "interacts", [:atom, :atom]
relation "in_pathway", [:atom, :atom]   # protein, pathway
relation "drug_target", [:atom, :atom]   # drug, protein

# Proteins in the same pathway interact
rule "pathway_interaction(P1, P2) <- in_pathway(P1, W), in_pathway(P2, W), interacts(P1, P2)"

# Drugs that target proteins interacting with a disease pathway
rule "repurpose_candidate(D, W) <- drug_target(D, P), pathway_interaction(P, Q), in_pathway(Q, W)"
```

Drug repurposing is a natural fit for Datalog: encode known interactions,
let transitive rules discover chains, and query for candidates.

### Use Case 5: Infrastructure — Network Reachability

```elixir
relation "link", [:atom, :atom]
relation "firewall", [:atom, :atom]       # allows traffic from A to B
relation "reachable", [:atom, :atom]

# Direct reachability through links
rule "reachable(X, Y) <- link(X, Y)"

# Transitive reachability
rule "reachable(X, Z) <- link(X, Y), reachable(Y, Z)"

# Reachability through firewalls
rule "allowed(X, Y) <- reachable(X, Y), firewall(X, Y)"

# Find policy violations: reachable but not allowed
rule "violation(X, Y) <- reachable(X, Y), not allowed(X, Y)"
```

This is essentially what Cisco's formal verification tools and cloud
security groups compute. One fixpoint evaluation replaces pages of
imperative graph traversal code.

---

## Datalog and LLMs: Knowledge Storage and Reasoning

### The Problem

Large language models (LLMs) are powerful pattern matchers with significant
limitations as knowledge stores:

| Problem | Datalog's Answer |
|---|---|
| **Hallucination** — LLMs generate plausible-sounding but false statements | Datalog facts are explicitly true or false. No hallucination. |
| **No guaranteed reasoning** — LLMs can fail on simple transitive chains | Datalog's fixpoint evaluation guarantees all derivable facts are found. |
| **No inconsistency detection** — LLMs can believe contradictory things simultaneously | Datalog's stratified negation and declarative semantics make inconsistencies explicit. |
| **No explainability** — "Why did the model say X?" is opaque | Datalog provenance traces every derived fact to the rules and base facts that produced it. |
| **Context window limits** — LLMs forget facts beyond the context window | Datalog scales to millions of facts without context limits. |

### Architecture: Datalog as a Knowledge Layer for LLMs

```
┌──────────────────────────────────────────────┐
│                  LLM Agent                    │
│  (natural language understanding/generation)│
└──────────────┬────────────────┬───────────────┘
               │                │
        "Tell me about X"   "What follows from Y?"
               │                │
               ▼                ▼
┌──────────────────────────────────────────────┐
│             ExDatalog Engine                  │
│  (declarative rules, fixpoint evaluation,      │
│   stratified negation, provenance)            │
└──────────────┬────────────────┬───────────────┘
               │                │
     Facts derived          Facts asserted
     from text extraction    from structured sources
               │                │
               ▼                ▼
┌──────────────────────────────────────────────┐
│           Knowledge Base (facts)              │
│  parent(alice, bob).  employee(alice, eng).    │
│  manages(alice, carol). ...                   │
└──────────────────────────────────────────────┘
```

### Pattern 1: LLM as Fact Extractor, Datalog as Reasoner

The LLM reads unstructured text and extracts relational facts. Datalog
rules then derive new knowledge that the LLM could not produce reliably:

```elixir
# LLM extracts from a document:
fact "works_for", [:alice, :acme]
fact "works_for", [:bob, :acme]
fact "manages", [:carol, :alice]
fact "manages", [:carol, :bob]

# Datalog rules derive organizational hierarchy:
rule "reports_to(X, Y) <- manages(Y, X)"
rule "colleague(X, Y) <- works_for(X, C), works_for(Y, C), not X = Y"
rule "skip_level(X, Z) <- manages(Y, X), manages(Z, Y)"
```

The LLM can answer "Who are Alice's colleagues?" by querying the Datalog
engine — the answer is derived, not hallucinated.

### Pattern 2: Datalog as Consistency Checker

LLMs generating structured data often produce contradictions. Datalog
rules can detect them:

```elixir
# The LLM asserts two contradictory facts:
fact "alive", [:socrates]
fact "deceased", [:socrates]

# Datalog rule flags contradiction:
rule "contradiction(X) <- alive(X), deceased(X)"
```

A Datalog engine returns `contradiction(socrates)` — the LLM's output
failed a consistency check.

### Pattern 3: Datalog as Agent Memory

An autonomous LLM agent accumulates facts during a session. Datalog rules
maintain derived beliefs:

```elixir
# Agent observes:
fact "in_room", [:agent, :kitchen]
fact "in_room", [:cup, :kitchen]
fact "reachable", [:agent, :cup]    # I can reach the cup

# Rules derive affordances:
rule "can_use(X, Y) <- in_room(X, L), in_room(Y, L), reachable(X, Y)"
rule "in_room(X, L) <- in_room(X, L)"  # stability: things stay where they are

# After observation: "I moved to the living room"
fact "in_room", [:agent, :living_room]   # update

# Derived fact remains: can_use(agent, cup) if the cup is still reachable
# Datalog's fixpoint recomputes only what changed
```

### Pattern 4: Multi-Agent Knowledge Sharing

Multiple LLM agents can share a Datalog knowledge base:

```elixir
# Agent A contributes:
fact "observes", [:agent_a, :smoke, :kitchen]

# Agent B contributes:
fact "observes", [:agent_b, :fire_alarm, :hallway]

# Shared rules derive collective knowledge:
rule "fire_detected(L) <- observes(_, :smoke, L)"
rule "building_emergency <- fire_detected(_), observes(_, :fire_alarm, _)"

# Any agent can query: "Is there a building emergency?"
# The answer is derived from both agents' observations.
```

### Why Not Just Use an LLM?

An LLM can answer "Is Alice an ancestor of Dave?" by pattern-matching on
its training data. But:

1. **Precision**: The LLM might say "probably" or "I think so." Datalog
   says `ancestor(alice, dave)` is `true` or `false` — no hedging.
2. **Completeness**: Ask the LLM "list all ancestors of Dave" and it might
   miss some. Datalog's fixpoint semantics guarantee: if it can be derived,
   it will be.
3. **Size**: The LLM's context window holds maybe 100K tokens. A Datalog
   engine holds millions of facts in storage and evaluates in milliseconds.
4. **Update**: Tell the LLM "actually, Bob is not Carol's parent" and it
   might not correctly retract all consequences. In Datalog, you retract
   `parent(bob, carol)` and re-evaluate — `ancestor(bob, carol)`,
   `ancestor(alice, carol)`, and all transitive consequences update
   correctly.

### Limitations and When Not to Use Datalog with LLMs

Datalog is not a replacement for vector databases or embedding search:

| Task | Use Datalog | Use Vector Search |
|---|---|---|
| Exact relational queries ("who manages Alice?") | ✅ | ❌ |
| Transitive reasoning ("is Dave an ancestor of Alice?") | ✅ | ❌ |
| Consistency checking ("is this fact contradicted?") | ✅ | ❌ |
| Fuzzy similarity ("find documents about supply chains") | ❌ | ✅ |
| Semantic search ("find paragraphs about fraud") | ❌ | ✅ |
| Unstructured reasoning (code generation, summarization) | ❌ | ❌ (use LLM directly) |

The sweet spot: **use Datalog for structured, rule-based reasoning where
correctness matters, and use the LLM for natural language understanding,
extraction, and generation.**

---

## ExDatalog's Place in the Ecosystem

ExDatalog is a pure-Elixir implementation of a bottom-up, semi-naive
Datalog engine with:

- **Stratified negation** — `not` works correctly, with the guarantee that
  negated literals are evaluated against the complete lower stratum.
- **Provenance tracking** — `explain: true` tells you *which rule derived
  each fact*.
- **Telemetry** — `:telemetry` events for query start, stop, and exception.
- **Pluggable storage** — swap the `Storage.Map` backend for ETS, Postgres,
  or any key-value store.
- **No function symbols** — pure Datalog semantics, guaranteed termination.

It is designed to be embedded in Elixir applications that need declarative
reasoning: authorization engines, configuration validation, data pipelines,
and yes — knowledge layers for AI agents.

---

## Further Reading

- Abiteboul, Hull, Vianu. *Foundations of Databases*. 1995. The formal
  reference for Datalog semantics.
- Ceri, Gottlob, Tanca. *What You Always Wanted to Know About Datalog
  (And Never Dared to Ask)*. IEEE TKDE 1989. Classic survey.
- Green, Kass, Bravenboer, Smaragdakis. *Datalog as a Static Analysis
  Tool*. 2010. The Doop approach.
- Soufflé: https://souffle-lang.github.io/ — Production Datalog engine for
  static analysis.
- Ngo, Reinecke, Faber, Batory. *Datalog for the Web*. 2018. Web-scale
  reasoning.
- Zanzibar: https://research.google/pubs/pub48190/ — Google's authorization
  system, Datalog-inspired.