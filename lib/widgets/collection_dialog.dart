import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plaza_data.dart';
import '../models/collection.dart';
import '../utils/app_globals.dart';
import 'app_ui.dart';

/// 合集表单的提交结果（对应网页版 CollectionDialog 的 `submit` 事件）
class CollectionFormResult {
  const CollectionFormResult({
    required this.name,
    required this.category,
    required this.color,
    required this.desc,
  });

  final String name;
  final String category;
  final String color;
  final String desc;
}

/// 新建 / 编辑系列合集（对应网页版 `components/CollectionDialog.vue`）
Future<CollectionFormResult?> showCollectionSheet(
  BuildContext context, {
  Collection? collection,
}) {
  return showAppSheetBuilder<CollectionFormResult>(
    context,
    (_) => _CollectionSheet(collection: collection),
  );
}

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({this.collection});

  final Collection? collection;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  late String _category;
  late String _color;

  /// 上一次「跟随科目」得到的颜色：用户手动选过色后就不再自动跟随
  late String _autoColor;

  @override
  void initState() {
    super.initState();
    final source = widget.collection;
    _nameController = TextEditingController(text: source?.name ?? '');
    _descController = TextEditingController(text: source?.desc ?? '');
    _category = source?.category ?? '通用';
    _color = source?.color ?? (kCategoryColors[_category] ?? kCollectionColors.first);
    _autoColor = kCategoryColors[_category] ?? kCollectionColors.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _handleCategoryChange(String category) {
    final next = kCategoryColors[category] ?? kCollectionColors.first;
    setState(() {
      _category = category;
      // 没手动改过颜色时才跟随科目的主题色
      if (_color == _autoColor) _color = next;
      _autoColor = next;
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showWarningToast('请输入合集名称');
      return;
    }

    Navigator.of(context).pop(
      CollectionFormResult(
        name: name,
        category: _category,
        color: _color,
        desc: _descController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetShell(
      title: widget.collection == null ? '新建系列合集' : '编辑系列合集',
      footer: AppSheetActions(
        onCancel: () => Navigator.of(context).maybePop(),
        onConfirm: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppFormField(
            label: '合集名称',
            child: AppTextInput(
              controller: _nameController,
              hintText: '例如：数学专题突破',
            ),
          ),
          AppFormField(
            label: '主攻科目',
            child: ChoiceChips<String>(
              options: kCategoryOptions,
              selected: _category,
              onChanged: _handleCategoryChange,
            ),
          ),
          AppFormField(
            label: '主题色',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kCollectionColors.map((color) {
                final selected = _color == color;
                return GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: _ColorDot(color: color, selected: selected),
                );
              }).toList(),
            ),
          ),
          AppFormField(
            label: '合集简介',
            tip: '这个合集适合什么时候做、想达到什么效果',
            child: TTextarea(
              controller: _descController,
              hintText: '选填',
              minLines: 2,
              maxLines: 4,
            ),
          ),
        ],
      ),
    );
  }
}

/// 主题色圆点：选中时套一圈与色值同色的光晕
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected});

  final String color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final value = colorFromHex(color);

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: value,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? theme.bgColorContainer : Colors.transparent,
          width: 3,
        ),
        boxShadow: selected
            ? <BoxShadow>[
                BoxShadow(
                  color: value.withValues(alpha: 0.5),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: selected
          ? const Icon(TIcons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}
