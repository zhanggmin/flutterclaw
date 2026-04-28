library;

/// 抽象的 Idea 仓储接口（PRD 9.4）。
///
/// Idea 结构使用 `Map<String, dynamic>` 表达，约定常用字段：
/// - id: String
/// - title/content/summary: String
/// - tags: List<String>
/// - nextActions: List<Map<String, dynamic>>，每项可包含 text
/// - archived: bool
/// - sources: List<Map<String, dynamic>>
/// - createdAt/updatedAt/archivedAt: ISO-8601 String
abstract class IdeaRepository {
  Future<List<Map<String, dynamic>>> listIdeas({bool includeArchived = false});

  Future<Map<String, dynamic>?> getIdeaById(String id);

  Future<void> upsertIdea(Map<String, dynamic> idea);

  Future<void> deleteIdea(String id);

  Future<List<Map<String, dynamic>>> searchIdeas(
    String query, {
    bool includeArchived = false,
  });

  Future<String> getIdeasFilePath();

  Future<String> getAttachmentDirectoryPath(String ideaId);
}
