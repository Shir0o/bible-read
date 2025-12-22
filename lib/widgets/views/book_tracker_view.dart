import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/achievement.dart';
import '../../models/achievement_definition.dart';
import '../../services/achievement_service.dart';
import '../../services/reference_parser.dart';
import '../common_styles.dart';

class BookTrackerView extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const BookTrackerView({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to track books.')),
      );
    }

    final achievementService = AchievementService(firestore: firestore);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: StreamBuilder<Set<String>>(
          stream: achievementService.unlockedAchievementIds(user.uid),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Error loading progress'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final unlockedIds = snapshot.data!;
            final books = ReferenceParser.allBooks;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                final achievementId =
                    AchievementDefinition.bookAchievementId(book);
                final isUnlocked = unlockedIds.contains(achievementId);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colorScheme.surfaceContainerHigh,
                  child: CheckboxListTile(
                    title: Text(
                      book,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    value: isUnlocked,
                    activeColor: Theme.of(context).colorScheme.primary,
                    checkColor: colorScheme.onPrimary,
                    onChanged: isUnlocked
                        ? null // Disable unchecking
                        : (bool? value) async {
                            if (value == true) {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Complete $book?'),
                                  content: Text(
                                      'Are you sure you want to mark $book as completed? This cannot be undone.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Confirm'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                await achievementService.unlockAchievement(
                                  user.uid,
                                  Achievement(
                                    id: achievementId,
                                    title: 'Complete $book',
                                    type: 'book',
                                    dateUnlocked: DateTime.now(),
                                  ),
                                );
                              }
                            }
                          },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
