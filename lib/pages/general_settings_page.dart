import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_preferences.dart';
import '../services/user_preferences_service.dart';
import '../widgets/common_styles.dart';

class GeneralSettingsPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final UserPreferencesService? userPreferencesService;

  GeneralSettingsPage({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.userPreferencesService,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  late final UserPreferencesService _prefsService;
  UserPreferences _prefs = const UserPreferences();
  bool _loading = true;
  StreamSubscription<UserPreferences>? _prefSub;

  @override
  void initState() {
    super.initState();
    _prefsService = widget.userPreferencesService ??
        UserPreferencesService(firestore: widget.firestore);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    _prefSub?.cancel();
    _prefSub = _prefsService.streamPreferences(uid).listen((prefs) {
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _prefSub?.cancel();
    super.dispose();
  }

  Future<void> _updatePreference(bool value) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final newPrefs = _prefs.copyWith(autoMarkPlanRead: value);
    setState(() {
      _prefs = newPrefs;
    });

    await _prefsService.updatePreferences(uid, newPrefs);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'General Settings'),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSectionHeader('Reading Plans'),
                  CommonStyles.buildTappableCard(
                    context: context,
                    onTap: () => _updatePreference(!_prefs.autoMarkPlanRead),
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-mark Plan Reading'),
                      subtitle: const Text(
                        'Automatically mark today\'s reading in your personal plan when you mark your daily reading as complete.',
                      ),
                      value: _prefs.autoMarkPlanRead,
                      onChanged: _updatePreference,
                      activeThumbColor: colorScheme.primary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Note: If this is off, you will need to manually mark your plan progress in the plan details page.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
