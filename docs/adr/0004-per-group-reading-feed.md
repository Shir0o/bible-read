# The reading feed is denormalized per Group

The encouragement feed lives at `read_logs/{date}/entries/{userId}` and is
world-readable to any signed-in user (`firestore.rules`: `// 🌐 Public reading
feed`). Scoping it to a person's Circle is not expressible as a security rule:
rules are not filters, so a list query is rejected unless every possible result
is provably readable, and constraining the query with `whereIn` on member uids
caps out around 30 people.

Each read-log entry is therefore written into **every Group the reader belongs
to**. The query becomes `groups/{id}/entries`, and the rule a one-line
membership check.

## Considered options

- **Leave it globally readable**, filter client-side. Rejected: this is the
  status quo and it is a live privacy hole — any signed-in user can read anyone's
  reading history.
- **`whereIn` on Circle uids.** Rejected: hard ~30-member ceiling.
- **A callable function** that assembles the feed. Rejected: turns a realtime
  stream into polling and loses the live updates `StreamBuilder` gets for free.
- **Denormalize per Group** (chosen).

## Consequences

- Fan-out on write: one entry per Group the reader belongs to. Small in practice.
- Existing `read_logs` data needs migrating, and the global collection retiring.
- Visibility now follows the same unit as everything else in the app — the
  Group — which is consistent with `Circle` being derived from Group membership
  ([ADR-0003](0003-circle-derived-from-groups.md)).
