import 'package:flutter/material.dart';

import 'edit_idea_screen.dart';

enum IdeaStatus {
  draft('草稿'),
  organized('已整理'),
  diverged('已发散'),
  inProgress('推进中'),
  archived('已归档');

  const IdeaStatus(this.label);
  final String label;
}

class IdeaActionItem {
  const IdeaActionItem({required this.title, this.done = false});

  final String title;
  final bool done;

  IdeaActionItem copyWith({String? title, bool? done}) {
    return IdeaActionItem(
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }
}

class IdeaChatRef {
  const IdeaChatRef({
    required this.title,
    required this.preview,
    required this.updatedAt,
  });

  final String title;
  final String preview;
  final DateTime updatedAt;
}

class IdeaRecord {
  const IdeaRecord({
    required this.title,
    required this.rawInspiration,
    this.summary,
    this.aiInsights = const [],
    this.directions = const [],
    this.risks = const [],
    this.assumptions = const [],
    this.actionItems = const [],
    this.recentChats = const [],
    this.historyChats = const [],
    this.tags = const [],
    this.status = IdeaStatus.draft,
    this.updatedAt,
    this.archived = false,
  });

  final String title;
  final String rawInspiration;
  final String? summary;
  final List<String> aiInsights;
  final List<String> directions;
  final List<String> risks;
  final List<String> assumptions;
  final List<IdeaActionItem> actionItems;
  final List<IdeaChatRef> recentChats;
  final List<IdeaChatRef> historyChats;
  final List<String> tags;
  final IdeaStatus status;
  final DateTime? updatedAt;
  final bool archived;

  bool get isOrganized =>
      (summary?.trim().isNotEmpty ?? false) || aiInsights.isNotEmpty;

  bool get isDiverged =>
      directions.isNotEmpty || risks.isNotEmpty || assumptions.isNotEmpty;

  IdeaRecord copyWith({
    String? title,
    String? rawInspiration,
    String? summary,
    List<String>? aiInsights,
    List<String>? directions,
    List<String>? risks,
    List<String>? assumptions,
    List<IdeaActionItem>? actionItems,
    List<IdeaChatRef>? recentChats,
    List<IdeaChatRef>? historyChats,
    List<String>? tags,
    IdeaStatus? status,
    DateTime? updatedAt,
    bool? archived,
  }) {
    return IdeaRecord(
      title: title ?? this.title,
      rawInspiration: rawInspiration ?? this.rawInspiration,
      summary: summary ?? this.summary,
      aiInsights: aiInsights ?? this.aiInsights,
      directions: directions ?? this.directions,
      risks: risks ?? this.risks,
      assumptions: assumptions ?? this.assumptions,
      actionItems: actionItems ?? this.actionItems,
      recentChats: recentChats ?? this.recentChats,
      historyChats: historyChats ?? this.historyChats,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
    );
  }
}

class IdeaDetailScreen extends StatefulWidget {
  const IdeaDetailScreen({
    super.key,
    required this.idea,
    this.onChanged,
    this.onDelete,
  });

  final IdeaRecord idea;
  final ValueChanged<IdeaRecord>? onChanged;
  final ValueChanged<IdeaRecord>? onDelete;

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  late IdeaRecord _idea;

  @override
  void initState() {
    super.initState();
    _idea = widget.idea;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_idea.title),
        actions: [
          IconButton(
            onPressed: _openEditScreen,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑灵感',
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _idea.archived ? 'restore' : 'archive',
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    _idea.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  ),
                  title: Text(_idea.archived ? '恢复' : '归档'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 108),
        children: [
          _MetaSection(
            tags: _idea.tags,
            status: _idea.status,
            updatedAt: _idea.updatedAt,
            onAddTag: _addTag,
            onRemoveTag: _removeTag,
            onStatusChanged: _changeStatus,
          ),
          _SectionCard(title: '原始灵感', child: Text(_idea.rawInspiration)),
          _SectionCard(
            title: 'AI 整理结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_idea.summary?.isNotEmpty == true ? _idea.summary! : '暂无 summary'),
                const SizedBox(height: 10),
                _BulletList(items: _idea.aiInsights, emptyText: '暂无 aiInsights'),
              ],
            ),
          ),
          _SectionCard(
            title: '发散结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SubBlock(title: 'directions', items: _idea.directions),
                _SubBlock(title: 'risks', items: _idea.risks),
                _SubBlock(title: 'assumptions', items: _idea.assumptions),
              ],
            ),
          ),
          _SectionCard(
            title: '下一步行动列表',
            child: _idea.actionItems.isEmpty
                ? const Text('暂无行动项')
                : Column(
                    children: _idea.actionItems
                        .asMap()
                        .entries
                        .map(
                          (entry) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: entry.value.done,
                            title: Text(entry.value.title),
                            onChanged: (checked) => _toggleAction(entry.key, checked ?? false),
                          ),
                        )
                        .toList(),
                  ),
          ),
          _SectionCard(
            title: '关联聊天',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChatGroup(title: '最近会话', chats: _idea.recentChats),
                const SizedBox(height: 10),
                _ChatGroup(title: '历史', chats: _idea.historyChats),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () {},
          child: Text(_primaryActionLabel),
        ),
      ),
    );
  }

  String get _primaryActionLabel {
    if (!_idea.isOrganized) return '让 AI 整理';
    if (_idea.isOrganized && !_idea.isDiverged) return '与 AI 发散';
    if (_idea.actionItems.isEmpty) return '提取下一步';
    if (_idea.actionItems.any((item) => !item.done)) return '继续推进';
    return '查看成果复盘';
  }

  void _applyChange(IdeaRecord next) {
    setState(() {
      _idea = next.copyWith(updatedAt: DateTime.now());
    });
    widget.onChanged?.call(_idea);
  }

  Future<void> _openEditScreen() async {
    final updated = await Navigator.of(context).push<IdeaRecord>(
      MaterialPageRoute(builder: (_) => EditIdeaScreen(initialIdea: _idea)),
    );
    if (updated != null) {
      _applyChange(updated);
    }
  }

  void _toggleAction(int index, bool done) {
    final next = [..._idea.actionItems];
    next[index] = next[index].copyWith(done: done);
    _applyChange(_idea.copyWith(actionItems: next));
  }

  Future<void> _handleMenuAction(String action) async {
    if (action == 'archive') {
      final ok = await _confirmDialog(
        title: '确认归档',
        content: '归档后会隐藏在默认列表中，可随时恢复。',
        confirmText: '确认归档',
      );
      if (ok) {
        _applyChange(_idea.copyWith(archived: true, status: IdeaStatus.archived));
      }
      return;
    }

    if (action == 'restore') {
      final ok = await _confirmDialog(
        title: '确认恢复',
        content: '恢复后会重新出现在灵感列表。',
        confirmText: '确认恢复',
      );
      if (ok) {
        _applyChange(_idea.copyWith(archived: false, status: IdeaStatus.inProgress));
      }
      return;
    }

    if (action == 'delete') {
      final ok = await _confirmDialog(
        title: '确认删除',
        content: '删除后无法撤销，请确认是否继续。',
        confirmText: '删除',
        isDanger: true,
      );
      if (ok && mounted) {
        widget.onDelete?.call(_idea);
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String content,
    required String confirmText,
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: isDanger
                ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入标签'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('添加')),
        ],
      ),
    );
    final value = tag?.trim();
    if (value == null || value.isEmpty || _idea.tags.contains(value)) return;
    _applyChange(_idea.copyWith(tags: [..._idea.tags, value]));
  }

  void _removeTag(String tag) {
    _applyChange(_idea.copyWith(tags: _idea.tags.where((item) => item != tag).toList()));
  }

  void _changeStatus(IdeaStatus status) {
    _applyChange(_idea.copyWith(status: status, archived: status == IdeaStatus.archived));
  }
}

class _MetaSection extends StatelessWidget {
  const _MetaSection({
    required this.tags,
    required this.status,
    required this.updatedAt,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onStatusChanged,
  });

  final List<String> tags;
  final IdeaStatus status;
  final DateTime? updatedAt;
  final VoidCallback onAddTag;
  final ValueChanged<String> onRemoveTag;
  final ValueChanged<IdeaStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final updated = updatedAt == null
        ? '尚未更新'
        : '${updatedAt!.year}-${updatedAt!.month.toString().padLeft(2, '0')}-${updatedAt!.day.toString().padLeft(2, '0')} '
            '${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}';

    return _SectionCard(
      title: '标签与状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...tags.map(
                (tag) => InputChip(
                  label: Text(tag),
                  onDeleted: () => onRemoveTag(tag),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('添加标签'),
                onPressed: onAddTag,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<IdeaStatus>(
            initialValue: status,
            decoration: const InputDecoration(labelText: '状态'),
            items: IdeaStatus.values
                .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) onStatusChanged(value);
            },
          ),
          const SizedBox(height: 8),
          Text('updatedAt：$updated', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SubBlock extends StatelessWidget {
  const _SubBlock({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          _BulletList(items: items, emptyText: '暂无内容'),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, required this.emptyText});

  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(emptyText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item'),
              ))
          .toList(),
    );
  }
}

class _ChatGroup extends StatelessWidget {
  const _ChatGroup({required this.title, required this.chats});

  final String title;
  final List<IdeaChatRef> chats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (chats.isEmpty)
          const Text('暂无会话')
        else
          ...chats.map(
            (chat) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_bubble_outline, size: 18),
              title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(chat.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(
                '${chat.updatedAt.month}/${chat.updatedAt.day}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}
