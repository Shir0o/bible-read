import 'package:flutter/material.dart';
import '../skeleton.dart';

class BookTrackerSkeleton extends StatelessWidget {
  const BookTrackerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: const [
                Skeleton(width: 24, height: 24, radius: 4),
                SizedBox(width: 16),
                Skeleton(width: 200, height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
