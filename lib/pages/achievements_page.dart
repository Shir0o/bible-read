import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/achievement_definition.dart';
import '../services/achievement_service.dart';
import '../widgets/achievement_list_item.dart';
import '../widgets/common_styles.dart';

class AchievementsPage extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  AchievementsPage(
      {super.key, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Achievements',
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: user == null
            ? const Center(
                child: Text('Please sign in to view your achievements.'),
              )
            : StreamBuilder<Set<String>>(
                stream: AchievementService(firestore: firestore)
                    .unlockedAchievementIds(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                        child: Text('Failed to load achievements'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final unlocked = snapshot.data!;
                  final categories = AchievementCategory.values;
                  final tabLabelColor = Colors.white;
                  final unselectedTabLabelColor = Colors.white70;
                  final definitionsByCategory = {
                    for (final category in categories)
                      category: achievementsForCategory(category),
                  };

                  return DefaultTabController(
                    length: categories.length,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.transparent,
                          child: TabBar(
                            labelColor: tabLabelColor,
                            unselectedLabelColor: unselectedTabLabelColor,
                            indicatorColor: tabLabelColor,
                            tabs: [
                              for (final category in categories)
                                Tab(text: category.label),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            children: [
                              for (final category in categories)
                                _AchievementCategoryList(
                                  category: category,
                                  definitions:
                                      definitionsByCategory[category] ??
                                          const <AchievementDefinition>[],
                                  unlocked: unlocked,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _AchievementCategoryList extends StatelessWidget {
  const _AchievementCategoryList({
    required this.category,
    required this.definitions,
    required this.unlocked,
  });

  final AchievementCategory category;
  final List<AchievementDefinition> definitions;
  final Set<String> unlocked;

  @override
  Widget build(BuildContext context) {
    if (definitions.isEmpty) {
      return const Center(
        child: Text('No achievements in this category yet.'),
      );
    }

    return ListView.builder(
      key: ValueKey('achievementsList_${category.name}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: definitions.length,
      itemBuilder: (context, index) {
        final def = definitions[index];
        return AchievementListItem(
          definition: def,
          unlocked: unlocked.contains(def.id),
        );
      },
    );
  }
}
