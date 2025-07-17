import 'package:flutter/material.dart';

/// Displays an error message when Firebase App Check fails to initialize.
class AppCheckErrorPage extends StatelessWidget {
  const AppCheckErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'App verification failed. Please reinstall or check your device.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
