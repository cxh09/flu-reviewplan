import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plan_data.dart';
import '../data/plaza_data.dart';
import '../models/plan.dart';
import '../stores/connection.dart';
import '../stores/plan_store.dart';
import '../utils/app_globals.dart';
import '../utils/date_utils.dart';
import 'app_ui.dart';
import 'date_picker_sheet.dart';

/// 日程详情（对应网页版日程表右侧的「日程详情」面板）。
///
/// 表单改动即写回 store；store 会归一化（空标题、非法日期不会覆盖原值）。
Future<void> showScheduleDetailSheet(BuildContext context, String planId) {
  return showAppSheetBuilder<void>(
    context,
    (_) => _ScheduleDetailSheet(planId: planId),
  );
}

class _ScheduleDetailSheet extends StatefulWidget {
  const _ScheduleDetailSheet({required this.planId});

  final String planId;

  @override
  State<_ScheduleDetailSheet> createState() => _ScheduleDetailSheetState();
}

class _ScheduleDetailSheetState extends State<_ScheduleDetailSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _linkController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final plan = context.read<PlanStore>().plans.firstWhere(
          (item) => item.id == widget.planId,
          orElse: () => const Plan(id: '', title: ''),
        );
    _titleController = TextEditingController(text: plan.title);
    _linkController = TextEditingController(text: plan.link);
    _noteController = TextEditingController(text: plan.note);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Plan? _findPlan(PlanStore planStore) {
    for (final plan in planStore.plans) {
      if (plan.id == widget.planId) return plan;
    }
    return null;
  }

  String _rangeText(Plan plan) =>
      '${formatClock(plan.startHour)} - ${formatClock(plan.startHour + plan.duration / 60)}';

  Future<void> _pickDate(Plan plan) async {
    final picked = await showDatePickerSheet(context, currentKey: plan.date, title: '日程日期');
    if (picked == null || !mounted) return;
    context.read<PlanStore>().updatePlan(widget.planId, date: picked);
  }

  Future<void> _pickStartHour(Plan plan) async {
    final hour = plan.startHour.floor().clamp(kFirstHour, kEndHour - 1);
    final picked = await showAppSheet<int>(
      context,
      title: '开始时间',
      child: ChoiceChips<int>(
        options: kTimelineHours,
        selected: hour,
        labelOf: (value) => formatHour(value),
        onChanged: (value) => Navigator.of(context).pop(value),
      ),
    );
    if (picked == null || !mounted) return;
    context.read<PlanStore>().updatePlan(widget.planId, startHour: picked.toDouble());
  }

  /// 详情里通用的「点一行改一个值」样式
  Widget _tappableRow({
    required TThemeData theme,
    required IconData icon,
    required String value,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(theme.radiusDefault),
          border: Border.all(color: theme.componentBorderColor),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: theme.textColorSecondary),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontSize: 15)),
            const Spacer(),
            if (trailingText != null) ...<Widget>[
              Text(
                trailingText,
                style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
              ),
              const SizedBox(width: 6),
            ],
            Icon(TIcons.chevron_right, size: 18, color: theme.textColorPlaceholder),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final planStore = context.watch<PlanStore>();
    final plan = _findPlan(planStore);

    // 计划被别的地方删掉（比如另一台设备同步过来）时，弹层自己收起来，
    // 不要留一个空白盒子
    if (plan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const AppSheetShell(
        title: '日程详情',
        child: SizedBox(height: 80),
      );
    }

    final color = categoryColor(plan.category);

    return AppSheetShell(
      title: '日程详情',
      footer: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TButton(
                  variant: TButtonVariant.outline,
                  colorScheme: TButtonColorScheme.primary,
                  icon: Icon(plan.done ? TIcons.rollback : TIcons.check, size: 16),
                  child: Text(plan.done ? '标记为未完成' : '标记为已完成'),
                  onPressed: () => planStore.togglePlanDone(plan.id),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TButton(
                  variant: TButtonVariant.outline,
                  colorScheme: TButtonColorScheme.defaultTheme,
                  icon: const Icon(TIcons.swap_right, size: 16),
                  child: const Text('退回待办'),
                  onPressed: () {
                    planStore.unschedulePlan(plan.id);
                    Navigator.of(context).maybePop();
                    if (isOnline) showInfoToast('「${plan.title}」已退回待办清单');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TButton(
            variant: TButtonVariant.text,
            colorScheme: TButtonColorScheme.danger,
            icon: const Icon(TIcons.delete, size: 16),
            child: const Text('删除日程'),
            onPressed: () {
              planStore.removePlan(plan.id);
              Navigator.of(context).maybePop();
              if (isOnline) showSuccessToast('「${plan.title}」已删除');
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.bgColorSecondaryContainer,
              borderRadius: BorderRadius.circular(theme.radiusDefault),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        plan.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (plan.done)
                      MetaChip(text: '已完成', color: theme.successNormalColor),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatMD(plan.date)} · ${_rangeText(plan)}',
                  style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: '日程名称',
            child: TInput(
              controller: _titleController,
              onChanged: (value) => planStore.updatePlan(widget.planId, title: value),
            ),
          ),
          AppFormField(
            label: '附件或链接',
            tip: '粘贴网盘 / 文档链接，选填',
            child: TInput(
              controller: _linkController,
              hintText: 'https://…',
              inputType: TextInputType.url,
              onChanged: (value) => planStore.updatePlan(widget.planId, link: value),
            ),
          ),
          AppFormField(
            label: '日期',
            child: _tappableRow(
              theme: theme,
              icon: TIcons.calendar,
              value: plan.date,
              onTap: () => _pickDate(plan),
            ),
          ),
          AppFormField(
            label: '开始时间',
            child: _tappableRow(
              theme: theme,
              icon: TIcons.time,
              value: formatClock(plan.startHour),
              trailingText: _rangeText(plan),
              onTap: () => _pickStartHour(plan),
            ),
          ),
          AppFormField(
            label: '时长（分钟）',
            child: TStepper(
              value: plan.duration,
              min: kMinDuration,
              max: kMaxDuration,
              step: 5,
              onChanged: (value) =>
                  planStore.updatePlan(widget.planId, duration: value.toInt()),
            ),
          ),
          AppFormField(
            label: '备注',
            child: TTextarea(
              controller: _noteController,
              hintText: '选填',
              minLines: 2,
              maxLines: 4,
              onChanged: (value) => planStore.updatePlan(widget.planId, note: value),
            ),
          ),
        ],
      ),
    );
  }
}
