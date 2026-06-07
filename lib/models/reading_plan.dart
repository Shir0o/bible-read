/// Represents a day within a reading plan.
class ReadingPlanDay {
  /// The day number (1-indexed).
  final int day;

  /// The list of chapter references for this day (e.g., "Genesis 1", "Matthew 1").
  final List<String> readings;

  const ReadingPlanDay({required this.day, required this.readings});

  factory ReadingPlanDay.fromJson(Map<String, dynamic> json) {
    return ReadingPlanDay(
      day: json['day'] as int,
      readings: List<String>.from(json['readings'] as List),
    );
  }

  Map<String, dynamic> toJson() => {'day': day, 'readings': readings};
}

/// Represents a structured reading plan.
class ReadingPlan {
  final String id;
  final String title;
  final String description;
  final int durationDays;
  final List<String> tags;
  final List<ReadingPlanDay> schedule;

  /// The original creation configuration (reading method, duration, active
  /// days, selected books, custom pace) used to generate [schedule]. Stored so
  /// the edit flow can faithfully pre-fill the form. `null` for legacy plans
  /// created before this field existed — the edit form falls back to defaults.
  final Map<String, dynamic>? config;

  const ReadingPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.durationDays,
    required this.tags,
    required this.schedule,
    this.config,
  });

  factory ReadingPlan.fromJson(Map<String, dynamic> json) {
    return ReadingPlan(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      durationDays: json['durationDays'] as int,
      tags: List<String>.from(json['tags'] as List? ?? []),
      schedule: (json['schedule'] as List)
          .map((e) => ReadingPlanDay.fromJson(e as Map<String, dynamic>))
          .toList(),
      config: (json['config'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'durationDays': durationDays,
        'tags': tags,
        'schedule': schedule.map((e) => e.toJson()).toList(),
        if (config != null) 'config': config,
      };

  /// Returns a copy with the given fields replaced.
  ReadingPlan copyWith({
    String? id,
    String? title,
    String? description,
    int? durationDays,
    List<String>? tags,
    List<ReadingPlanDay>? schedule,
    Map<String, dynamic>? config,
  }) {
    return ReadingPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      durationDays: durationDays ?? this.durationDays,
      tags: tags ?? this.tags,
      schedule: schedule ?? this.schedule,
      config: config ?? this.config,
    );
  }
}
