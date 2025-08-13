import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/menu_button.dart';

/// Displays the user's reading streak history.
class StreakHistoryPage extends StatelessWidget {
  /// Creates a [StreakHistoryPage].
  const StreakHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'History',
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: const Center(
          child: Text('Streak history coming soon'),
        ),
      ),
    );
  }
}
