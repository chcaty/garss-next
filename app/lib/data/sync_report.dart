class SyncRun {
  const SyncRun({
    required this.generatedAt,
    required this.succeeded,
    required this.failed,
    required this.checked,
    required this.articleCount,
    required this.durationSeconds,
    this.workflowRunId = '',
  });
  final DateTime generatedAt;
  final int succeeded, failed, checked, articleCount, durationSeconds;
  final String workflowRunId;
  factory SyncRun.fromJson(Map<String, dynamic> json) => SyncRun(
    generatedAt: DateTime.parse(json['generated_at'] as String),
    succeeded: json['succeeded'] as int? ?? 0,
    failed: json['failed'] as int? ?? 0,
    checked: json['checked'] as int? ?? 0,
    articleCount: json['article_count'] as int? ?? 0,
    durationSeconds: json['duration_seconds'] as int? ?? 0,
    workflowRunId: json['workflow_run_id'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'succeeded': succeeded,
    'failed': failed,
    'checked': checked,
    'article_count': articleCount,
    'duration_seconds': durationSeconds,
    'workflow_run_id': workflowRunId,
  };
}

class SourceHealth {
  const SourceHealth({
    required this.status,
    this.error = '',
    this.lastCheckedAt,
    this.lastSuccessAt,
    this.failures = 0,
  });
  final String status, error;
  final DateTime? lastCheckedAt, lastSuccessAt;
  final int failures;
  factory SourceHealth.fromJson(Map<String, dynamic> json) => SourceHealth(
    status: json['status'] as String? ?? 'pending',
    error: json['last_error'] as String? ?? '',
    failures: json['failures'] as int? ?? 0,
    lastCheckedAt: DateTime.tryParse(json['last_checked_at'] as String? ?? ''),
    lastSuccessAt: DateTime.tryParse(json['last_success_at'] as String? ?? ''),
  );
  Map<String, dynamic> toJson() => {
    'status': status,
    'last_error': error,
    'failures': failures,
    'last_checked_at': lastCheckedAt?.toUtc().toIso8601String(),
    'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
  };
}

class SyncReport {
  SyncReport({
    required this.generatedAt,
    required List<SyncRun> runs,
    required Map<String, SourceHealth> sources,
  }) : runs = List.unmodifiable(runs.take(30)),
       sources = Map.unmodifiable(sources);
  final DateTime generatedAt;
  final List<SyncRun> runs;
  final Map<String, SourceHealth> sources;
  factory SyncReport.fromJson(Map<String, dynamic> json) => SyncReport(
    generatedAt: DateTime.parse(json['generated_at'] as String),
    runs: (json['runs'] as List<dynamic>? ?? [])
        .map((value) => SyncRun.fromJson(value as Map<String, dynamic>))
        .toList(),
    sources: (json['sources'] as Map<String, dynamic>? ?? {}).map(
      (id, value) =>
          MapEntry(id, SourceHealth.fromJson(value as Map<String, dynamic>)),
    ),
  );
  Map<String, dynamic> toJson() => {
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'runs': runs.map((run) => run.toJson()).toList(),
    'sources': sources.map((id, value) => MapEntry(id, value.toJson())),
  };
}
