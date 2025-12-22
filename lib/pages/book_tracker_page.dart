import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/views/book_tracker_view.dart';

class BookTrackerPage extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  BookTrackerPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Book Tracker',
        automaticallyImplyLeading: false,
      ),
      body: BookTrackerView(
        firestore: firestore,
        auth: auth,
      ),
    );
  }
}
