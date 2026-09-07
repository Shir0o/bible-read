# Circle is derived from Group membership; there is no friend graph

The app had two parallel social graphs: a mutual request/accept friend graph
(`users/{uid}/friends`, `friendRequestsSent`, `friendRequestsReceived`) and
Group membership (`groups/{id}/members`). They were already crossing in code —
`GroupMembersPage` nudged group members through `FriendService`, and
`InviteMemberPage` searched your *friends* to fill a *group* — and new users
could not tell which one they were supposed to use to reach the people they
read with.

We deleted the friend graph. A person's **Circle** is now derived: everyone
they share at least one Group with. Group is the only relationship primitive.

## Considered options

- **Presentation-only merge** — keep both collections, render one list. Rejected:
  keeps the entire friend read-path alive forever, so none of the complexity is
  actually removed.
- **Group membership implies friendship** — auto-link co-members while keeping
  friend requests for one-to-one adds. Rejected: still two graphs, and it makes
  the consent question harder rather than answering it.
- **Delete the friend graph** (chosen) — friendships that are not backed by a
  shared Group cease to exist.

## Consequences

- Two people cannot be connected without forming a Group together. This is
  accepted: a Group of two is a reasonable object in this app.
- Existing friendships are dropped rather than migrated, and announced. No
  auto-creation of two-person Groups.
- Consent for progress visibility becomes **delegated**: approving a join
  request on a public Group grants the newcomer visibility of every member's
  named daily Progress, not just the approver's. The approval screen must say
  so explicitly.
- `friendStreakLinks` / `friendStreakInvites` were already dead schema (present
  in `firestore.rules`, referenced nowhere) and go with it.
- `nudgeFriend` becomes `nudgeMember`, sendable to anyone in your Circle. A
  Nudge is not tied to a Group: it means "come and read", not "you are behind on
  our schedule". This is what the existing code already assumes — nudges are
  stored per recipient with no group dimension.
