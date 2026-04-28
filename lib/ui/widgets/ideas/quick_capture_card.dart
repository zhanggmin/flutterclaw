import 'package:flutter/material.dart';

class QuickCaptureCard extends StatefulWidget {
  const QuickCaptureCard({
    super.key,
    required this.onSave,
    required this.onSaveAndExpand,
  });

  final void Function(String title, String body) onSave;
  final void Function(String title, String body) onSaveAndExpand;

  @override
  State<QuickCaptureCard> createState() => _QuickCaptureCardState();
}

class _QuickCaptureCardState extends State<QuickCaptureCard> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit(void Function(String title, String body) action) {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正文为必填项，请先输入想法内容。')),
      );
      return;
    }
    action(title, body);
    _titleController.clear();
    _bodyController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快速记录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bodyController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '正文（必填）',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _submit(widget.onSave),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _submit(widget.onSaveAndExpand),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('保存并发散'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
