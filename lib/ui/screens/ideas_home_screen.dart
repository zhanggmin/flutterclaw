import 'package:flutter/material.dart';
import 'package:flutterclaw/ui/widgets/ideas/idea_card.dart';
import 'package:flutterclaw/ui/widgets/ideas/idea_empty_state.dart';
import 'package:flutterclaw/ui/widgets/ideas/idea_status_chip.dart';
import 'package:flutterclaw/ui/widgets/ideas/quick_capture_card.dart';

enum IdeaStatus { inbox, incubating, developing, archived }

class IdeaItem {
  IdeaItem({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String body;
  final IdeaStatus status;
  final List<String> tags;
}

class IdeasHomeScreen extends StatefulWidget {
  const IdeasHomeScreen({super.key, this.onEnterSession});

  final VoidCallback? onEnterSession;

  @override
  State<IdeasHomeScreen> createState() => _IdeasHomeScreenState();
}

class _IdeasHomeScreenState extends State<IdeasHomeScreen> {
  final _searchController = TextEditingController();
  IdeaStatus? _statusFilter;
  int _nextId = 3;

  final List<IdeaItem> _ideas = [
    IdeaItem(
      id: 'idea-1',
      title: '',
      body: '做一个可视化面板，展示最近 7 天最常触发的自动化动作与失败原因。',
      status: IdeaStatus.inbox,
      tags: ['数据看板', '自动化'],
    ),
    IdeaItem(
      id: 'idea-2',
      title: '把截图流程变成一键 Prompt',
      body: '目标是让运营在聊天里输入自然语言，就能完成截图、标注和归档。',
      status: IdeaStatus.incubating,
      tags: ['运营', 'AI'],
    ),
    IdeaItem(
      id: 'idea-3',
      title: '多端同步提醒规则',
      body: '在 iOS 与 Android 保持一致的提醒节奏，减少重复通知。',
      status: IdeaStatus.developing,
      tags: ['移动端'],
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addIdea(String title, String body, {required bool andExpand}) {
    setState(() {
      _nextId += 1;
      _ideas.insert(
        0,
        IdeaItem(
          id: 'idea-$_nextId',
          title: title,
          body: body,
          status: IdeaStatus.inbox,
        ),
      );
    });

    if (andExpand) {
      widget.onEnterSession?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存并进入会话，你可以继续与 AI 发散。')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('想法已保存。')),
      );
    }
  }

  List<IdeaItem> get _filteredIdeas {
    final query = _searchController.text.trim().toLowerCase();
    return _ideas.where((idea) {
      final archivedFilteredOut =
          _statusFilter == null && idea.status == IdeaStatus.archived;
      if (archivedFilteredOut) return false;

      if (_statusFilter != null && idea.status != _statusFilter) {
        return false;
      }

      if (query.isEmpty) return true;

      final joinedTags = idea.tags.join(' ').toLowerCase();
      return idea.title.toLowerCase().contains(query) ||
          idea.body.toLowerCase().contains(query) ||
          joinedTags.contains(query);
    }).toList();
  }

  String _statusLabel(IdeaStatus status) {
    return switch (status) {
      IdeaStatus.inbox => 'Inbox',
      IdeaStatus.incubating => 'Incubating',
      IdeaStatus.developing => 'Developing',
      IdeaStatus.archived => 'Archived',
    };
  }

  String _primaryLabel(IdeaStatus status) {
    return switch (status) {
      IdeaStatus.inbox => '开始整理',
      IdeaStatus.incubating => '与 AI 发散',
      IdeaStatus.developing => '继续推进',
      IdeaStatus.archived => '查看归档',
    };
  }

  Color _statusColor(IdeaStatus status) {
    return switch (status) {
      IdeaStatus.inbox => Colors.blue,
      IdeaStatus.incubating => Colors.deepPurple,
      IdeaStatus.developing => Colors.teal,
      IdeaStatus.archived => Colors.grey,
    };
  }

  String _fallbackTitle(IdeaItem idea) {
    if (idea.title.trim().isNotEmpty) return idea.title.trim();
    final lines = idea.body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(2)
        .toList();
    return lines.isNotEmpty ? lines.join(' ') : '未命名想法';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredIdeas;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('想法首页')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索标题、正文、标签',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          QuickCaptureCard(
            onSave: (title, body) => _addIdea(title, body, andExpand: false),
            onSaveAndExpand: (title, body) =>
                _addIdea(title, body, andExpand: true),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IdeaStatusChip(
                  label: '全部（默认隐藏 Archived）',
                  selected: _statusFilter == null,
                  onSelected: (_) => setState(() => _statusFilter = null),
                ),
                const SizedBox(width: 8),
                ...IdeaStatus.values.map(
                  (status) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IdeaStatusChip(
                      label: _statusLabel(status),
                      selected: _statusFilter == status,
                      onSelected: (_) => setState(() => _statusFilter = status),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_ideas.isEmpty && !hasQuery)
            const IdeaEmptyState(
              title: '还没有任何想法',
              description: '先在上方「快速记录」里写下你的第一个灵感。',
              icon: Icons.lightbulb,
            )
          else if (filtered.isEmpty)
            const IdeaEmptyState(
              title: '没有找到匹配结果',
              description: '试试更换关键词，或切换状态筛选。',
              icon: Icons.search_off,
            )
          else
            ...filtered.map(
              (idea) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IdeaCard(
                  title: _fallbackTitle(idea),
                  body: idea.body,
                  statusLabel: _statusLabel(idea.status),
                  statusColor: _statusColor(idea.status),
                  tags: idea.tags,
                  primaryActionLabel: _primaryLabel(idea.status),
                  onPrimaryAction: () {
                    widget.onEnterSession?.call();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
