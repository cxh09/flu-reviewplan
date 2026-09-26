import 'package:flutter/material.dart';

import 'app_ui.dart';

/// 拖拽浮起反馈：源卡片在被拖动时轻微放大 + 压暗。
///
/// 统一 [plan_block_view] 与 [plaza_panel_view] 两处原本各写一遍的
/// `AnimatedScale + AnimatedOpacity`，时长/曲线收口到 [AppMotion]。
/// [scale] 由调用方传入以保留计划块(1.04)与广场条目(1.02)的细微差异。
class DragFeedbackWrap extends StatelessWidget {
  const DragFeedbackWrap({
    super.key,
    required this.isDragging,
    required this.scale,
    required this.child,
  });

  final bool isDragging;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isDragging ? scale : 1,
      duration: AppMotion.dragLift,
      curve: AppMotion.dragLiftCurve,
      child: AnimatedOpacity(
        opacity: isDragging ? 0.35 : 1,
        duration: AppMotion.dragLift,
        child: child,
      ),
    );
  }
}
