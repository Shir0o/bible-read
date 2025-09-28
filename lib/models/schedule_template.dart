import 'package:cloud_firestore/cloud_firestore.dart';

/// Auto-schedule template configuration for a group.
class ScheduleTemplate {
  /// Optional display name for the template (e.g., "Morning OT").
  final String? name;
  /// Whether automatic schedule creation is enabled.
  final bool active;

  /// IANA timezone identifier, e.g. "UTC" or "America/Los_Angeles".
  final String timezone;

  /// Local start time in 24h format HH:mm (optional, currently informational).
  final String startTimeLocal;

  /// Optional duration in minutes.
  final int? durationMinutes;

  /// Optional recurrence rule (RFC 5545). Defaults to daily.
  final String rrule;

  /// Optional content plan identifier (e.g., 'sequential_ot').
  final String? plan;

  /// Chapters to assign per scheduled day (if [plan] is set).
  final int? chaptersPerDay;

  /// Weekday codes to schedule on (RFC-style two-letter codes, e.g., 'MO').
  final List<String>? weekdays;

  /// Starting reference for content plans, e.g., 'Gen 1'.
  final String? startRef;

  /// Creates a [ScheduleTemplate].
  const ScheduleTemplate({
    required this.active,
    required this.timezone,
    required this.startTimeLocal,
    this.durationMinutes,
    this.rrule = 'FREQ=DAILY;INTERVAL=1',
    this.plan,
    this.chaptersPerDay,
    this.weekdays,
    this.startRef,
    this.name,
  });

  /// Default template with daily recurrence at midnight UTC.
  factory ScheduleTemplate.defaultUtc() => const ScheduleTemplate(
        active: false,
        timezone: 'UTC',
        startTimeLocal: '00:00',
      );

  /// Reads a [ScheduleTemplate] from a Firestore document.
  factory ScheduleTemplate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ScheduleTemplate(
      active: (data['active'] as bool?) ?? false,
      timezone: (data['timezone'] as String?)?.trim().isNotEmpty == true
          ? (data['timezone'] as String)
          : 'UTC',
      startTimeLocal: (data['startTimeLocal'] as String?)?.trim().isNotEmpty == true
          ? (data['startTimeLocal'] as String)
          : '00:00',
      durationMinutes: (data['durationMinutes'] as num?)?.toInt(),
      rrule: (data['rrule'] as String?)?.trim().isNotEmpty == true
          ? (data['rrule'] as String)
          : 'FREQ=DAILY;INTERVAL=1',
      plan: (data['plan'] as String?)?.trim().isNotEmpty == true
          ? (data['plan'] as String)
          : null,
      chaptersPerDay: (data['chaptersPerDay'] as num?)?.toInt(),
      weekdays: (data['weekdays'] as List?)
          ?.whereType<String>()
          .map((s) => s.trim().toUpperCase())
          .toList(),
      startRef: (data['startRef'] as String?)?.trim().isNotEmpty == true
          ? (data['startRef'] as String)
          : null,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String)
          : null,
    );
  }

  /// Serializes this template for Firestore.
  Map<String, dynamic> toFirestore() => {
        'active': active,
        'timezone': timezone,
        'startTimeLocal': startTimeLocal,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'rrule': rrule,
        if (plan != null) 'plan': plan,
        if (chaptersPerDay != null) 'chaptersPerDay': chaptersPerDay,
        if (weekdays != null) 'weekdays': weekdays,
        if (startRef != null) 'startRef': startRef,
        if (name != null) 'name': name,
      };

  ScheduleTemplate copyWith({
    bool? active,
    String? timezone,
    String? startTimeLocal,
    int? durationMinutes,
    String? rrule,
    String? plan,
    int? chaptersPerDay,
    List<String>? weekdays,
    String? startRef,
    String? name,
  }) =>
      ScheduleTemplate(
        active: active ?? this.active,
        timezone: timezone ?? this.timezone,
        startTimeLocal: startTimeLocal ?? this.startTimeLocal,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        rrule: rrule ?? this.rrule,
        plan: plan ?? this.plan,
        chaptersPerDay: chaptersPerDay ?? this.chaptersPerDay,
        weekdays: weekdays ?? this.weekdays,
        startRef: startRef ?? this.startRef,
        name: name ?? this.name,
      );
}
