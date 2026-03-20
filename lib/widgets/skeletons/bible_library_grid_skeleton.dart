import 'package:flutter/material.dart';
import '../skeleton.dart';

class BibleLibraryGridSkeleton extends StatelessWidget {
  const BibleLibraryGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Skeleton(width: double.infinity, height: 200, radius: 24);
  }
}
