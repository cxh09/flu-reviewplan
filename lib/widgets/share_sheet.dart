import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../services/api_client.dart';
import '../stores/sync_store.dart';
import '../utils/app_globals.dart';
import '../utils/date_utils.dart';
import 'app_ui.dart';
import 'date_picker_sheet.dart';

/// 分享日程表：选择可查看的日期范围，生成 /share/xxxx 只读链接。
Future<void> showShareSheet(BuildContext context) {
  return showAppSheetBuilder<void>(context, (_) => const _ShareSheet());
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet();

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late String _start;
  late String _end;
  bool _submitting = false;
  String _url = '';

  @override
  void initState() {
    super.initState();
    _start = todayKey();
    _end = addDays(todayKey(), 7);
  }

  Future<void> _pickStart() async {
    final picked = await showDatePickerSheet(context, currentKey: _start, title: '开始日期');
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked;
      if (_end.compareTo(_start) < 0) _end = picked;
      _url = '';
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePickerSheet(context, currentKey: _end, title: '结束日期');
    if (picked == null || !mounted) return;
    setState(() {
      _end = picked;
      _url = '';
    });
  }

  Future<void> _generate() async {
    if (_submitting) return;
    final sync = context.read<SyncStore>();
    if (!sync.configured) {
      showWarningToast('请先在「设置」里配置服务端地址');
      return;
    }
    if (_start.compareTo(_end) > 0) {
      showWarningToast('开始日期不能晚于结束日期');
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await ApiClient.createShare(
        sync.normalizedUrl,
        sync.accessToken,
        _start,
        _end,
      );
      final code = '${res?['code'] ?? ''}';
      if (code.isEmpty) {
        showErrorToast('生成分享链接失败');
        return;
      }
      setState(() => _url = '${sync.normalizedUrl}/share/$code');
      showSuccessToast('分享链接已生成');
    } on ApiException catch (err) {
      showErrorToast(err.message);
    } catch (err) {
      showErrorToast('$err');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copy() async {
    if (_url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _url));
    showSuccessToast('链接已复制到剪贴板');
  }

  Widget _dateRow(TThemeData theme, {required String label, required String value, required VoidCallback onTap}) {
    return AppFormField(
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(theme.radiusDefault),
            border: Border.all(color: theme.componentBorderColor),
          ),
          child: Row(
            children: <Widget>[
              Icon(TIcons.calendar, size: 18, color: theme.textColorSecondary),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(fontSize: 15)),
              const Spacer(),
              Icon(TIcons.chevron_right, size: 18, color: theme.textColorPlaceholder),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;

    return AppSheetShell(
      title: '分享日程表',
      footer: AppSheetActions(
        onCancel: () => Navigator.of(context).maybePop(),
        onConfirm: _generate,
        confirmText: '生成链接',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '选择允许查看的日期范围，生成一个只读链接；对方只能看到这段时间内的日程，无法编辑。',
            style: TextStyle(fontSize: 12, height: 1.6, color: theme.textColorSecondary),
          ),
          const SizedBox(height: 14),
          _dateRow(theme, label: '开始日期', value: _start, onTap: _pickStart),
          _dateRow(theme, label: '结束日期', value: _end, onTap: _pickEnd),
          if (_submitting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: TLoading(size: TLoadingSize.medium)),
            ),
          if (_url.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            AppFormField(
              label: '分享链接',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.bgColorSecondaryContainer,
                  borderRadius: BorderRadius.circular(theme.radiusDefault),
                ),
                child: SelectableText(
                  _url,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            TButton(
              size: TButtonSize.medium,
              variant: TButtonVariant.outline,
              colorScheme: TButtonColorScheme.primary,
              icon: const Icon(TIcons.copy, size: 16),
              child: const Text('复制链接'),
              onPressed: _copy,
            ),
          ],
        ],
      ),
    );
  }
}
