# /decision <topic>

Log a project decision:

1. Research the topic (optionally delegate to @researcher).
2. Create a decision record in `data/decisions/<date>-<topic>.md` using the ADR (Architecture Decision Record) format:
    - Context: Why is this decision needed?
    - Options: What were the alternatives?
    - Decision: What was chosen and why?
    - Consequences: What are the trade-offs?
3. Update `data/projects/mela.md` if the decision changes project status or goals.
4. Notify the user of the recorded decision.
