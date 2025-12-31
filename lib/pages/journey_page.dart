import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/profile_summary_card.dart';
import '../widgets/views/book_tracker_view.dart';
import '../widgets/views/streak_history_view.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
             SliverPersistentHeader(
               delegate: _SliverTabBarDelegate(
                 TabBar(
                  controller: _tabController,
                  labelColor: colorScheme.onSecondaryContainer,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  dividerColor: Colors.transparent,
                  overlayColor: MaterialStateProperty.all(Colors.transparent),
                  splashBorderRadius: BorderRadius.circular(28),
                  labelStyle: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 18),
                          SizedBox(width: 4),
                          Text('Tracker'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 18),
                          SizedBox(width: 4),
                          Text('History'),
                        ],
                      ),
                    ),
                  ],
                ),
                colorScheme: colorScheme,
               ),
               pinned: true,
             ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
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
         decoration: BoxDecoration(
           color: colorScheme.surfaceContainer,
           borderRadius: BorderRadius.circular(28),
         ),
         child: _tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
