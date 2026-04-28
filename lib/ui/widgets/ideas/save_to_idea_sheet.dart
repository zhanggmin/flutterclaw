import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterclaw/core/app_providers.dart';
import 'package:flutterclaw/services/idea_service.dart';

class SaveToIdeaSheet extends ConsumerStatefulWidget {
  final String content;
  final IdeaSourceType sourceType;
  final String sourceRef;

  const SaveToIdeaSheet({
    super.key,
    required this.content,
    required this.sourceType,
    required this.sourceRef,
  });

  @override
  ConsumerState<SaveToIdeaSheet> createState() => _SaveToIdeaSheetState();
}

class _SaveToIdeaSheetState extends ConsumerState<SaveToIdeaSheet> {
  bool _append = false;
  bool _organize = false;
  String? _selectedIdeaId;
  bool _saving = false;
  List<IdeaItem> _ideas = const [];

  @override
  void initState() {
    super.initState();
    _loadIdeas();
  }

  Future<void> _loadIdeas() async {
    final service = ref.read(ideaServiceProvider);
    await service.load();
    if (!mounted) return;
    setState(() {
      _ideas = service.items;
      if (_ideas.isNotEmpty) _selectedIdeaId = _ideas.first.id;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final service = ref.read(ideaServiceProvider);
      await service.saveFromChat(
        content: widget.content,
        sourceType: widget.sourceType,
        sourceRef: widget.sourceRef,
        append: _append,
        existingIdeaId: _append ? _selectedIdeaId : null,
        organizeWithAi: _organize,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存为灵感')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.content.trim();
    final displayPreview = preview.length > 280 ? '${preview.substring(0, 280)}…' : preview;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('保存为灵感', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                displayPreview.isEmpty ? '(空内容)' : displayPreview,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('新建')),
                ButtonSegment(value: true, label: Text('追加')),
              ],
              selected: {_append},
              onSelectionChanged: (s) => setState(() => _append = s.first),
            ),
            if (_append) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedIdeaId,
                items: _ideas
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          e.title.isEmpty ? '(未命名)' : e.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedIdeaId = v),
                decoration: const InputDecoration(
                  labelText: '选择已有灵感',
                ),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _organize,
              title: const Text('整理后保存（AI 提取标题/摘要/标签/行动项）'),
              onChanged: (v) => setState(() => _organize = v ?? false),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving || (_append && _selectedIdeaId == null)
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lightbulb_outline),
                label: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
