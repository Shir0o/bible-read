# Friends return alongside Groups; Circle is co-members plus Friends

_Proposed 2026-10-17. Supersedes ADR-0003 once accepted._

ADR-0003 deleted the friend graph and made Group the only relationship
primitive, accepting that "two people cannot be connected without forming a
Group together". In practice a reader who wants to encourage one specific
person has to invent a Group of two for it, and that Group then shows up
everywhere a Group does — schedule, Path card, filter chips.

We bring back a mutual, one-to-one **Friend** connection that exists alongside
Group membership. A reader's **Circle** becomes everyone they share a Group
with plus their Friends, each person counted once.

## Considered options

- **Keep ADR-0003; a Friend is a hidden two-person Group** ("Pair"). Every
  existing mechanism (Feed denormalized per Group, rules scoped per Group,
  Nudge, Amen) would work unchanged. Rejected: the hidden Group leaks into
  every surface that lists Groups, and "a Group that isn't shown as a Group"
  is a second meaning of Group.
- **Restore the old friend graph wholesale** (search, requests, Friends
  screen). Rejected: search is a people directory, and the requests inbox
  and separate screen are the parallel surfaces the second pass deleted.
- **A friend graph made by direct invite only** (chosen).

## Decisions

- A Friend is made only by direct invite: one reader's personal friend code,
  typed, scanned as QR or opened as a link. Using the code is the consent;
  there is no search and no friend request.
- One stable code per reader, with Reset to retire it. Friend codes are
  eight characters so the one "Have a code?" field can tell them from
  six-character group codes.
- Friends get full parity with co-members: Feed (Reflections stay private
  per entry), Amen, Nudge.
- Either side can unfriend, silently. A shared Group keeps the person in the
  Circle regardless.
- Friendships dropped by `functions/drop-friend-graph.js` are not restored.

## Consequences

- The Feed and its rules need a second source. ADR-0004 denormalizes updates
  per Group precisely because rules cannot scope a list query to a Circle;
  Friend-visible updates need their own fan-out or rule path.
- An invite link depends on deep links, still deferred in #785; a QR code
  adds a camera permission and a scanner dependency.
- Which way of passing the code ships is open — see `design/friends-return/`.
