import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plaza_data.dart';
import '../models/plaza_item.dart';
import '../utils/app_globals.dart';
import '../utils/url_utils.dart';
import 'app_ui.dart';

/// 合集内日程的提交结果
class PlazaItemFormResult {
  const PlazaItemFormResult({
    required this.title,
    required this.link,
    required this.duration,
  });

  final String title;
  final String link;

  /// 预估耗时（分钟）
  final int duration;
}

/// 添加 / 编辑合集里的日程（对应网页版 `components/PlazaItemDialog.vue`）。
///
/// 科目、难度不再让用户填：新建时继承合集科目与默认值，编辑时 store 会保留原值。
Future<PlazaItemFormResult?> showPlazaItemSheet(
  BuildContext context, {
  PlazaItem? item,
}) {
  return showAppSheetBuilder<PlazaItemFormResult>(
    context,
    (_) => _PlazaItemSheet(item: item),
  );
}

class _PlazaItemSheet extends StatefulWidget {
  const _PlazaItemSheet({this.item});

  final PlazaItem? item;

  @override
  State<_PlazaItemSheet> createState() => _PlazaItemSheetState();
}

class _PlazaItemSheetState extends State<_PlazaItemSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _linkController;

  /// 预估耗时，按「几小时几分钟」分开记，提交时换算成分钟
  late int _hours;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _linkController = TextEditingController(text: widget.item?.link ?? '');
    final total = widget.item?.duration ?? kDefaultItemDuration;
    _hours = total ~/ 60;
    _minutes = total % 60;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showWarningToast('请输入日程标题');
      return;
    }

    final link = _linkController.text.trim();
    if (!isValidHttpLink(link)) {
      showWarningToast('链接无效，请检查后重试');
      return;
    }

    final duration = (_hours * 60 + _minutes).clamp(5, 24 * 60).toInt();
    Navigator.of(context).pop(
      PlazaItemFormResult(title: title, link: link, duration: duration),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetShell(
      title: widget.item == null ? '添加日程' : '编辑日程',
      footer: AppSheetActions(
        onCancel: () => Navigator.of(context).maybePop(),
        onConfirm: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppFormField(
            label: '日程标题',
            child: TInput(
              controller: _titleController,
              hintText: '例如：函数与导数专题刷题',
            ),
          ),
          AppFormField(
            label: '预估耗时',
            tip: '拖入日历时默认按这个时长占用时间块',
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TStepper(
                    value: _hours,
                    min: 0,
                    max: 23,
                    step: 1,
                    onChanged: (value) => setState(() => _hours = value.toInt()),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('小时', style: TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: TStepper(
                    value: _minutes,
                    min: 0,
                    max: 55,
                    step: 5,
                    onChanged: (value) => setState(() => _minutes = value.toInt()),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('分钟', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          AppFormField(
            label: '附件或链接',
            tip: '粘贴网盘 / 文档链接，选填',
            child: TInput(
              controller: _linkController,
              hintText: 'https://…',
              inputType: TextInputType.url,
            ),
          ),
        ],
      ),
    );
  }
}
