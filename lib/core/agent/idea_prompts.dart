/// Prompt builders for idea-related agent actions.
library;

class IdeaPrompts {
  const IdeaPrompts._();

  static String generateTitle(String ideaText) => '''
你是一个产品想法整理助手。
请基于用户输入生成一个简短、具体、可执行的标题。

要求：
- 输出 JSON 对象，字段为 title
- title 最长 20 个汉字
- 不要输出额外解释

用户输入：
$ideaText
''';

  static String generateSummary(String ideaText) => '''
你是一个产品想法整理助手。
请把下面的想法整理成 2~4 句摘要，突出问题、方案、价值。

要求：
- 输出 JSON 对象，字段为 summary
- 不要输出额外解释

用户输入：
$ideaText
''';

  static String recommendTags(String ideaText) => '''
你是一个产品想法整理助手。
请为该想法推荐 3~6 个标签。

要求：
- 首选输出 JSON 对象，字段为 tags，类型为字符串数组
- 标签尽量短（2~8 字）
- 不要输出额外解释

用户输入：
$ideaText
''';

  static String extractNextActions(String ideaText) => '''
你是一个产品想法整理助手。
请提炼最关键的下一步行动。

要求：
- 输出 JSON 对象，字段为 next_actions，类型为字符串数组
- 行动项 1~3 条
- 每条是可以直接执行的动作，避免空泛描述
- 不要输出额外解释

用户输入：
$ideaText
''';

  static String brainstormIdea(String ideaText) => '''
你是一个创意共创助手。
请围绕用户想法进行发散，给出可落地的补充方向。

要求：
- 输出 JSON 对象，字段为 brainstorm
- 结构建议：目标用户、差异化、风险与验证点
- 不要输出额外解释

用户输入：
$ideaText
''';
}
