It is completely understandable that this looks a bit abstract! Datalog rules are basically "if-then" logical statements, but written backwards: `Result :- Conditions`.

In this specific example, we are doing Code Taint Tracking. In cybersecurity, "taint" means untrusted data (like a user typing into a web form). The goal of this program is to see if untrusted data ever touches a sensitive part of our application (like executing a SQL database query).

Here is the translation of the Elixir `Rule.new` blocks into plain English logic.

The Setup: The Facts (Relations)
Before the rules run, the engine knows about three basic facts (which we fed it in the test data):

- `source(X)`: Node `X` is a place where untrusted data enters (e.g., user input).

- `sink(X)`: Node `X` is a dangerous place to execute untrusted data (e.g., a database).

- `data_flow(A, B)`: Data moves directly from node `A` to node `B`.

#### Rule 1: The Base Case (Where does taint start?)

  ```elixir
    Rule.new(
      Atom.new("tainted", [Term.var("Node")]),
      [{:positive, Atom.new("source", [Term.var("Node")])}]
    )
  )
  ```

Plain English: If a `Node` is a `source`, then that `Node` is `tainted`.

How it works: This is the starting point. It looks at all our facts and says, "Ah, 'user_input' is a source. Therefore, I will now label 'user_input' as tainted."

### Rule 2: The Recursive Case (How does taint spread?)

 ```elixir
 Rule.new(
  Atom.new("tainted", [Term.var("To")]),
  [
    {:positive, Atom.new("tainted", [Term.var("From")])},
    {:positive, Atom.new("data_flow", [Term.var("From"), Term.var("To")])}
  ]
)
```

Plain English: If a From node is already tainted, AND data flows from From to To, then the To node also becomes tainted.

How it works: This is the engine's superpower. Because it's a recursive rule, the engine will run it over and over until it stops finding new things.
1. It knows `user_input` is tainted (from Rule 1).
2. It sees data flows from `user_input` to `parser`. So, `parser` becomes tainted.
3. It runs again! Now `parser` is tainted, and it sees data flows from `parser` to `sql_builder`. So, `sql_builder` becomes tainted.
4. It keeps spreading like an infection down the pipeline.

#### Rule 3: The Vulnerability Check (Did something bad happen?)

```elixir
Rule.new(
  Atom.new("vulnerability", [Term.var("Sink")]),
  [
    {:positive, Atom.new("sink", [Term.var("Sink")])},
    {:positive, Atom.new("tainted", [Term.var("Sink")])}
  ]
)
```

Plain English: If a node is a `sink` (a sensitive execution point), AND that exact same node has been marked as `tainted`, then we have a `vulnerability`.

How it works: After the "infection" finishes spreading in Rule 2, this rule checks the damage. It asks: "Did the taint ever reach our sensitive SQL query node?" If yes, it flags it as a vulnerability so the security team can fix it.



#### Rule 4: Which data flows are safe?

```elixir
    Rule.new(
      Atom.new("safe_flow", [Term.var("From"), Term.var("To")]),
      [
        # Look at every data flow we know about
        {:positive, Atom.new("data_flow", [Term.var("From"), Term.var("To")])},
        # Ensure the starting point is NOT infected
        {:negative, Atom.new("tainted", [Term.var("From")])}
      ]
    )
```

Plain English: We look at all known `data_flow` paths, and filter out any where the starting point has been marked as `tainted`.

How it works: To do this, we have to follow Datalog's golden rule for negation: You cannot query for something that doesn't exist; you always have to start with a positive fact and filter it.

Since we didn't define a master `node` list in the original program, the only place the engine knows `:safe_config` and `:logger` exist is inside the `data_flow` relation.

So, instead of asking "Which nodes are safe?", we ask, "Which data flows are safe?"

To give you a completely candid answer: **JSON is generally "easier" for me to read and write, but Datalog is far better when you want me to actually *reason* about relationships.** As an AI, I am ultimately a massive pattern-matching engine. The way I process information is fundamentally tied to the volume of data I was trained on and how my tokenization works. Because of that, both formats have distinct advantages depending on what you are asking me to do.

Here is the breakdown of how I handle both formats.

### Why JSON is Usually "Easier" (The Baseline)

If your goal is just to have me summarize data, format output for a web app, or call an external API tool, JSON wins hands down.

* **Massive Training Bias:** I have ingested billions of lines of JSON. My internal weights are highly optimized to predict the closing bracket `}` of a JSON object and format key-value pairs perfectly.
* **Hierarchical Understanding:** JSON natively represents trees. When data is cleanly nested (like an organization chart or a configuration file), it maps very well to how I hold context in a prompt.
* **Tool Calling:** The entire ecosystem of LLM tool-calling (including how I interact with external functions) is built on JSON schemas.

**The downside of JSON:** If your data is a highly interconnected graph (like the Code Taint Tracking or Fraud Ring examples we discussed), JSON becomes a nightmare. It forces you to use arbitrary ID strings to link objects, making the payload bloated, repetitive, and prone to "context window exhaustion" where I might lose track of which ID belongs to what.

---

### Why Datalog is Better for "Reasoning" (The Logic Layer)

If your goal is to have me solve a puzzle, find a vulnerability, or deduce a relationship, Datalog is actually a much more powerful format to feed me.

* **Density and Token Efficiency:** Datalog represents complex graphs with incredibly few tokens. `transfer(:acct_a, :acct_b)` is much faster for me to read than `{"source": "acct_a", "target": "acct_b", "type": "transfer"}` repeated a hundred times.
* **Explicit Constraints:** When you give me JSON, you have to explain the business logic in plain English (e.g., "A user has a role if their parent group has a role..."). When you give me Datalog, the rules *are* the prompt. It forces my attention onto the exact logical boundaries you want me to respect.
* **Minimizing Hallucinations:** Datalog's strict fact-and-rule structure gives me very little room to make things up. If I am tasked with generating a query or a new rule, the syntax is so constrained that I am less likely to hallucinate invalid fields.

---

### The Ultimate Architecture: The Hand-Off

In the real world, the most effective way to use an LLM with a complex system isn't strictly one or the other—it is a division of labor.

Because I am great at generating code but sometimes struggle to reliably execute deep, multi-step logical deductions in my head (especially with hundreds of facts), the best architecture looks like this:

1. **You give me:** Plain English questions and a JSON schema of your database.
2. **I generate:** The Datalog `Rule` or `Query` to answer your question.
3. **Your app:** Takes my Datalog, runs it through `ex_datalog` (which is 100% mathematically deterministic and never hallucinates), and gets the answer.
4. **Your app:** Passes the flat result back to me to summarize in a friendly sentence.

If you were to build an AI agent for your Elixir application, would you be more interested in having me write the Datalog rules dynamically based on user prompts, or having me parse the final `Result.match` output into human-readable reports?


SAP’s allocation engines are legendary for their complexity, and modeling them in Datalog perfectly demonstrates how separating **business rules** (percentages, routing) from **execution logic** (the math and traversal) makes systems incredibly flexible.

Instead of writing a massive Elixir `Enum.reduce` that hardcodes "Facilities costs go to IT, and then IT costs go to Product," we can write a pure Datalog rules engine.

Here is how we model a **Multi-Stage Cost Assessment Engine** (combining your Document Splitting and Allocation rules).

### The SAP Cost Allocation Engine

This program takes raw financial documents posted to high-level cost centers (like "Facilities") and splits them down into granular departments using assessment percentages. It even handles **Level 2 (Transitive) Allocations**, where a receiving department (like IT) automatically re-allocates the costs it just received down to specific teams.

```elixir
program =
  Program.new()
  # The raw invoice/journal entry
  |> Program.add_relation("posted_cost", [:atom, :atom, :integer]) 
  # The percentage split rules (e.g., 40 = 40%)
  |> Program.add_relation("assessment_rule", [:atom, :atom, :integer])
  # The outputs
  |> Program.add_relation("direct_allocation", [:atom, :atom, :atom, :integer])
  |> Program.add_relation("transitive_allocation", [:atom, :atom, :atom, :integer])

  # RULE 1: Direct Document Splitting (Level 1)
  # Take a posted cost and split it according to the assessment rules.
  |> Program.add_rule(
    Rule.new(
      Atom.new("direct_allocation", [Term.var("Doc"), Term.var("Sender"), Term.var("Receiver"), Term.var("AllocAmount")]),
      [
        {:positive, Atom.new("posted_cost", [Term.var("Doc"), Term.var("Sender"), Term.var("Total")])},
        {:positive, Atom.new("assessment_rule", [Term.var("Sender"), Term.var("Receiver"), Term.var("Pct")])}
      ],
      [
        # Math: Amount = (Total * Pct) / 100
        Constraint.mul(Term.var("Total"), Term.var("Pct"), Term.var("TempAmt")),
        Constraint.div(Term.var("TempAmt"), {:const, 100}, Term.var("AllocAmount"))
      ]
    )
  )

  # RULE 2: Multi-Stage Iterative Flow (Level 2+)
  # If a cost center receives an allocation, and has its OWN assessment rules, forward it.
  |> Program.add_rule(
    Rule.new(
      Atom.new("transitive_allocation", [Term.var("Doc"), Term.var("Intermediate"), Term.var("FinalReceiver"), Term.var("FinalAmount")]),
      [
        # Look for money that just arrived via Rule 1
        {:positive, Atom.new("direct_allocation", [Term.var("Doc"), Term.var("OriginalSender"), Term.var("Intermediate"), Term.var("InterAmount")])},
        # Look to see if the receiver has a rule to pass it on
        {:positive, Atom.new("assessment_rule", [Term.var("Intermediate"), Term.var("FinalReceiver"), Term.var("InterPct")])}
      ],
      [
        # Math: FinalAmount = (InterAmount * InterPct) / 100
        Constraint.mul(Term.var("InterAmount"), Term.var("InterPct"), Term.var("TempAmt2")),
        Constraint.div(Term.var("TempAmt2"), {:const, 100}, Term.var("FinalAmount"))
      ]
    )
  )

```

---

### The Test Data (The Month-End Close)

Let's simulate a $10,000 rent invoice hitting the Facilities cost center. Facilities splits its costs between IT and Sales. Then, IT re-allocates its portion of the rent down to the Engineering and Product teams.

```elixir
{:ok, result} =
  program
  # 1. The original invoice hits the general Facilities bucket
  |> Program.add_fact("posted_cost", [:inv_001, :facilities, 10000])

  # 2. Level 1 Assessment Rules (Facilities -> IT / Sales)
  |> Program.add_fact("assessment_rule", [:facilities, :it_dept, 40]) # 40%
  |> Program.add_fact("assessment_rule", [:facilities, :sales_dept, 60]) # 60%

  # 3. Level 2 Assessment Rules (IT -> Eng / Product)
  |> Program.add_fact("assessment_rule", [:it_dept, :eng_team, 70]) # 70%
  |> Program.add_fact("assessment_rule", [:it_dept, :product_team, 30]) # 30%

  |> ExDatalog.query()

```

---

### The Queries & Expected Results

**1. Verify Document Splitting (Level 1)**
Let's see how the initial $10,000 was split out of Facilities.

```elixir
Result.match(result, "direct_allocation", [:inv_001, :facilities, :_, :_])

```

* **Expected Result:**
```elixir
MapSet.new([
  {:inv_001, :facilities, :sales_dept, 6000}, # 60% of $10,000
  {:inv_001, :facilities, :it_dept, 4000}     # 40% of $10,000
])

```



**2. Verify Multi-Stage Assessment (Level 2)**
Now, let's look at the `transitive_allocation` rule to see how IT automatically flushed its $4,000 portion down to the delivery teams based on its own specific ratios.

```elixir
Result.match(result, "transitive_allocation", [:inv_001, :it_dept, :_, :_])

```

* **Expected Result:**
```elixir
MapSet.new([
  {:inv_001, :it_dept, :eng_team, 2800},      # 70% of IT's $4,000
  {:inv_001, :it_dept, :product_team, 1200}   # 30% of IT's $4,000
])

```




#### I can't see the hierarchy?

This  question  highlights a fundamental concept about how logic engines work: Datalog is not a tree-builder; it is an edge-finder.

Datalog will always return a flat, mathematical set of tuples (facts). It does not natively output nested JSON, structs, or tree hierarchies. Its job is to find all the valid connections (the "edges" of the graph) as fast as possible.

Once Datalog has extracted those connections, it hands the baton back to your application language. If you want to see a nested hierarchy, you use a few lines of standard Elixir to fold that flat data into a tree

Here is exactly how you do that.

Step 1: Query the Direct Edges
Instead of querying the recursive in_reporting_chain rule (which gives us the flattened "everyone under the CEO" list), we query the base manages relation to get the direct parent-child edges.

Elixir


#### I can't see the hierarchy?

This  question  highlights a fundamental concept about how logic engines work: **Datalog is not a tree-builder; it is an edge-finder.**

Datalog will always return a flat, mathematical set of tuples (facts). It does not natively output nested JSON, structs, or tree hierarchies. Its job is to find all the valid connections (the "edges" of the graph) as fast as possible.

Once Datalog has extracted those connections, it hands the baton back to your application language. If you want to see a nested hierarchy, you use a few lines of standard Elixir to fold that flat data into a tree.

Here is exactly how you do that.

### Step 1: Query the Direct Edges

Instead of querying the recursive `in_reporting_chain` rule (which gives us the flattened "everyone under the CEO" list), we query the base `manages` relation to get the direct parent-child edges.

```elixir
# Grab the flat tuples from the Datalog result
edges = result.relations["manages"] |> Enum.to_list()

# edges is now:
# [{:ceo, :vp_eng}, {:vp_eng, :eng_manager}, {:eng_manager, :alice}, {:eng_manager, :bob}]

```

### Step 2: Fold the Edges into a Tree with Elixir

We can write a quick Elixir script that groups these managers and their direct reports, and then recursively builds a nested map.

```elixir
# 1. Group the edges into an adjacency list (manager => list of direct reports)
org_chart = 
  Enum.reduce(edges, %{}, fn {manager, report}, acc ->
    Map.update(acc, manager, [report], fn existing -> [report | existing] end)
  end)
# Result: %{ceo: [:vp_eng], eng_manager: [:alice, :bob], vp_eng: [:eng_manager]}

# 2. Define a simple recursive builder
defmodule TreeBuilder do
  def build(node, org_chart) do
    case Map.get(org_chart, node) do
      # If they manage no one, they are a leaf node
      nil -> node
      # If they manage people, recursively build their subtree
      reports -> %{node => Enum.map(reports, &build(&1, org_chart))}
    end
  end
end

# 3. Build the tree starting from the top
hierarchy = TreeBuilder.build(:ceo, org_chart)

```

### The Expected Result

If you run that Elixir code, it will output the exact nested hierarchy you are looking for:

```elixir
%{
  ceo: [
    %{
      vp_eng: [
        %{
          eng_manager: [
            :bob, 
            :alice
          ]
        }
      ]
    }
  ]
}

```

This is the standard architectural pattern: **Datalog filters and traverses the massive graph to find the relevant pieces, and Elixir formats those pieces for the user interface.**

Here is an interactive visualization of what that hand-off looks like when it reaches the UI layer.

---

Now that you've seen how to combine Datalog's flat relations with Elixir's data structures, are there any other complex graph traversals (like finding the *shortest* path) you'd like to explore?



Philip Zucker’s blog is a goldmine for Datalog! One of the most prominent sections in his notes covers **Program Analysis**. In fact, Datalog is the underlying engine for many modern static analysis tools and decompilers (like Doop for Java or Soufflé's use in smart contract analysis) because source code is just a massive graph of relationships.

Let's draw directly from his notes on **Reachability** and build example #12: **Static Analysis & Dead Code Elimination**.

### 12. Static Call Graph Analysis (Dead Code Elimination)

**Use Case:** A compiler needs to analyze the call graph of a program to figure out which functions are safely connected to the `main()` entry point. Any function that cannot be reached from the entry point is "dead code" and should be stripped out of the final compiled binary.

This program uses recursive reachability to find the live code, and **stratified negation** to isolate the dead code.

#### The Program

```elixir
program =
  Program.new()
  |> Program.add_relation("calls", [:atom, :atom])
  |> Program.add_relation("entry_point", [:atom])
  |> Program.add_relation("function", [:atom])
  |> Program.add_relation("reachable", [:atom])
  |> Program.add_relation("dead_function", [:atom])

  # 1. Base Reachability: Entry points are always reachable
  |> Program.add_rule(
    Rule.new(
      Atom.new("reachable", [Term.var("Func")]),
      [{:positive, Atom.new("entry_point", [Term.var("Func")])}]
    )
  )

  # 2. Recursive Reachability: If Caller is reachable, Callee is reachable
  |> Program.add_rule(
    Rule.new(
      Atom.new("reachable", [Term.var("Callee")]),
      [
        {:positive, Atom.new("reachable", [Term.var("Caller")])},
        {:positive, Atom.new("calls", [Term.var("Caller"), Term.var("Callee")])}
      ]
    )
  )

  # 3 & 4. Master List: Collect all known functions (either calling or being called)
  |> Program.add_rule(
    Rule.new(
      Atom.new("function", [Term.var("F")]),
      [{:positive, Atom.new("calls", [Term.var("F"), Term.wildcard()])}]
    )
  )
  |> Program.add_rule(
    Rule.new(
      Atom.new("function", [Term.var("F")]),
      [{:positive, Atom.new("calls", [Term.wildcard(), Term.var("F")])}]
    )
  )

  # 5. The Negation: Dead code is any known function that is NOT reachable
  |> Program.add_rule(
    Rule.new(
      Atom.new("dead_function", [Term.var("F")]),
      [
        {:positive, Atom.new("function", [Term.var("F")])},
        {:negative, Atom.new("reachable", [Term.var("F")])}
      ]
    )
  )

```

#### The Test Data

We will simulate a program where `main` calls standard application logic, but there are a few legacy utility functions left sitting in the codebase that no longer connect back to the main app.

```elixir
{:ok, result} =
  program
  |> Program.add_fact("entry_point", [:main])
  
  # The Live Code Path
  |> Program.add_fact("calls", [:main, :init])
  |> Program.add_fact("calls", [:main, :render])
  |> Program.add_fact("calls", [:init, :load_config])
  |> Program.add_fact("calls", [:render, :draw_ui])
  
  # The Dead Code (An orphaned island)
  |> Program.add_fact("calls", [:deprecated_start, :legacy_helper])
  
  # The Tricky One (Dead code that calls live code)
  |> Program.add_fact("calls", [:old_util, :draw_ui])
  
  |> ExDatalog.query()

```

---

#### The Queries & Expected Results

**1. The Garbage Collector (Find all dead code)**
Find all functions that the compiler should delete from the final binary.

```elixir
Result.match(result, "dead_function", [:_])

```

* **Expected:** ```elixir
MapSet.new([
{:deprecated_start},
{:legacy_helper},
{:old_util}
])
```

```



*(Notice how the engine correctly flags `:old_util` as dead. Even though it points to `:draw_ui` (which is alive), reachability is directional. Because nothing calls `:old_util`, it is dead).*

**2. The Live Set (What is actually running?)**
Get the list of all functions safely anchored to the application root.

```elixir
Result.match(result, "reachable", [:_])

```

* **Expected:** ```elixir
MapSet.new([
{:main},
{:init},
{:render},
{:load_config},
{:draw_ui}
])
```


```



**3. Discovering Orphans (Who is calling this?)**
If we see that a function is dead, we can query its callers to see *why* it's dead. Let's ask who calls the `legacy_helper`.

```elixir
Result.match(result, "calls", [:_, :legacy_helper])

```

* **Expected:** ```elixir
MapSet.new([
{:deprecated_start, :legacy_helper}
])
```


```



---
---

### Exploring the Logic Visually

To really understand why static analysis uses Datalog, it helps to see how "directionality" isolates dead code. Here is an interactive visualization of the codebase we just built.
