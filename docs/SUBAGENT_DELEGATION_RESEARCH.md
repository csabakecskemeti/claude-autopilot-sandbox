# Subagent Delegation Research

## Problem Statement

Large tasks exceed context window size. We need the agent to proactively delegate work to subagents to:
1. Keep main context clean (only summaries return)
2. Parallelize work across multiple subagents
3. Prevent context bloat from verbose operations (tests, logs, file searches)

---

## LOCAL LLM CONSTRAINTS

**This section evaluates all patterns through the lens of local LLM deployment.**

### Hardware Reality

| Constraint | Impact on Agent Design |
|------------|------------------------|
| Single GPU | Cannot run multiple agents truly in parallel |
| Inference speed | Each subagent spawn = significant latency |
| VRAM limits | One model loaded at a time (no model routing) |
| No per-token cost | Cost optimization patterns don't apply |
| Context window | Varies: 8k-128k+ depending on model |
| Instruction following | Less reliable than cloud APIs |

### What Works with Local LLMs

| Pattern | Verdict | Why |
|---------|---------|-----|
| Sequential subagents | ✅ YES | One at a time is fine |
| Hierarchical coordinator | ✅ YES | Simple chain of command |
| Context isolation | ✅ YES | Critical - local models have smaller windows |
| Anti-drift checkpoints | ✅ YES | Local models drift more - need validation |
| Explicit delegation rules | ✅ YES | Local models need clearer instructions |
| File-based memory | ✅ YES | Simple, reliable, no vector DB needed |

### What Doesn't Work with Local LLMs

| Pattern | Verdict | Why |
|---------|---------|-----|
| 100+ agent swarms | ❌ NO | GPU bottleneck, too slow |
| Parallel subagents | ⚠️ LIMITED | Sequentially processed anyway |
| Dynamic model routing | ❌ NO | Can't hot-swap models (VRAM) |
| Complex meta-cognition | ❌ NO | Local models not reliable enough |
| Self-learning loops | ⚠️ RISKY | May amplify errors |
| Vector memory retrieval | ⚠️ MAYBE | Adds complexity, simpler approaches work |

### Local LLM Best Practices

1. **Keep delegation rules SIMPLE and EXPLICIT**
   - Local models struggle with nuanced "when to delegate" decisions
   - Use hard rules: "If task has 5+ files, ALWAYS delegate"

2. **Prefer sequential over parallel**
   - Don't pretend parallelism exists
   - Chain: explore → plan → implement → test → verify

3. **Use file-based context passing**
   - Write summaries to files between agents
   - More reliable than complex memory systems

4. **Aggressive context conservation**
   - Local context windows are precious
   - Delegate EVERYTHING that produces verbose output

5. **Stronger supervisor validation**
   - Local models make more mistakes
   - Supervisor should run more checks, not fewer

## Key Findings

### How Subagent Delegation Works

From [Claude Code Docs](https://code.claude.com/docs/en/sub-agents):

> When Claude encounters a task that matches a subagent's description, it delegates to that subagent, which works independently and returns results.

Each subagent:
- Runs in its **own context window** (starts empty except for task prompt)
- Only returns a **summary** to the parent
- Cannot spawn other subagents (prevents infinite nesting)

### Why This Solves Context Issues

> Running tests, fetching documentation, or processing log files can consume significant context. By delegating to a subagent, the verbose output stays in the subagent's context window. Only the summary returns to the parent.

### How to Force More Delegation

#### 1. Add Delegation Rules to CLAUDE.md

Add explicit rules that force delegation for multi-file or complex tasks:

```markdown
## Agent Delegation Rules (MANDATORY)

For ANY task that touches more than 3 files or involves refactoring:
1. First invoke the `explore` subagent to map the relevant files
2. Use its output to invoke the `plan` subagent with specific scope
3. Only then invoke `worker` with the approved plan

For testing/verification:
- ALWAYS delegate test runs to a subagent (keeps verbose output isolated)
- ALWAYS delegate file searches to `explore` subagent

For implementation:
- Break large features into independent subtasks
- Delegate each subtask to a separate `worker` subagent
- Run independent workers in parallel

NEVER execute directly if the task can be delegated.
```

#### 2. Write Proactive Subagent Descriptions

Include "use proactively" in descriptions:

```yaml
---
name: worker
description: "General-purpose worker. Use PROACTIVELY to delegate ANY independent, self-contained task. Automatically spawn for multi-step work."
---
```

#### 3. Create Specialized Subagents

Create agents for specific task types (from [this setup pattern](https://gist.github.com/tomas-rampas/a79213bb4cf59722e45eab7aa45f155c)):

| Agent | Model | Purpose |
|-------|-------|---------|
| `plan-agent` | Opus | Strategic planning, architecture |
| `reader-agent` | Haiku | File analysis, information extraction |
| `maker-agent` | Sonnet | Code creation, implementation |
| `test-agent` | Haiku | Test execution, QA |
| `debug-agent` | Haiku | Troubleshooting, root cause analysis |
| `docs-agent` | Haiku | Documentation generation |

**Cost optimization**: Use Haiku for read-only exploration, Sonnet for implementation.

#### 4. Use @-mention for Guaranteed Delegation

Since April 2026, you can type `@agent-name` in prompts for direct invocation:

```
@worker implement the authentication module
```

This guarantees delegation rather than leaving it to Claude's judgment.

### Master-Clone Architecture

An alternative pattern from the community:

> Use Claude's built-in Task(...) feature to spawn clones of the general agent. Put all key context in the CLAUDE.md. Then, let the main agent decide when and how to delegate work to copies of itself.

This gives context-saving benefits without needing many specialized subagents.

### Built-in Subagents

Claude Code includes these automatically:

| Agent | Model | Purpose |
|-------|-------|---------|
| `Explore` | Haiku | Codebase search, file discovery (read-only) |
| `Plan` | Inherit | Gather context during plan mode |
| `general-purpose` | Inherit | Complex multi-step tasks |

## Implementation Recommendations

### Option A: Update CLAUDE.md with Delegation Rules

Add to `claude-backup/CLAUDE.md`:

```markdown
## Mandatory Delegation

You MUST delegate to subagents for:

1. **Any task involving 5+ files** → Use `worker` subagent
2. **File/code searches** → Use built-in `Explore` subagent
3. **Test execution** → Delegate to keep verbose output isolated
4. **Multi-step features** → Break into subtasks, delegate each to `worker`
5. **Research/exploration** → Use `web-researcher` or `Explore`

### Delegation Pattern

For large tasks:
1. Spawn `Explore` to understand codebase scope
2. Create task breakdown
3. Spawn parallel `worker` subagents for independent subtasks
4. Aggregate results

### Context Conservation

- NEVER read large files directly if you can delegate
- ALWAYS delegate test runs (output stays in subagent context)
- ALWAYS delegate documentation fetching
```

### Option B: Add More Specialized Subagents

Create targeted subagents in `agents-backup/`:

1. `file-worker.md` - Single file modifications
2. `test-runner.md` - Execute and report test results
3. `research.md` - Documentation and API research
4. `refactor.md` - Code restructuring tasks

### Option C: Dynamic Delegation via Stop Hook Feedback

When supervisor returns "not_complete", append delegation hints:

```bash
# In block_stop(), add delegation guidance
reason="$reason

CONTEXT HINT: If this task is large, delegate subtasks to worker subagents.
Use 'Explore' for file searches. Use 'worker' for independent subtasks."
```

## Relevant Configurations

### Subagent File Location

```
~/.claude/agents/          # User-level (all projects)
.claude/agents/            # Project-level (this project only)
```

For our Docker setup:
```
agents-backup/             # Copied to ~/.claude/agents/ in container
```

### Frontmatter Options

```yaml
---
name: worker
description: "Use proactively for any self-contained task"
model: inherit              # or: sonnet, haiku, opus
tools: Read, Write, Edit, Bash, Grep, Glob, Task
maxTurns: 50               # Limit turns to prevent runaway
background: true           # Run in background (parallel)
---
```

## Next Steps for Our Project

### Immediate Actions

1. **Update `claude-backup/CLAUDE.md`** with simple, explicit delegation rules:
   ```markdown
   ## Mandatory Delegation (LOCAL LLM RULES)

   You are running on a LOCAL LLM with limited context. CONSERVE CONTEXT.

   ALWAYS delegate these tasks to subagents:
   - File searches → use `Explore` (built-in)
   - Test execution → delegate (verbose output stays isolated)
   - Any task touching 5+ files → use `worker` subagent
   - Documentation research → use `web-researcher`

   NEVER:
   - Read large files directly if you can delegate
   - Keep test output in main context
   - Try to hold entire codebase in context

   Workflow for large tasks:
   1. Spawn `Explore` to find relevant files
   2. Get summary back (not full content)
   3. Spawn `worker` for each independent subtask
   4. Aggregate results
   5. Call supervisor
   ```

2. **Simplify subagent definitions** - ensure they work with local LLMs:
   - Remove complex instructions local models won't follow
   - Add explicit "return a SHORT summary" instructions
   - Set `maxTurns` to prevent runaway subagents

3. **Add context conservation to supervisor feedback**:
   ```bash
   # In stop hook, append to feedback:
   "CONTEXT HINT: Delegate subtasks to worker subagents.
    Keep main context clean."
   ```

### Testing Strategy

1. Run todoapp with PDF export task
2. Monitor Langfuse for:
   - Context size per turn
   - Subagent spawning frequency
   - Summary quality (are they concise?)
3. Iterate on delegation rules

### Future Enhancements

1. **Token counting** - Track context usage, warn when high
2. **Automatic summarization** - Compress context before it overflows
3. **Subagent result caching** - Don't re-explore same files

---

## Advanced: External Agent Orchestration Frameworks

### Evaluation Criteria for Local LLMs

Each framework is evaluated on:
- 🟢 Works well with local LLMs
- 🟡 Partially applicable / needs adaptation
- 🔴 Not practical for local deployment

---

### Claude-Flow / Ruflo (github.com/ruvnet/claude-flow)

An enterprise-grade multi-agent orchestration platform that deploys 100+ coordinated agents.

**Key Patterns:**

1. **Swarm Organization with "Queens"** 🟡
   - Agents organized into swarms led by coordinator "queens"
   - Queens prevent goal drift and coordinate work
   - 3 queen types: Strategic, Tactical, Adaptive
   - 8 worker types for task-specific assignment
   - **Local LLM verdict**: Queen/coordinator pattern ✅, but limit to 1-3 agents max

2. **Anti-Drift Configuration** 🟢
   ```yaml
   topology: "hierarchical"    # Single coordinator enforces alignment
   maxAgents: 8                # Limit parallel agents - FOR LOCAL: use 2-3
   strategy: "specialized"     # Task-specific agents
   ```
   - **Local LLM verdict**: Critical! Local models drift more than cloud APIs.

3. **3-Scope Memory Architecture** 🟡
   - Project-level: Shared across all agents
   - Local: Per-agent context
   - User-scoped: Cross-session persistence
   - Vector memory with HNSW indexing for fast retrieval
   - **Local LLM verdict**: File-based approach simpler. Skip vector DB complexity.

4. **Intelligent Task Routing** 🔴
   - 89% accuracy based on learned patterns
   - Cost-based provider selection (Claude, GPT, Gemini, Ollama)
   - Automatic task decomposition across domains
   - **Local LLM verdict**: No model routing possible (single GPU). Use fixed rules instead.

5. **Learning Loop** 🔴
   ```
   RETRIEVE → JUDGE → DISTILL → CONSOLIDATE → ROUTE
   ```
   - **Local LLM verdict**: Too complex. Local models can't reliably self-improve.

**Applicable for local**: Hierarchical coordinator (our supervisor), anti-drift validation, simple file-based memory.

### SAFLA (github.com/ruvnet/SAFLA)

Self-Aware Feedback Loop Algorithm - a neural network for autonomous agents with:

1. **Hybrid Memory System** 🟡
   - Vector Memory: Semantic embeddings for similarity retrieval
   - Episodic Memory: Sequences of events/experiences
   - Semantic Memory: Knowledge graphs of concepts
   - Working Memory: Active context with attention
   - **Local LLM verdict**: Interesting but complex. Simple file-based summaries may work better.

2. **Meta-Cognitive Engine** 🔴
   ```
   Experience → Learn → Adapt → Improve
   ```
   Identifies patterns, modifies behavior based on success, progressively enhances.
   - **Local LLM verdict**: Local models can't reliably do meta-cognition. Skip this.

3. **Safety Framework** 🟢
   - Constraint enforcement
   - Risk assessment before actions
   - Rollback capability
   - Emergency stop
   - **Local LLM verdict**: Essential! Local models need MORE guardrails, not fewer.

**Performance**: 172,000+ ops/sec, 60% memory compression

**Applicable for local**: Safety/rollback framework. Skip the self-learning parts.

### Agentic-Flow (github.com/ruvnet/agentic-flow)

Production orchestration with 66 self-learning agents and 213 MCP tools.

**Key Features:**

1. **Intelligent Model Routing (LLM Router)** 🔴
   - 60% cost savings via dynamic model selection
   - Routes to Haiku for simple tasks, Sonnet/Opus for complex
   - Evaluates quality requirements vs budget
   - Quality scores 0.8-0.95 maintained
   - **Local LLM verdict**: NOT APPLICABLE. Can't hot-swap models on single GPU.

2. **Cost Metrics** 🔴
   - 32.3% token reduction with smart coordination
   - Monthly costs: $720 → $288 with routing
   - **Local LLM verdict**: No per-token cost. GPU time is the constraint, not API fees.

3. **Claude Code Integration** 🟡
   ```bash
   npx agentic-flow init              # Initialize project
   npx agentic-flow hooks pretrain    # Bootstrap from codebase
   npx agentic-flow mcp start         # Start MCP server
   ```
   - **Local LLM verdict**: MCP integration useful, but pretraining assumes cloud API.

4. **Token Reduction via Coordination** 🟢
   - Smart summarization between agents
   - Avoid redundant context passing
   - **Local LLM verdict**: YES! Context window conservation is critical for local.

**Applicable for local**: Context/token reduction patterns. Skip model routing and cost optimization.

### Claw Code (github.com/ultraworkers/claw-code)

A Rust implementation of a Claude-compatible CLI agent harness.

**Key Features:**

1. **Session Management** 🟢
   - Persistent sessions across restarts
   - Context preservation
   - **Local LLM verdict**: Useful for long-running local tasks.

2. **Container-first Workflow** 🟢
   - Designed for containerized deployment
   - **Local LLM verdict**: Matches our architecture exactly.

3. **Subagent Support** 🟢
   - Via `copilot_swe_agent_use_subagents` flag
   - **Local LLM verdict**: Good reference for subagent implementation.

4. **Mock Parity Harness** 🟢
   - Deterministic testing without API calls
   - **Local LLM verdict**: Excellent for testing agent logic offline.

**Applicable for local**: Most features relevant. Good reference implementation.

⚠️ **CRITICAL FINDING**: Hooks are **config-only, not executed** in current Claw Code.
See [CLAW_CODE_EVALUATION.md](./CLAW_CODE_EVALUATION.md) for full analysis.

From [PARITY.md](https://github.com/ultraworkers/claw-code/blob/main/PARITY.md):
> "Hook config is parsed... However, there is no actual hook execution pipeline...
> Status: config-only; runtime behavior missing."

**This means**: Our Stop hook supervisor pattern would NOT work with Claw Code today.

---

## Summary: Patterns for Local LLM Deployment

### Recommended Patterns (Local LLM Compatible)

| Pattern | Source | Local LLM Fit | Implementation |
|---------|--------|---------------|----------------|
| Hierarchical coordinator | Claude-Flow | 🟢 Excellent | Already have (supervisor) |
| Anti-drift checkpoints | Claude-Flow | 🟢 Critical | Supervisor validates goals |
| Sequential subagents | General | 🟢 Required | One agent at a time |
| File-based context passing | General | 🟢 Simple | Write summaries to files |
| Safety/rollback framework | SAFLA | 🟢 Essential | Add more guardrails |
| Session persistence | Claw Code | 🟢 Useful | For long tasks |
| Container-first workflow | Claw Code | 🟢 Perfect | Already have |
| Explicit delegation rules | General | 🟢 Required | Hard rules in CLAUDE.md |

### Patterns to AVOID (Not Suitable for Local)

| Pattern | Source | Why Not |
|---------|--------|---------|
| 100+ agent swarms | Claude-Flow | GPU bottleneck, too slow |
| Dynamic model routing | Agentic-Flow | Can't hot-swap models |
| Meta-cognitive learning | SAFLA | Local models unreliable |
| Parallel subagents | General | Single GPU = sequential anyway |
| Complex vector memory | SAFLA | Overkill, files work fine |
| Self-learning loops | Agentic-Flow | May amplify errors |

### Local LLM Specific Recommendations

1. **Limit concurrent agents to 2-3 max** (really 1 at a time)
2. **Use EXPLICIT delegation rules** (local models don't infer well)
3. **Aggressive context conservation** (smaller windows)
4. **Stronger supervisor validation** (more errors to catch)
5. **Simple file-based memory** (skip vector DBs)
6. **Sequential workflows** (don't pretend parallelism exists)

---

## Sources

- [Claude Code Subagents Documentation](https://code.claude.com/docs/en/sub-agents)
- [Claude Code Customization Guide](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/)
- [Sub-Agent Delegation Setup Gist](https://gist.github.com/tomas-rampas/a79213bb4cf59722e45eab7aa45f155c)
- [Claude Lab Agent Guide](https://claudelab.net/en/articles/claude-code/claude-code-agent-guide)
- [MorphLLM Subagents Guide](https://www.morphllm.com/claude-subagents)
- [Claude-Flow / Ruflo](https://github.com/ruvnet/claude-flow) - Multi-agent swarm orchestration
- [SAFLA](https://github.com/ruvnet/SAFLA) - Self-aware feedback loop with hybrid memory
- [Claw Code](https://github.com/ultraworkers/claw-code) - Rust Claude agent harness
- [Claw Code Evaluation](./CLAW_CODE_EVALUATION.md) - Our detailed analysis (hooks not functional)
