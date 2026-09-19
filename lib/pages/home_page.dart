import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plaza_data.dart';
import '../models/plan.dart';
import '../stores/plan_store.dart';
import '../utils/app_tabs.dart';
import '../utils/date_utils.dart';
import '../widgets/app_ui.dart';

/// 首页（对应网页版 `views/HomeView.vue`）：
/// 高考倒计时 + 整体统计 + 未来 7 天的排版计划总览。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final planStore = context.watch<PlanStore>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _CountdownCard(planStore: planStore),
        const SizedBox(height: 14),
        _StatGrid(planStore: planStore),
        const SizedBox(height: 14),
        _UpcomingPlansCard(planStore: planStore),
      ],
    );
  }
}

/// 倒计时大卡
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.planStore});

  final PlanStore planStore;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final days = planStore.daysToGaokao;
    final daysLeft = days < 0 ? 0 : days;

    final label = days > 0
        ? '距离 ${planStore.gaokaoDate.substring(0, 4)} 年高考还有'
        : days == 0
            ? '今天就是高考'
            : '高考已经结束';

    String motivate;
    if (days > 200) {
      motivate = '一轮复习阶段，把每一天的计划落到实处，比什么都重要。';
    } else if (days > 100) {
      motivate = '基础已经打得差不多了，接下来是查漏补缺的关键期。';
    } else if (days > 30) {
      motivate = '进入冲刺阶段，稳住节奏比盲目刷更多题更重要。';
    } else if (days > 0) {
      motivate = '最后阶段，回归错题与课本，保持手感。';
    } else {
      motivate = '这一段旅程结束了，好好休息。';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.radiusExtraLarge),
        border: Border.all(color: theme.componentStrokeColor, width: 0.5),
        gradient: LinearGradient(
          colors: <Color>[
            theme.brandNormalColor.withValues(alpha: 0.10),
            theme.successNormalColor.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 13, color: theme.textColorSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: <Color>[Color(0xFF0052D9), Color(0xFF00A870)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(rect),
                blendMode: BlendMode.srcIn,
                child: Text(
                  '$daysLeft',
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '天',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '目标日期 ${formatCN(planStore.gaokaoDate)} · ${weekdayCN(planStore.gaokaoDate)}',
            style: TextStyle(fontSize: 12, color: theme.textColorSecondary),
          ),
          const SizedBox(height: 10),
          Text(
            motivate,
            style: TextStyle(
              fontSize: 12,
              height: 1.75,
              color: theme.textColorPlaceholder,
            ),
          ),
        ],
      ),
    );
  }
}

/// 4 个统计卡
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.planStore});

  final PlanStore planStore;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final items = <({String title, num value, String unit})>[
      (title: '待办清单', value: planStore.todoCount, unit: '项'),
      (title: '已排计划', value: planStore.planCount, unit: '项'),
      (title: '已完成', value: planStore.donePlanCount, unit: '项'),
      (title: '本周完成率', value: planStore.weekStats.rate, unit: '%'),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: items.map((item) {
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                item.title,
                style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '${item.value}',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.unit,
                    style: TextStyle(fontSize: 12, color: theme.textColorPlaceholder),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 未来 7 天的排版计划
class _UpcomingPlansCard extends StatelessWidget {
  const _UpcomingPlansCard({required this.planStore});

  final PlanStore planStore;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final groups = planStore.upcomingGroups;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: '我的排版计划',
            trailing: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.bgColorSecondaryContainer,
                    borderRadius: BorderRadius.circular(theme.radiusSmall),
                  ),
                  child: Text(
                    '未来 7 天',
                    style: TextStyle(fontSize: 11, color: theme.textColorSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => goToTab(AppTab.schedule),
                  icon: const Icon(TIcons.chevron_right, size: 18),
                  color: theme.textColorPlaceholder,
                  tooltip: '在日程表中查看',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            EmptyHint(
              text: '还没有排版计划\n先去日程广场挑几条日程加入待办清单，再到日程表拖到时间线上排班',
              actionText: '去日程广场',
              onAction: () => goToTab(AppTab.plaza),
            )
          else
            ...groups.map((group) => _DayGroup(group: group)),
        ],
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.group});

  final PlanGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final today = isToday(group.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                formatCN(group.date),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: today ? theme.brandLightColor : theme.bgColorSecondaryContainer,
                  borderRadius: BorderRadius.circular(theme.radiusSmall),
                ),
                child: Text(
                  today ? '今天' : weekdayCN(group.date),
                  style: TextStyle(
                    fontSize: 11,
                    color: today ? theme.brandNormalColor : theme.textColorSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.items.length} 项',
                style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...group.items.map((plan) => _PlanRow(plan: plan)),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final color = categoryColor(plan.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.bgColorSecondaryContainer,
        borderRadius: BorderRadius.circular(theme.radiusDefault),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Text(
              formatClock(plan.startHour),
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: theme.textColorSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              plan.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: plan.done ? theme.textColorPlaceholder : theme.textColorPrimary,
                decoration: plan.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          MetaChip(text: plan.category, color: color),
          const SizedBox(width: 6),
          Text(
            '${plan.duration} 分钟',
            style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
          ),
          if (plan.done) ...<Widget>[
            const SizedBox(width: 6),
            Icon(TIcons.check_circle, size: 14, color: theme.successNormalColor),
          ],
        ],
      ),
    );
  }
}
