import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../utils/date_utils.dart';
import 'app_ui.dart';

/// 日期选择弹层（用 TDesign 的滚轮选择器，返回 `YYYY-MM-DD`）
Future<String?> showDatePickerSheet(
  BuildContext context, {
  required String currentKey,
  String title = '选择日期',
}) {
  return showAppSheetBuilder<String>(
    context,
    (_) => _DatePickerSheet(currentKey: currentKey, title: title),
  );
}

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({required this.currentKey, required this.title});

  final String currentKey;
  final String title;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late TDateTimePickerValue _value;

  @override
  void initState() {
    super.initState();
    final date = parseDateKey(widget.currentKey);
    _value = TDateTimePickerValue(
      year: date.year,
      month: date.month,
      day: date.day,
    );
  }

  void _confirm() {
    final year = _value.year;
    final month = _value.month;
    final day = _value.day;
    if (year == null || month == null || day == null) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pop(toDateKey(DateTime(year, month, day)));
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetShell(
      title: widget.title,
      footer: AppSheetActions(
        confirmText: '确定',
        onCancel: () => Navigator.of(context).maybePop(),
        onConfirm: _confirm,
      ),
      child: TDateTimePicker(
        value: _value,
        mode: DateTimePickerMode(dateMode: DateMode.date),
        start: const TDateTimePickerValue(year: 2000, month: 1, day: 1),
        end: const TDateTimePickerValue(year: 2100, month: 12, day: 31),
        onChanged: (value) => setState(() => _value = value),
      ),
    );
  }
}
