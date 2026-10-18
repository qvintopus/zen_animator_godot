# docs

Project documentation that travels with the repo.

| Path | Contents |
|---|---|
| `plans/` | Implementation plans: the reasoning behind a change, what was measured, and the order to execute in. |

Plans are written before the work and kept after it, so a later reader can see *why* a
change was made and which engine behaviours were actually verified rather than assumed.
A plan is not updated to match what shipped — if the design changes, that is a new plan.

Durable design notes about how the runtime works live in the file headers and in the
top-level `README.md`, not here.
