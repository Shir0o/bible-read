import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/profile_summary_card.dart';
import '../widgets/views/book_tracker_view.dart';
import '../widgets/views/streak_history_view.dart';
import '../theme/app_theme.dart';
import '../widgets/views/reading_plans_view.dart';

class JourneyPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  const JourneyPage({
    super.key,
    required this.auth,
    required this.firestore,
  });

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
             SliverAppBar(
               centerTitle: true,
               backgroundColor: colorScheme.surface,
               scrolledUnderElevation: 0,
               forceMaterialTransparency: true, // Keep it transparent/clean
               // No explicitly set title, letting the card be the focus
               // but we can add an opacity-faded title if scrolled later if desired.
             ),
             SliverToBoxAdapter(
               child: ProfileSummaryCard(auth: widget.auth),
             ),
             AnimatedBuilder(
               animation: _tabController,
               builder: (context, child) {
                 return SliverPersistentHeader(
                   delegate: _SliverTabBarDelegate(
                     TabBar(
                      controller: _tabController,
                      labelColor: AppTheme.primary90,
                      unselectedLabelColor: AppTheme.neutral90,
                      indicator: const BoxDecoration(),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      tabs: [
                        _JourneyPageState._buildTab(_tabController, 0, Icons.calendar_today, 'Plans'),
                        _JourneyPageState._buildTab(_tabController, 1, Icons.check_circle_outline, 'Tracker'),
                        _JourneyPageState._buildTab(_tabController, 2, Icons.history, 'History'),
                      ],
                    ),
                    colorScheme: colorScheme,
                   ),
                   pinned: true,
                 );
               },
             ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            ReadingPlansView(
              firestore: widget.firestore,
              auth: widget.auth,
            ),
            BookTrackerView(
              firestore: widget.firestore,
              auth: widget.auth,
            ),
            StreakHistoryView(
              firestore: widget.firestore,
              auth: widget.auth,
            ),
          ],
        ),
      ),
    );
  }


  static Widget _buildTab(TabController controller, int index, IconData icon, String label) {
    if (!controller.indexIsChanging) {
       // Accessing index is safe
    }
    // We listen to animation in parent, so rebuild happens.
    // controller.index gives the current index.
    final isSelected = controller.index == index;
    return Tab(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary30 : AppTheme.neutral22,
          borderRadius: BorderRadius.circular(isSelected ? 99 : 16),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.body.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 14,
            )),
          ],
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final ColorScheme colorScheme;

  _SliverTabBarDelegate(this._tabBar, {required this.colorScheme});

  @override
  double get minExtent => _tabBar.preferredSize.height + 16;
  @override
  double get maxExtent => _tabBar.preferredSize.height + 16;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: colorScheme.surface, // Opaque background when pinned
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.center,
      child: Container(
         // No decoration needed
         child: _tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true; // Force rebuild to update tab styles
  }
}
