import 'package:flutter/material.dart';

import 'idea_detail_screen.dart';

class EditIdeaScreen extends StatefulWidget {
  const EditIdeaScreen({super.key, required this.initialIdea});

  final IdeaRecord initialIdea;

  @override
  State<EditIdeaScreen> createState() => _EditIdeaScreenState();
}

class _EditIdeaScreenState extends State<EditIdeaScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _rawController;
  late final TextEditingController _summaryController;
  late final TextEditingController _insightsController;

  late IdeaStatus _status;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialIdea.title);
    _rawController = TextEditingController(text: widget.initialIdea.rawInspiration);
    _summaryController = TextEditingController(text: widget.initialIdea.summary ?? '');
    _insightsController = TextEditingController(text: widget.initialIdea.aiInsights.join('\n'));
    _status = widget.initialIdea.status;
    _tags = [...widget.initialIdea.tags];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _rawController.dispose();
    _summaryController.dispose();
    _insightsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑灵感'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rawController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: '原始灵感'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summaryController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'summary'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _insightsController,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'aiInsights（每行一条）',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<IdeaStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: '状态'),
            items: IdeaStatus.values
                .map((status) => DropdownMenuItem(value: status, child: Text(status.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _status = value);
              }
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._tags.map(
                (tag) => InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(() => _tags.remove(tag)),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('添加标签'),
                onPressed: _addTag,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入标签内容'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('添加')),
        ],
      ),
    );
    final tag = result?.trim();
    if (tag == null || tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags = [..._tags, tag]);
  }

  void _save() {
    final title = _titleController.text.trim();
    final raw = _rawController.text.trim();
    if (title.isEmpty || raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题和原始灵感不能为空')),
      );
      return;
    }

    final insights = _insightsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final updated = widget.initialIdea.copyWith(
      title: title,
      rawInspiration: raw,
      summary: _summaryController.text.trim().isEmpty ? null : _summaryController.text.trim(),
      aiInsights: insights,
      tags: _tags,
      status: _status,
      archived: _status == IdeaStatus.archived,
    );

    Navigator.of(context).pop(updated);
  }
}
