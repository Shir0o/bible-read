# Skeleton ownership on the Path tab is per-section, keyed to each section's own loading signal

The Path tab (`JourneyPage`) is five independent data sections — the plan hub,
two stat tiles, the consistency calendar, the read-through card, and the badge
strip — each fed by its own Firestore stream that resolves at its own speed
(and the plan hub's is the slowest, chaining several reads). The app chose to
skeletonize each section with its own `SkeletonLoader`, keyed to *that section's*
loading signal (a local bool for imperative fetches, `connectionState == waiting`
for `StreamBuilder` sections), rather than gate the whole tab behind one page-level
loading flag.

This follows and extends the convention in `AGENTS.md`: titles and headers stay
visible, and only data-dependent components skeletonize. A fast section renders
its real content as soon as its own data lands; a slow section's skeleton never
blanks content that is already real. It is why, for example, the read-through card
skeleton keeps the "Times through" title while only the count boxes shimmer, and
why the badge strip skeletonizes only the "next up" card — the badge circles
themselves are stable layout that only changes fill color.

## Considered options

- **One page-level skeleton** (e.g. a repurposed full-page `JourneyPageSkeleton`)
  that replaces the entire tab until the slowest stream resolves. Rejected: the
  plan hub is that slowest section, so the calendar, badges, stat tiles and
  read-through card would sit blank waiting on it — a strictly worse experience
  than progressive per-section loading. It also conflicts with the documented
  "headers stay visible" convention.
- **Per-section loaders keyed to each section's own signal** (chosen). The
  consistency calendar and stat tiles are driven by `JourneyPage`'s own flags;
  the read-through card and badge strip derive their signal from their
  `StreamBuilder` connection state with no extra plumbing.

## Consequences

- Skeleton ownership lives with each section rather than behind one page-level
  gate: the plan hub, read-through card and badge strip each own their loader,
  while the stat tiles and consistency calendar are driven by `JourneyPage`'s
  own flags. A new Path section must add its own `SkeletonLoader` rather than
  inherit one.
- Each section enforces its own 1000ms `minTime` minimum, so a fast stream still
  shows its skeleton long enough to avoid a flash.
- Pull-to-refresh shows no skeletons — the `RefreshIndicator` is the feedback —
  because the section loading flags are only ever raised on first load, never
  during refresh.