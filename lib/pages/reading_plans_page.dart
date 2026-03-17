import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'create_plan_page.dart';
import '../widgets/views/reading_plans_view.dart';

class ReadingPlansPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const ReadingPlansPage({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<ReadingPlansPage> createState() => _ReadingPlansPageState();
}

class _ReadingPlansPageState extends State<ReadingPlansPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reading Plans',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      backgroundColor: colorScheme.surface,
      body: ReadingPlansView(
        firestore: widget.firestore,
        auth: widget.auth,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreatePlanPage(
                firestore: widget.firestore,
                auth: widget.auth,
              ),
            ),
          );
          if (mounted) {
            setState(() {});
          }
        },
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        tooltip: 'Create New Plan',
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}
