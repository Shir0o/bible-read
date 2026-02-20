import sys

with open('lib/pages/group_detail_page.dart', 'r') as f:
    content = f.read()

search_text = """  Widget _buildGroupProgress(
      BuildContext context, List<GroupSchedule> schedule) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate progress
    int totalChapters = 0;
    int completedChapters = 0;
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);

    String? currentBook;

    for (var s in schedule) {
      totalChapters += s.chapters.length;
      if (s.date.isBefore(today) || s.date.isAtSameMomentAs(today)) {
        completedChapters += s.chapters.length;
      }
      if (s.date.isAtSameMomentAs(today) && s.chapters.isNotEmpty) {
        // Simple parsing: assuming format "Book Chapter"
        final firstChapter = s.chapters.first;
        final parts = firstChapter.split(' ');
        if (parts.length > 1) {
          // Handle "1 John" cases
          if (int.tryParse(parts[0]) != null && parts.length > 2) {
            currentBook = '${parts[0]} ${parts[1]}';
          } else {
            currentBook = parts[0];
          }
        } else {
          currentBook = parts[0];
        }
      }
    }

    final percent = totalChapters > 0 ? completedChapters / totalChapters : 0.0;
    final percentDisplay = (percent * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GROUP PROGRESS',
                    style: GoogleFonts.plusJakartaSans(
                      textStyle: theme.textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$percentDisplay%',
                    style: GoogleFonts.plusJakartaSans(
                      textStyle: theme.textTheme.displaySmall,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'On Track',
                  style: GoogleFonts.plusJakartaSans(
                    textStyle: theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 16,
              backgroundColor:
                  colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            currentBook != null
                ? 'The group is $percentDisplay% through the Book of $currentBook.'
                : 'The group is $percentDisplay% through the reading plan.',
            style: GoogleFonts.plusJakartaSans(
              textStyle: theme.textTheme.bodyMedium,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }"""

replace_text = """  Widget _buildGroupProgress(
      BuildContext context, List<GroupSchedule> schedule) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate time-based expected progress
    int totalChapters = 0;
    int expectedCompletedChapters = 0;
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);

    String? currentBook;

    for (var s in schedule) {
      totalChapters += s.chapters.length;
      if (s.date.isBefore(today) || s.date.isAtSameMomentAs(today)) {
        expectedCompletedChapters += s.chapters.length;
      }
      if (s.date.isAtSameMomentAs(today) && s.chapters.isNotEmpty) {
        // Simple parsing: assuming format "Book Chapter"
        final firstChapter = s.chapters.first;
        final parts = firstChapter.split(' ');
        if (parts.length > 1) {
          // Handle "1 John" cases
          if (int.tryParse(parts[0]) != null && parts.length > 2) {
            currentBook = '${parts[0]} ${parts[1]}';
          } else {
            currentBook = parts[0];
          }
        } else {
          currentBook = parts[0];
        }
      }
    }

    final timePercent =
        totalChapters > 0 ? expectedCompletedChapters / totalChapters : 0.0;

    return StreamBuilder<List<GroupMemberProgressData>>(
        stream: widget.groupService.memberOverallCompletion(widget.group.id),
        builder: (context, snapshot) {
          final members = snapshot.data ?? [];
          final double actualPercent = members.isEmpty
              ? 0.0
              : members.map((m) => m.completion).reduce((a, b) => a + b) /
                  members.length;

          final percentDisplay = (actualPercent * 100).round();
          final bool isOnTrack = actualPercent >= timePercent;

          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GROUP PROGRESS',
                          style: GoogleFonts.plusJakartaSans(
                            textStyle: theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$percentDisplay%',
                          style: GoogleFonts.plusJakartaSans(
                            textStyle: theme.textTheme.displaySmall,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOnTrack
                            ? colorScheme.primaryContainer
                            : colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isOnTrack ? 'On Track' : 'Behind',
                        style: GoogleFonts.plusJakartaSans(
                          textStyle: theme.textTheme.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: isOnTrack
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: actualPercent,
                    minHeight: 16,
                    backgroundColor:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  currentBook != null
                      ? 'The group is $percentDisplay% through the Book of $currentBook.'
                      : 'The group is $percentDisplay% through the reading plan.',
                  style: GoogleFonts.plusJakartaSans(
                    textStyle: theme.textTheme.bodyMedium,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        });
  }"""

if search_text not in content:
    print("Error: Search text not found!")
    sys.exit(1)

new_content = content.replace(search_text, replace_text)

with open('lib/pages/group_detail_page.dart', 'w') as f:
    f.write(new_content)
