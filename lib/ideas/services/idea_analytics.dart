library;

import 'package:flutterclaw/services/analytics_service.dart';

/// PRD 13.1 events for Ideas domain.
class IdeaAnalytics {
  IdeaAnalytics(this._analyticsService);

  final AnalyticsService _analyticsService;

  Future<void> logIdeaCreated({
    required String ideaId,
    required String sourceType,
    required String status,
  }) {
    return _log(
      eventName: 'idea_created',
      ideaId: ideaId,
      sourceType: sourceType,
      status: status,
    );
  }

  Future<void> logIdeaUpdated({
    required String ideaId,
    required String sourceType,
    required String status,
  }) {
    return _log(
      eventName: 'idea_updated',
      ideaId: ideaId,
      sourceType: sourceType,
      status: status,
    );
  }

  Future<void> logIdeaArchived({
    required String ideaId,
    required String sourceType,
    required String status,
  }) {
    return _log(
      eventName: 'idea_archived',
      ideaId: ideaId,
      sourceType: sourceType,
      status: status,
    );
  }

  Future<void> logIdeaFiltered({
    required String ideaId,
    required String sourceType,
    required String status,
  }) {
    return _log(
      eventName: 'idea_filter_applied',
      ideaId: ideaId,
      sourceType: sourceType,
      status: status,
    );
  }

  Future<void> _log({
    required String eventName,
    required String ideaId,
    required String sourceType,
    required String status,
  }) {
    return _analyticsService.logAction(
      name: eventName,
      parameters: {
        'ideaId': ideaId,
        'sourceType': sourceType,
        'status': status,
      },
    );
  }
}
