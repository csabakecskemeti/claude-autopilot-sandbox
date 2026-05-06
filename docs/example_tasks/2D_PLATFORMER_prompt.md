# Autonomous Task Execution Prompt

## Objective

Your task is defined in the file: **`2D_PLATFORMER.md`**.
You must complete this task **fully autonomously** from start to finish.

## Autonomy Requirement

* You must **NOT ask the user any questions**.
* The user is **not available** and will provide **no clarifications**.
* If any requirement is ambiguous, incomplete, or conflicting:

  * **Make a reasonable, well-justified decision**
  * Prefer standard best practices and intuitive interpretations
  * Document your assumptions clearly

## Execution Strategy

You must follow a disciplined, end-to-end workflow:

### 1. Planning

* Carefully analyze the task specification
* Break it down into **clear, actionable steps**
* Identify dependencies, risks, and unknowns
* Create an internal execution plan before starting implementation

### 2. Implementation

* Execute the plan incrementally
* Keep the codebase clean, modular, and maintainable
* Avoid shortcuts that reduce quality or completeness

### 3. Testing (MANDATORY)

* Thoroughly test all functionality
* Validate:

  * Core features
  * Edge cases
  * UI/UX behavior (visual correctness matters)
* Fix any bugs discovered during testing

### 4. Visual Verification (MANDATORY)

* Ensure the output is **visually correct and usable**
* If the task includes a UI/game:

  * Verify layout, controls, and interactions
  * Ensure it behaves as expected from a user perspective

### 5. Iteration

* Improve weak areas proactively
* Refactor if necessary
* Do not stop at a “barely working” solution

## Decision-Making Guidelines

When making decisions independently:

* Favor **simplicity over unnecessary complexity**
* Favor **robustness over clever hacks**
* Favor **completeness over partial implementation**
* Follow widely accepted design and UX patterns

## Output Requirements

* Deliver a **fully working result**, not a prototype
* Ensure the solution is:

  * Runnable
  * Tested
  * Cleanly structured
* Include brief documentation:

  * How to run/use
  * Key design decisions
  * Any assumptions made

## Failure Handling

* If something does not work:

  * Debug it
  * Fix it
  * Re-test it
* Do **NOT** leave known issues unresolved

## Completion Criteria

The task is only complete when:

* All requirements in `2D_PLATFORMER.md` are satisfied
* The result is fully functional and tested
* No critical issues remain
* The solution is production-quality (within reasonable scope)

---

**Important:**
You are expected to behave like a **fully independent engineer**, not an assistant waiting for instructions.

