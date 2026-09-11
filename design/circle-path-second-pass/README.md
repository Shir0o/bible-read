# Circle / Path — second pass mockups

Seven phone artboards for the decisions in the "Second pass" section of
[`docs/community_journey_ia.md`](../../docs/community_journey_ia.md).

Every value is lifted from `lib/theme/app_theme.dart` — warm-paper `#F4F0E8`,
cards `#FFFDFA` at `rCard` 22, lavender `#6A53AD`, warm gold `#A0702F`, Spectral
for titles and Hanken Grotesk for UI, `buttonHeight` 52. The bottom-bar icons are
`lib/widgets/nav_glyphs.dart` redrawn as SVG on the same 24 grid at 1.8 stroke.

| Artboard | Screen | Issue |
|---|---|---|
| `Main.dc.html` | Circle, empty — the screen the observed user failed on | #855 |
| `CircleFull.dc.html` | Circle, people only (no "Your groups" section) | #855 |
| `Path.dc.html` | One card shape for solo and shared plans | #854, #857 |
| `Schedule.dc.html` | The merged schedule page | #856 |
| `GroupPage.dc.html` | `GroupMembersPage` as the group page | #857 |
| `GroupPreview.dc.html` | Public-group preview, member count only | #858 |
| `Reschedule.dc.html` | Owner-only Reschedule vs. Adjust pace | #859 |

`canvas.json` lays them out. The names, references and reflections are invented
sample content.

The published canvas is regenerated from these sources; the seeded output is
gitignored.
