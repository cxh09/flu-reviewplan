import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reviewplan_mobile/models/plan.dart';
import 'package:reviewplan_mobile/services/merge.dart';
import 'package:reviewplan_mobile/utils/date_utils.dart';
import 'package:reviewplan_mobile/utils/url_utils.dart';
import 'package:reviewplan_mobile/widgets/app_ui.dart';
import 'package:reviewplan_mobile/widgets/schedule_layout.dart';

void main() {
  group('日期工具', () {
    test('toDateKey / parseDateKey 能原样往返', () {
      expect(toDateKey(DateTime(2026, 9, 11)), '2026-09-11');
      expect(isValidDateKey('2026-09-11'), isTrue);
      expect(isValidDateKey('2026-02-30'), isFalse);
      expect(isValidDateKey('2026-9-1'), isFalse);
    });

    test('addDays 跨月跨年', () {
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(addDays('2026-03-01', -1), '2026-02-28');
    });

    test('diffDays 与今天判定', () {
      expect(diffDays('2026-09-11', '2026-09-20'), 9);
      expect(isToday(todayKey()), isTrue);
    });

    test('formatClock 把小数小时格式化成 HH:mm', () {
      expect(formatClock(9.75), '09:45');
      expect(formatClock(23.5), '23:30');
      expect(formatClock(24), '00:00');
    });

    test('dateRange 生成连续日期', () {
      expect(dateRange('2026-09-11', 3), <String>[
        '2026-09-11',
        '2026-09-12',
        '2026-09-13',
      ]);
    });
  });

  group('链接归一化', () {
    test('只放行 http / https，裸域名补 https', () {
      expect(sanitizeLink('https://example.com/a'), 'https://example.com/a');
      expect(sanitizeLink('example.com'), 'https://example.com');
      expect(sanitizeLink('javascript:alert(1)'), '');
      expect(sanitizeLink('data:text/html;base64,xxx'), '');
      expect(sanitizeLink('  '), '');
    });
  });

  group('快照合并', () {
    Map<String, dynamic> snapshot({
      List<Map<String, dynamic>> todos = const <Map<String, dynamic>>[],
      List<Map<String, dynamic>> plans = const <Map<String, dynamic>>[],
      List<Map<String, dynamic>> deleted = const <Map<String, dynamic>>[],
      String gaokaoDate = '2027-06-07',
      int gaokaoAt = 0,
    }) {
      return <String, dynamic>{
        'gaokaoDate': gaokaoDate,
        'gaokaoDateUpdatedAt': gaokaoAt,
        'todos': todos,
        'plans': plans,
        'collections': <Map<String, dynamic>>[],
        'deleted': deleted,
      };
    }

    test('同一条按 updatedAt 取新的', () {
      final merged = mergeSnapshots(
        snapshot(todos: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'title': '本地新', 'updatedAt': 200},
        ]),
        snapshot(todos: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'title': '云端旧', 'updatedAt': 100},
        ]),
      );

      final todos = merged['todos'] as List<dynamic>;
      expect(todos.length, 1);
      expect((todos.first as Map)['title'], '本地新');
    });

    test('时间戳相同时以云端为准', () {
      final merged = mergeSnapshots(
        snapshot(todos: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'title': '本地', 'updatedAt': 100},
        ]),
        snapshot(todos: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'title': '云端', 'updatedAt': 100},
        ]),
      );

      final todos = merged['todos'] as List<dynamic>;
      expect((todos.first as Map)['title'], '云端');
    });

    test('删除标记让已删除的条目不再复活', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final merged = mergeSnapshots(
        snapshot(todos: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'title': '残留副本', 'updatedAt': now - 1000},
        ]),
        snapshot(
          deleted: <Map<String, dynamic>>[
            <String, dynamic>{'id': 'a', 'at': now - 100},
          ],
        ),
      );

      expect(merged['todos'], isEmpty);
      expect((merged['deleted'] as List).length, 1);
    });

    test('过期删除标记会被回收', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final merged = mergeSnapshots(
        snapshot(),
        snapshot(deleted: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'old', 'at': now - 40 * 24 * 60 * 60 * 1000},
        ]),
        now,
      );

      expect(merged['deleted'], isEmpty);
    });

    test('高考日期按各自的修改时间决定归属', () {
      final merged = mergeSnapshots(
        snapshot(gaokaoDate: '2028-06-07', gaokaoAt: 500),
        snapshot(gaokaoDate: '2027-06-07', gaokaoAt: 100),
      );

      expect(merged['gaokaoDate'], '2028-06-07');
    });

    test('合集里的日程会各自合并', () {

      final merged = mergeSnapshots(
        <String, dynamic>{
          ...snapshot(),
          'collections': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c1',
              'name': '数学',
              'updatedAt': 10,
              'items': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'i1', 'title': '本地加的', 'updatedAt': 20},
              ],
            },
          ],
        },
        <String, dynamic>{
          ...snapshot(),
          'collections': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c1',
              'name': '数学',
              'updatedAt': 10,
              'items': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'i2', 'title': '云端加的', 'updatedAt': 20},
              ],
            },
          ],
        },
      );

      final collections = merged['collections'] as List<dynamic>;
      final items = (collections.first as Map)['items'] as List<dynamic>;
      expect(items.length, 2);
    });
  });

  group('日程表排版', () {
    // 只关心开始时间与时长，其余字段用默认值
    Plan plan(String id, double startHour, int duration) => Plan(
          id: id,
          title: id,
          date: '2026-09-11',
          startHour: startHour,
          duration: duration,
        );

    test('不重叠的计划只占一层', () {
      final layout = computeDayLayout(
        <Plan>[plan('a', 8, 60), plan('b', 10, 60)],
        'sig',
      );

      expect(layout.lanes, 1);
      expect(layout.blocks.every((block) => block.lane == 0), isTrue);
      expect(layout.height, ScheduleMetrics.laneHeight);
    });

    test('完全重叠的计划分成两层', () {
      final layout = computeDayLayout(
        <Plan>[plan('a', 8, 60), plan('b', 8, 60)],
        'sig',
      );

      expect(layout.lanes, 2);
      expect(layout.blocks.map((block) => block.lane).toSet(), <int>{0, 1});
      expect(layout.height, ScheduleMetrics.laneHeight * 2);
    });

    test('首尾相接（8:00-9:00 与 9:00-10:00）可以复用同一层', () {
      final layout = computeDayLayout(
        <Plan>[plan('a', 8, 60), plan('b', 9, 60)],
        'sig',
      );

      expect(layout.lanes, 1);
    });

    test('横向位置与宽度按时间占比换算', () {
      final layout = computeDayLayout(<Plan>[plan('a', 9, 180)], 'sig');
      final block = layout.blocks.single;

      // 9:00 距 6:00 三小时，占 18 列的 3/18
      expect(block.left, closeTo(ScheduleMetrics.contentWidth * 3 / 18, 0.01));
      // 时长 180 分钟＝3 小时
      expect(block.width, closeTo(ScheduleMetrics.contentWidth * 3 / 18, 0.01));
    });

    test('超出时间轴范围的计划会被夹回来', () {
      final layout = computeDayLayout(<Plan>[plan('a', 23.5, 600)], 'sig');
      final block = layout.blocks.single;

      expect(block.end, 24);
      expect(block.start, 23.5);
    });

    test('空的一天是 1 层', () {
      final layout = computeDayLayout(<Plan>[], '');
      expect(layout.lanes, 1);
      expect(layout.blocks, isEmpty);
    });

    test('签名包含 updatedAt，改了标题也会重新排版', () {
      final before = <Plan>[plan('a', 8, 60)];
      final after = <Plan>[
        plan('a', 8, 60).copyWith(title: '改过的标题', updatedAt: 12345),
      ];

      expect(dayLayoutSignature(after), isNot(dayLayoutSignature(before)));
    });
  });

  group('落点单元格', () {
    test('值相等即相等，可以拿来做"变化才通知"的判断', () {
      expect(const DropCell('2026-09-11', 9), const DropCell('2026-09-11', 9));
      expect(const DropCell('2026-09-11', 9), isNot(const DropCell('2026-09-11', 10)));
      expect(
        const DropCell('2026-09-11', 9).hashCode,
        const DropCell('2026-09-11', 9).hashCode,
      );
    });

    test('containsHour 只命中落在这一格里的时间', () {
      const cell = DropCell('2026-09-11', 9);
      expect(cell.containsHour(9), isTrue);
      expect(cell.containsHour(9.75), isTrue);
      expect(cell.containsHour(10), isFalse);
      expect(cell.containsHour(8.75), isFalse);
    });
  });

  group('半屏弹层', () {
    // Flutter 会在没有 Material 祖先的子树里把文字套成「红字 + 双黄下划线」的错误样式。
    // 弹层从 showModalBottomSheet 换成自定义路由时丢过这一层 Material（底部会出现双黄线），
    // 这个用例守住它别再丢。
    testWidgets('弹层里的文字不带错误的文本装饰', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  title: '标题',
                  footer: AppSheetActions(
                    onCancel: () => Navigator.of(context).pop(),
                    onConfirm: () => Navigator.of(context).pop(),
                  ),
                  child: const Text('正文'),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      for (final label in <String>['标题', '正文', '保存']) {
        final inherited =
            DefaultTextStyle.of(tester.element(find.text(label))).style;
        expect(
          inherited.decoration ?? TextDecoration.none,
          TextDecoration.none,
          reason: '$label 继承了错误的文本装饰（说明弹层里缺 Material 祖先）',
        );
      }
    });

    // 对照组：证明"没有 Material 祖先就会套上双黄下划线"这个前提成立，
    // 也就是上面那条用例在没有 Material 时确实会红。
    testWidgets('对照组：没有 Material 祖先时文字会带双黄下划线', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(builder: (_) => const Center(child: Text('裸文字'))),
            ],
          ),
        ),
      );

      final inherited = DefaultTextStyle.of(tester.element(find.text('裸文字'))).style;
      expect(inherited.decoration, TextDecoration.underline);
      expect(inherited.decorationStyle, TextDecorationStyle.double);
      expect(inherited.decorationColor, const Color(0xFFFFFF00));
    });
  });
}
