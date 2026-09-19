import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../data/plan_data.dart';
import '../models/todo.dart';
import '../stores/plan_store.dart';
import '../utils/app_globals.dart';
import '../utils/app_tabs.dart';
import '../utils/date_utils.dart';
import '../widgets/app_ui.dart';
import '../widgets/plan_block_view.dart';
import '../widgets/schedule_detail_sheet.dart';
import '../widgets/schedule_layout.dart';
import '../widgets/todo_panel_view.dart';

/// 日程表（对应网页版 `views/ScheduleView.vue`）：
/// 纵向连续日期、横向 06:00 ~ 24:00 时间轴，长按拖动排班 / 改时间 / 改时长。
///
/// 拖拽状态全部放在 [ValueNotifier] 上：手指移动不会触发整页重建，
/// 只有「浮层位置」「高亮的落点格子」「源卡片变灰」这几个小范围会刷新。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with TickerProviderStateMixin {
  // ---------- 日期扩展 ----------
  static const int initialPastDays = 7;
  static const int initialFutureDays = 21;
  static const int dayChunk = 14;
  static const int maxDays = 400;
  static const double scrollThreshold = 240;

  /// 待办面板高度（不含底部安全区）
  static const double panelHeight = 320;

  final GlobalKey _pageKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  final GlobalKey _panelKey = GlobalKey();
  final GlobalKey _unscheduleKey = GlobalKey();

  final ScrollController _vController = ScrollController();
  late final AnimationController _hAnim;

  /// 拖起浮层的弹入动画
  late final AnimationController _liftAnim;

  double _hOffset = 0;
  double _availableWidth = 0;

  late List<String> _days;
  bool _initialScrolled = false;
  bool _loadingMore = false;

  double _nowHour = 0;
  Timer? _nowTimer;

  // ---------- 拖拽状态 ----------

  /// 正在拖拽的条目 id（源卡片变灰 + 轻抬）
  final ValueNotifier<String?> _draggingId = ValueNotifier<String?>(null);

  /// 浮层跟随的全局坐标
  final ValueNotifier<Offset?> _dragPosition = ValueNotifier<Offset?>(null);

  /// 高亮的目标格子：只有真正跨格才通知
  final ValueNotifier<DropCell?> _dropCell = ValueNotifier<DropCell?>(null);

  /// 取消排班条：是否显示 + 是否已悬停
  final ValueNotifier<({bool visible, bool hovered})> _unscheduleBar =
      ValueNotifier<({bool visible, bool hovered})>((visible: false, hovered: false));

  DragKind? _dragKind;
  String? _dragId;
  String? _dragTitle;
  String? _dragCategory;
  Offset _dragStart = Offset.zero;

  /// 精确到 15 分钟的落点时间（高亮只用到整点，落下时才需要精确值）
  double _dropStartHour = kFirstHour.toDouble();

  // 拉伸时的原始值
  double _resizeStartHour = kFirstHour.toDouble();
  int _resizeDuration = kDefaultSlotMinutes;

  /// 上一次已经给过触感反馈的吸附档位，避免同一档位反复震动
  double? _lastResizeTick;

  Timer? _autoScrollTimer;
  double _autoScrollDx = 0;
  double _autoScrollDy = 0;

  bool _todoPanelOpen = false;

  // ---------- 缓存 ----------

  /// 每天的分层排版缓存
  final Map<String, DayLayout> _layoutCache = <String, DayLayout>{};

  /// 每行的累计高度，配合 store 版本号复用
  List<double>? _rowOffsets;
  int _rowOffsetsRevision = -1;
  int _rowOffsetsDayCount = -1;

  PlanStore get _planStore => context.read<PlanStore>();

  @override
  void initState() {
    super.initState();
    _days = dateRange(
      addDays(todayKey(), -initialPastDays),
      initialPastDays + initialFutureDays + 1,
    );
    _hAnim = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: ScheduleMetrics.contentWidth,
    );
    _hAnim.addListener(() => setState(() => _hOffset = _hAnim.value));
    _liftAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    _vController.addListener(_handleVerticalScroll);
    _updateNowHour();
    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(_updateNowHour);
    });

    // 首帧量完尺寸后：纵向定位到今天，横向把当前时刻对齐到可视区左侧 30%
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToToday();
      _scrollToNow();
      setState(() => _initialScrolled = true);
    });
  }

  @override
  void dispose() {
    _vController.removeListener(_handleVerticalScroll);
    _vController.dispose();
    _nowTimer?.cancel();
    _stopAutoScroll();
    _hAnim.dispose();
    _liftAnim.dispose();
    _draggingId.dispose();
    _dragPosition.dispose();
    _dropCell.dispose();
    _unscheduleBar.dispose();
    super.dispose();
  }

  void _updateNowHour() {
    final now = DateTime.now();
    _nowHour = now.hour + now.minute / 60;
  }

  // ---------- 纵向滚动：连续日期 + 首次定位到今天 ----------

  void _handleVerticalScroll() {
    if (!_vController.hasClients || !_initialScrolled || _loadingMore) return;

    final position = _vController.position;
    if (position.pixels < scrollThreshold) {
      _prependDays();
    } else if (position.maxScrollExtent - position.pixels < scrollThreshold) {
      _appendDays();
    }
  }

  void _prependDays() {
    if (_days.length >= maxDays) return;
    _loadingMore = true;

    final first = _days.first;
    final added = dateRange(addDays(first, -dayChunk), dayChunk);
    final addedHeight = added.fold<double>(0, (sum, date) => sum + _rowHeight(date));

    setState(() => _days = <String>[...added, ..._days]);
    _pruneLayoutCache();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vController.hasClients) {
        // 向前插入会让内容整体下移，同步补偿滚动位置，避免画面跳动
        _vController.jumpTo(_vController.offset + addedHeight);
      }
      _loadingMore = false;
    });
  }

  void _appendDays() {
    if (_days.length >= maxDays) return;
    _loadingMore = true;

    final last = _days.last;
    setState(() => _days = <String>[..._days, ...dateRange(addDays(last, 1), dayChunk)]);
    _pruneLayoutCache();

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadingMore = false);
  }

  /// 防御性回收：日期上限是 400，正常情况下缓存不会超；
  /// 万一以后把上限调大，这里保证缓存不会跟着无限增长。
  void _pruneLayoutCache() {
    if (_layoutCache.length <= maxDays + 32) return;
    final alive = _days.toSet();
    _layoutCache.removeWhere((date, _) => !alive.contains(date));
  }

  void _scrollToToday() {
    if (!_vController.hasClients) return;
    _vController.jumpTo(
      clampDouble(_offsetOfDate(todayKey()), 0, _vController.position.maxScrollExtent),
    );
  }

  /// 横向滚动，让当前时刻落在可视区左侧 30% 处
  void _scrollToNow() {
    if (_availableWidth <= 0) return;
    final offset = (_nowHour - kFirstHour) / kHoursCount * ScheduleMetrics.contentWidth;
    _setHOffset(offset - _availableWidth * 0.3);
  }

  // ---------- 行高与偏移 ----------

  /// 每一行的累计高度：第 i 行顶端 = offsets[i]，最后一项是总高。
  ///
  /// 用 store 的版本号 + 天数判断能不能复用——拖动"移动"的过程中数据没变，
  /// 所以一条拖拽序列里只会算一次，而不是每次手指移动都重算几百行。
  List<double> _rowOffsetsList() {
    final cached = _rowOffsets;
    final revision = _planStore.revision;
    if (cached != null &&
        _rowOffsetsRevision == revision &&
        _rowOffsetsDayCount == _days.length) {
      return cached;
    }

    final offsets = List<double>.filled(_days.length + 1, 0);
    for (var i = 0; i < _days.length; i += 1) {
      offsets[i + 1] = offsets[i] + _rowHeight(_days[i]);
    }
    _rowOffsets = offsets;
    _rowOffsetsRevision = revision;
    _rowOffsetsDayCount = _days.length;
    return offsets;
  }

  double _offsetOfDate(String date) {
    final index = _days.indexOf(date);
    if (index <= 0) return 0;
    return _rowOffsetsList()[index];
  }

  /// 按「距内容顶部的像素」反查日期（二分，不碰 RenderObject）
  String? _dateAtContentOffset(double contentY) {
    if (contentY < 0) return null;
    final offsets = _rowOffsetsList();

    var low = 0;
    var high = offsets.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (offsets[mid] <= contentY) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final index = low - 1;
    if (index < 0 || index >= _days.length) return null;
    return _days[index];
  }

  /// 保证目标日期已经在渲染范围内，必要时向对应方向补齐
  Future<void> _ensureDateRendered(String date) async {
    if (_days.contains(date)) return;

    final first = _days.first;
    final last = _days.last;

    if (date.compareTo(first) < 0) {
      setState(() {
        _days = <String>[...dateRange(date, diffDays(date, first)), ..._days];
      });
    } else {
      setState(() {
        _days = <String>[..._days, ...dateRange(addDays(last, 1), diffDays(last, date))];
      });
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _scrollToDate(String date) async {
    await _ensureDateRendered(date);
    if (!mounted || !_vController.hasClients) return;
    await _vController.animateTo(
      clampDouble(_offsetOfDate(date), 0, _vController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  // ---------- 横向滚动 ----------

  double get _maxHOffset =>
      clampDouble(ScheduleMetrics.contentWidth - _availableWidth, 0, ScheduleMetrics.contentWidth);

  void _setHOffset(double value) {
    final next = clampDouble(value, 0, _maxHOffset);
    if (next == _hOffset) return;
    _hAnim.value = next;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _hAnim.stop();
    setState(() {
      _hOffset = clampDouble(_hOffset - details.delta.dx, 0, _maxHOffset);
      _hAnim.value = _hOffset;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = -details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() < 60) return;
    final target = clampDouble(_hOffset + velocity * 0.18, 0, _maxHOffset);
    _hAnim.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.decelerate,
    );
  }

  // ---------- 计划排版 ----------

  DayLayout _layoutFor(String date) {
    final items = _planStore.plansOfDate(date);
    final signature = dayLayoutSignature(items);
    final cached = _layoutCache[date];
    if (cached != null && cached.signature == signature) return cached;

    final layout = computeDayLayout(items, signature);
    _layoutCache[date] = layout;
    return layout;
  }

  /// 行高＝该天计划占用的层数 × 每层高度
  double _rowHeight(String date) => _layoutFor(date).height;

  // ---------- 落点解析 ----------

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 用几何反算落点：横向按偏移换算时间，纵向按累计行高二分查日期。
  /// 不依赖 RenderObject 查找，也不需要给每一行挂 key。
  DropTarget? _resolveDrop(Offset global) {
    final gridRect = _rectOf(_gridKey);
    if (gridRect == null || !gridRect.contains(global)) return null;

    final localX = global.dx - gridRect.left + _hOffset;
    final rawHour = kFirstHour + localX / ScheduleMetrics.hourWidth;
    final snapped = (rawHour * 60 / ScheduleMetrics.snapMinutes).round() *
        ScheduleMetrics.snapMinutes /
        60;
    final startHour = clampDouble(
      snapped,
      kFirstHour.toDouble(),
      kEndHour - ScheduleMetrics.snapHours,
    );

    final date = _dateAtContentOffset(global.dy - gridRect.top + _vController.offset);
    if (date == null) return null;

    return DropTarget(date: date, startHour: startHour);
  }

  /// 落点是否在「退回待办」的两个区域上：底部取消条，或已展开的待办面板
  bool _isOverUnschedule(Offset global) {
    final bar = _rectOf(_unscheduleKey);
    if (bar != null && bar.contains(global)) return true;
    final panel = _rectOf(_panelKey);
    return panel != null && panel.contains(global);
  }

  // ---------- 拖拽 ----------

  void _beginDrag({
    required DragKind kind,
    required String id,
    required String title,
    required String category,
    required Offset start,
    double? fromStartHour,
    int? fromDuration,
  }) {
    // 起拖给一次明确反馈，否则触屏上很难判断"到底按住没有"
    HapticFeedback.mediumImpact();

    _lastResizeTick = null;
    _dragKind = kind;
    _dragId = id;
    _dragTitle = title;
    _dragCategory = category;
    _dragStart = start;
    _dropStartHour = kFirstHour.toDouble();
    if (fromStartHour != null) _resizeStartHour = fromStartHour;
    if (fromDuration != null) _resizeDuration = fromDuration;

    _draggingId.value = id;
    _dropCell.value = null;
    if (kind == DragKind.planMove) {
      _liftAnim.forward(from: 0);
      _setUnscheduleBar(visible: true, hovered: false);
    }
    // 最后再动坐标：它会立刻触发浮层渲染，此时上面这些字段都已经就位
    _dragPosition.value = kind.isResize ? null : start;

    if (!kind.isResize) _startAutoScroll();
  }

  void _onDragMove(Offset global) {
    final kind = _dragKind;
    if (kind == null) return;

    if (kind.isResize) {
      _applyResize(global);
      return;
    }

    _dragPosition.value = global;

    final hovering = kind == DragKind.planMove && _isOverUnschedule(global);
    _setUnscheduleBar(visible: kind == DragKind.planMove, hovered: hovering);

    final target = _resolveDrop(global);
    if (target != null && !hovering) _dropStartHour = target.startHour;

    // 悬停在"退回待办"上时不再高亮格子，避免两个落点暗示打架
    final cell = hovering ? null : target?.cell;
    if (_dropCell.value != cell) _dropCell.value = cell;

    _updateAutoScroll(global);
  }

  void _endDrag() {
    final kind = _dragKind;
    final id = _dragId;
    final cell = _dropCell.value;
    final hovering = _unscheduleBar.value.hovered;

    _resetDrag();
    if (kind == null || id == null) return;

    // 拉伸是实时生效的，抬手不需要再落一次
    if (kind.isResize) {
      HapticFeedback.lightImpact();
      return;
    }

    if (kind == DragKind.planMove && hovering) {
      HapticFeedback.lightImpact();
      _planStore.unschedulePlan(id);
      return;
    }

    if (cell == null) return;

    // 落点有效才给反馈，取消拖动（落空）保持安静
    HapticFeedback.lightImpact();
    final target = DropTarget(date: cell.date, startHour: _dropStartHour);
    final planStore = _planStore;
    if (kind == DragKind.todo) {
      planStore.scheduleFromTodo(id, target.date, target.startHour);
    } else {
      planStore.movePlan(id, target.date, target.startHour);
    }
  }

  void _resetDrag() {
    _stopAutoScroll();
    _dragKind = null;
    _dragId = null;
    _dragTitle = null;
    _dragCategory = null;
    _draggingId.value = null;
    _dragPosition.value = null;
    _dropCell.value = null;
    _setUnscheduleBar(visible: false, hovered: false);
  }

  void _setUnscheduleBar({required bool visible, required bool hovered}) {
    final next = (visible: visible, hovered: hovered);
    if (_unscheduleBar.value == next) return;
    _unscheduleBar.value = next;
  }

  /// 拖到边缘时自动滚动，方便把卡片拖到屏幕外的日期 / 时间
  void _updateAutoScroll(Offset global) {
    final gridRect = _rectOf(_gridKey);
    if (gridRect == null) {
      _stopAutoScroll();
      return;
    }

    var dx = 0.0;
    var dy = 0.0;
    const edge = ScheduleMetrics.edgeSize;

    if (global.dx < gridRect.left + edge) {
      dx = -ScheduleMetrics.edgeSpeed * ((gridRect.left + edge - global.dx) / edge);
    } else if (global.dx > gridRect.right - edge) {
      dx = ScheduleMetrics.edgeSpeed * ((global.dx - (gridRect.right - edge)) / edge);
    }

    if (global.dy < gridRect.top + edge) {
      dy = -ScheduleMetrics.edgeSpeed * ((gridRect.top + edge - global.dy) / edge);
    } else if (global.dy > gridRect.bottom - edge) {
      dy = ScheduleMetrics.edgeSpeed * ((global.dy - (gridRect.bottom - edge)) / edge);
    }

    _autoScrollDx = dx;
    _autoScrollDy = dy;

    if (dx != 0 || dy != 0) {
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final kind = _dragKind;
      if (kind == null) {
        _stopAutoScroll();
        return;
      }

      if (_autoScrollDx != 0) {
        final next = clampDouble(_hOffset + _autoScrollDx, 0, _maxHOffset);
        if (next != _hOffset) setState(() => _hOffset = next);
      }
      if (_autoScrollDy != 0 && _vController.hasClients) {
        final position = _vController.position;
        final next = clampDouble(
          _vController.offset + _autoScrollDy,
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (next != _vController.offset) _vController.jumpTo(next);
      }

      // 自动滚动之后落点会变，重新算一次
      final global = _dragPosition.value;
      if (global != null && !kind.isResize) {
        final hovering = kind == DragKind.planMove && _isOverUnschedule(global);
        _setUnscheduleBar(visible: kind == DragKind.planMove, hovered: hovering);

        final target = _resolveDrop(global);
        if (target != null && !hovering) _dropStartHour = target.startHour;
        final cell = hovering ? null : target?.cell;
        if (_dropCell.value != cell) _dropCell.value = cell;
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDx = 0;
    _autoScrollDy = 0;
  }

  // ---------- 拉伸：调整开始时间 / 时长 ----------

  void _applyResize(Offset global) {
    final id = _dragId;
    if (id == null) return;

    final deltaHours = (global.dx - _dragStart.dx) / ScheduleMetrics.hourWidth;
    final planStore = _planStore;

    if (_dragKind == DragKind.resizeEnd) {
      // 拖右边缘：开始时间不变，只改时长
      final snapped = ((_resizeDuration + deltaHours * 60) / ScheduleMetrics.snapMinutes)
              .round() *
          ScheduleMetrics.snapMinutes;
      final maxDuration = ((kEndHour - _resizeStartHour) * 60).round().toDouble();
      final next = clampDouble(
        snapped,
        ScheduleMetrics.snapMinutes.toDouble(),
        maxDuration,
      );
      _tickResize(next);
      planStore.resizePlan(id, duration: next.toInt());
      return;
    }

    // 拖左边缘：结束时间保持不变，开始时间同样按 15 分钟吸附
    final endHour = _resizeStartHour + _resizeDuration / 60;
    final rawStart = _resizeStartHour + deltaHours;
    final snappedStart = (rawStart / ScheduleMetrics.snapHours).round() *
        ScheduleMetrics.snapHours;
    final nextStart = clampDouble(
      snappedStart,
      kFirstHour.toDouble(),
      endHour - ScheduleMetrics.snapHours,
    );
    _tickResize(nextStart);
    final duration =
        (((endHour - nextStart) * 60) / ScheduleMetrics.snapMinutes).round() *
            ScheduleMetrics.snapMinutes;
    planStore.resizePlan(id, startHour: nextStart, duration: duration.toInt());
  }

  /// 拉伸时每跨过一个吸附档位给一次轻微反馈，手感上"咬得住"
  void _tickResize(double value) {
    if (_lastResizeTick == value) return;
    _lastResizeTick = value;
    HapticFeedback.selectionClick();
  }

  // ---------- 添加日程（仅从待办清单排班） ----------

  /// 待办一键排班：直接排到今天 19:00，之后可在详情里改时间
  Future<void> _quickSchedule(Todo todo) async {
    final planStore = _planStore;
    final targetDate = todayKey();
    final created = planStore.scheduleFromTodo(todo.id, targetDate, 19);

    // 只读模式下 store 会拒绝写入并给出提示，这里不再滚动也不再报「已添加」
    if (created == null) return;

    // 目标日期可能还没被渲染出来，补齐后滚动过去，保证能看到结果
    if (!mounted) return;
    await _scrollToDate(targetDate);
    if (mounted) showSuccessToast('已添加到排版计划');
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final theme = context.tTheme;
    final planStore = context.watch<PlanStore>();
    final media = MediaQuery.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        _availableWidth = constraints.maxWidth - ScheduleMetrics.dateWidth;

        return Stack(
          key: _pageKey,
          children: <Widget>[
            Column(
              children: <Widget>[
                _buildToolbar(theme, planStore),
                _buildHeader(theme),
                Expanded(child: _buildGrid(theme, planStore)),
              ],
            ),

            // 拖拽浮层：跟随手指（拉伸时不显示，免得挡住要看的边缘）
            AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_dragPosition, _liftAnim]),
              builder: (context, _) {
                final position = _dragPosition.value;
                final kind = _dragKind;
                if (position == null || kind == null || kind.isResize) {
                  return const SizedBox.shrink();
                }
                final local = _toLocal(position);
                final pop = Curves.easeOutBack.transform(_liftAnim.value).clamp(0.6, 1.4);
                return Positioned(
                  left: local.dx - 75,
                  top: local.dy - 22,
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: pop,
                      child: DragPreviewCard(
                        title: _dragTitle ?? '',
                        category: _dragCategory ?? '通用',
                      ),
                    ),
                  ),
                );
              },
            ),

            // 「拖到这里取消排班」
            ValueListenableBuilder<({bool visible, bool hovered})>(
              valueListenable: _unscheduleBar,
              builder: (context, state, _) => state.visible
                  ? _buildUnscheduleBar(theme, state.hovered)
                  : const SizedBox.shrink(),
            ),

            // 待办清单面板
            AnimatedPositioned(
              key: _panelKey,
              // 与各弹层共用同一套动效参数（见 AppMotion）
              duration: AppMotion.sheet,
              curve: AppMotion.sheetCurve,
              left: 0,
              right: 0,
              height: panelHeight + media.padding.bottom,
              bottom: _todoPanelOpen ? 0 : -panelHeight - media.padding.bottom,
              child: TodoPanelView(
                todos: planStore.todos,
                draggingId: _draggingId,
                onClose: () => setState(() => _todoPanelOpen = false),
                onScheduleTodo: _quickSchedule,
                onRemoveTodo: (todo) => planStore.removeTodo(todo.id),
                onGoPlaza: () {
                  setState(() => _todoPanelOpen = false);
                  goToTab(AppTab.plaza);
                },
                onDragStart: (todo, position) => _beginDrag(
                  kind: DragKind.todo,
                  id: todo.id,
                  title: todo.title,
                  category: todo.category,
                  start: position,
                ),
                onDragUpdate: _onDragMove,
                onDragEnd: _endDrag,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(TThemeData theme, PlanStore planStore) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.bgColorContainer,
        border: Border(
          bottom: BorderSide(color: theme.componentStrokeColor, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          TButton(
            size: TButtonSize.extraSmall,
            variant: TButtonVariant.outline,
            colorScheme: TButtonColorScheme.defaultTheme,
            icon: const Icon(TIcons.location, size: 15),
            child: const Text('今天'),
            onPressed: _scrollToToday,
          ),
          const Spacer(),
          TButton(
            size: TButtonSize.extraSmall,
            variant: TButtonVariant.fill,
            colorScheme: TButtonColorScheme.primary,
            icon: const Icon(TIcons.queue, size: 16),
            child: Text('待办 ${planStore.todoCount}'),
            onPressed: () => setState(() => _todoPanelOpen = !_todoPanelOpen),
          ),
        ],
      ),
    );
  }

  /// 固定表头：日期列 + 可横向滚动的小时轴
  Widget _buildHeader(TThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.bgColorSecondaryContainer,
        border: Border(
          bottom: BorderSide(color: theme.componentStrokeColor, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: ScheduleMetrics.dateWidth,
            height: 34,
            child: Center(
              child: Text(
                '日期 / 时间',
                style: TextStyle(fontSize: 10, color: theme.textColorSecondary),
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: SizedBox(
                height: 34,
                child: Transform.translate(
                  offset: Offset(-_hOffset, 0),
                  child: Row(
                    children: kTimelineHours.map((hour) {
                      return SizedBox(
                        width: ScheduleMetrics.hourWidth,
                        child: Center(
                          child: Text(
                            formatHour(hour),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textColorSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(TThemeData theme, PlanStore planStore) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        children: <Widget>[
          ClipRect(
            child: ListView.builder(
              key: _gridKey,
              controller: _vController,
              padding: EdgeInsets.zero,
              itemCount: _days.length,
              itemBuilder: (context, index) => _buildRow(theme, _days[index]),
            ),
          ),
          _buildNowLine(theme),
        ],
      ),
    );
  }

  Widget _buildRow(TThemeData theme, String date) {
    final layout = _layoutFor(date);
    final today = isToday(date);
    final weekend = isWeekend(date);

    return SizedBox(
      height: layout.height,
      child: Row(
        children: <Widget>[
          _buildDateCell(theme, date, today),
          Expanded(
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(-_hOffset, 0),
                child: SizedBox(
                  width: ScheduleMetrics.contentWidth,
                  height: layout.height,
                  child: Stack(
                    children: <Widget>[
                      // 只有落点格子变化时才重建这一行的格子
                      ValueListenableBuilder<DropCell?>(
                        valueListenable: _dropCell,
                        builder: (context, cell, _) {
                          final active = cell?.date == date ? cell : null;
                          return Row(
                            children: kTimelineHours
                                .map((hour) =>
                                    _buildCell(theme, hour, today, weekend, active))
                                .toList(),
                          );
                        },
                      ),
                      ...layout.blocks.map(
                        (block) => PlanBlockView(
                          key: ValueKey<String>(block.plan.id),
                          block: block,
                          draggingId: _draggingId,
                          onTap: (plan) => showScheduleDetailSheet(context, plan.id),
                          onDragStart: (plan, kind, position) => _beginDrag(
                            kind: kind,
                            id: plan.id,
                            title: plan.title,
                            category: plan.category,
                            start: position,
                            fromStartHour: plan.startHour,
                            fromDuration: plan.duration,
                          ),
                          onDragUpdate: _onDragMove,
                          onDragEnd: _endDrag,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCell(TThemeData theme, String date, bool today) {
    return Container(
      width: ScheduleMetrics.dateWidth,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: today ? theme.brandLightColor : theme.bgColorContainer,
        border: Border(
          right: BorderSide(color: theme.componentStrokeColor, width: 0.5),
          bottom: BorderSide(color: theme.componentStrokeColor, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                weekdayShortCN(date),
                style: TextStyle(fontSize: 11, color: theme.textColorPlaceholder),
              ),
              if (today) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.brandNormalColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    '今天',
                    style: TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatMD(date),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(
    TThemeData theme,
    int hour,
    bool today,
    bool weekend,
    DropCell? active,
  ) {
    final isOver = active != null && active.containsHour(hour.toDouble());

    return GestureDetector(
      onTap: () => setState(() => _todoPanelOpen = true),
      child: Container(
        width: ScheduleMetrics.hourWidth,
        decoration: BoxDecoration(
          color: isOver
              ? theme.brandFocusColor
              : today
                  ? theme.brandLightColor
                  : weekend
                      ? theme.bgColorSecondaryContainer
                      : theme.bgColorContainer,
          border: Border(
            right: BorderSide(color: theme.componentStrokeColor, width: 0.5),
            bottom: BorderSide(color: theme.componentStrokeColor, width: 0.5),
          ),
        ),
        child: isOver
            ? Center(
                child: Text(
                  '排到这里',
                  style: TextStyle(fontSize: 10, color: theme.brandNormalColor),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildNowLine(TThemeData theme) {
    if (_nowHour < kFirstHour || _nowHour > kEndHour) return const SizedBox.shrink();

    final x = ScheduleMetrics.dateWidth +
        (_nowHour - kFirstHour) / kHoursCount * ScheduleMetrics.contentWidth -
        _hOffset;
    if (x < ScheduleMetrics.dateWidth ||
        x > ScheduleMetrics.dateWidth + _availableWidth) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: x,
      top: 0,
      bottom: 0,
      width: 2,
      child: IgnorePointer(child: Container(color: theme.errorNormalColor)),
    );
  }

  Offset _toLocal(Offset global) {
    final box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return box.globalToLocal(global);
  }

  Widget _buildUnscheduleBar(TThemeData theme, bool over) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Container(
          key: _unscheduleKey,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: over ? theme.errorLightColor : theme.bgColorContainer,
            borderRadius: BorderRadius.circular(theme.radiusLarge),
            border: Border.all(
              color: over ? theme.errorNormalColor : theme.componentBorderColor,
              width: over ? 1.5 : 0.5,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                TIcons.swap_right,
                size: 16,
                color: over ? theme.errorNormalColor : theme.textColorSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                over ? '松手退回待办清单' : '拖到这里取消排班',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: over ? FontWeight.w600 : FontWeight.w400,
                  color: over ? theme.errorNormalColor : theme.textColorSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
