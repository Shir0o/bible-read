# Friends return — four ways to add a friend

Ten phone artboards for bringing a one-to-one friend connection back alongside
Groups, proposed in
[`docs/adr/0012-friends-alongside-circle.md`](../../docs/adr/0012-friends-alongside-circle.md).
Glossary: **Friend**, **Circle** and **Feed** in the root `CONTEXT.md`.

Settled before drawing: a Friend is made by direct invite only (no search, no
requests), one stable personal friend code with Reset, full parity with
co-members in Circle, silent unfriend, and no separate Friends screen.
The four variations differ only in how the code travels.

| Column | Artboards | What it shows |
|---|---|---|
| Shared | `Circle`, `FriendSheet` | "Add a friend" in the existing Invite sheet; a Friend in the Feed and Friends chip; Unfriend |
| V1 · Code | `V1CodeShare`, `V1CodeAdd` | 8-character code, typed into the same "Have a code?" field as a 6-character group code |
| V2 · QR | `V2QrShare`, `V2QrScan` | My code / Scan on one screen, for the same room |
| V3 · Link | `V3LinkShare`, `V3LinkOpen` | System share sheet; one confirm screen on open (needs #785 deep links) |
| V4 · All in one | `V4AllShare`, `V4AllAdd` | QR, code and link together; scanner and code field together |

Every value is lifted from `lib/theme/app_theme.dart`, matching
`../circle-path-second-pass/`. `canvas.json` lays them out. Names, codes and
reflections are invented sample content.
