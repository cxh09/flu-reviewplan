import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/plan_data.dart';
import '../data/plaza_data.dart';
import '../models/plan.dart';
import '../services/api_client.dart';
import '../stores/connection.dart';
import '../stores/plan_store.dart';
import '../stores/sync_store.dart';
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
  late final TextEditingController _doneNoteController;

  /// 当前正在上传的类型：image | file | ''，用于按钮文案
  String _uploading = '';

  /// 单文件上限与服务端一致（15MB）
  static const int _maxUploadBytes = 15 * 1024 * 1024;

  /// 预览图目标体积：1MB，展示默认用预览版，查看原图才加载 url
  static const int _previewMaxBytes = 1024 * 1024;

  /// 服务端允许直传的图片 mime（原图命中这些类型才保留）
  static const Set<String> _imageMimes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  /// 附件扩展名 → mime，需与服务端白名单对齐
  static const Map<String, String> _extMime = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'zip': 'application/zip',
  };

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
    _doneNoteController = TextEditingController(text: plan.doneNote);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _noteController.dispose();
    _doneNoteController.dispose();
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

  // ---------- 完成详情：图片 / 附件上传、删除与查看 ----------

  /// 上传件存的是相对路径，展示 / 打开时拼上服务端地址
  String _absUrl(String path) => '${context.read<SyncStore>().normalizedUrl}$path';

  /// 把原图压到 ≤1MB 的预览版 JPEG：分辨率与质量逐档下调，取第一个达标档位
  Uint8List? _compressPreview(Uint8List bytes) {
    final imglib.Image? decoded = imglib.decodeImage(bytes);
    if (decoded == null) return null;
    const List<(int, int)> stages = <(int, int)>[
      (1920, 85),
      (1600, 75),
      (1280, 70),
      (1024, 60),
      (800, 50),
    ];
    Uint8List? fallback;
    final int maxEdge =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    for (final (int edge, int quality) in stages) {
      final double scale = edge / maxEdge;
      final imglib.Image target = scale < 1
          ? imglib.copyResize(
              decoded,
              width: (decoded.width * scale).round().clamp(1, 4096),
              height: (decoded.height * scale).round().clamp(1, 4096),
            )
          : decoded;
      final Uint8List encoded = imglib.encodeJpg(target, quality: quality);
      fallback ??= encoded;
      if (encoded.length <= _previewMaxBytes) return encoded;
    }
    // 极端高熵图片兜底：用首档结果，至少比原图小
    return fallback;
  }

  Future<void> _pickDoneImages(Plan plan) async {
    final sync = context.read<SyncStore>();
    if (!sync.configured) {
      showWarningToast('请先配置服务端地址');
      return;
    }
    final List<XFile> files;
    try {
      // 不带压缩参数拿原图：原图要保留，预览版由 _compressPreview 生成
      files = await ImagePicker().pickMultiImage();
    } catch (_) {
      showErrorToast('无法打开相册');
      return;
    }
    if (files.isEmpty || !mounted) return;
    if (plan.doneImages.length + files.length > 9) {
      showWarningToast('最多 9 张图片');
      return;
    }

    setState(() => _uploading = 'image');
    final refs = List<Map<String, dynamic>>.from(
      plan.doneImages.map((item) => Map<String, dynamic>.from(item)),
    );
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final mime = file.mimeType ??
            _extMime[(file.name.split('.').last).toLowerCase()] ??
            'image/jpeg';
        final supported = _imageMimes.contains(mime);

        // ≤1MB 且类型受支持：原图本身就是预览版，只传一份
        if (bytes.length <= _previewMaxBytes && supported) {
          final res = await ApiClient.uploadFile(
            sync.normalizedUrl,
            sync.accessToken,
            name: file.name,
            mime: mime,
            base64Data: base64Encode(bytes),
          );
          final url = '${res?['url'] ?? ''}';
          if (url.isNotEmpty) {
            refs.add(<String, dynamic>{'name': file.name, 'url': url});
          }
          continue;
        }

        final previewBytes = _compressPreview(bytes);
        if (previewBytes == null) {
          showErrorToast('「${file.name}」压缩失败');
          continue;
        }
        // 原图在支持范围内且 ≤15MB 才保留；失败退回只存预览版
        String originalUrl = '';
        if (supported && bytes.length <= _maxUploadBytes) {
          try {
            final res = await ApiClient.uploadFile(
              sync.normalizedUrl,
              sync.accessToken,
              name: file.name,
              mime: mime,
              base64Data: base64Encode(bytes),
            );
            originalUrl = '${res?['url'] ?? ''}';
          } on ApiException catch (_) {
            originalUrl = '';
          }
        }
        final previewRes = await ApiClient.uploadFile(
          sync.normalizedUrl,
          sync.accessToken,
          name: file.name,
          mime: 'image/jpeg',
          base64Data: base64Encode(previewBytes),
        );
        final previewUrl = '${previewRes?['url'] ?? ''}';
        if (previewUrl.isEmpty) continue;
        final entry = <String, dynamic>{
          'name': file.name,
          'url': originalUrl.isNotEmpty ? originalUrl : previewUrl,
        };
        if (originalUrl.isNotEmpty && originalUrl != previewUrl) {
          entry['preview'] = previewUrl;
        }
        refs.add(entry);
      }
      if (!mounted) return;
      context.read<PlanStore>().updatePlan(plan.id, doneImages: refs);
      if (isOnline) showSuccessToast('图片已上传');
    } on ApiException catch (err) {
      showErrorToast(err.message);
    } catch (_) {
      showErrorToast('图片上传失败');
    } finally {
      if (mounted) setState(() => _uploading = '');
    }
  }

  Future<void> _pickDoneFiles(Plan plan) async {
    final sync = context.read<SyncStore>();
    if (!sync.configured) {
      showWarningToast('请先配置服务端地址');
      return;
    }
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    } catch (_) {
      showErrorToast('无法打开文件选择');
      return;
    }
    if (result == null || !mounted) return;
    if (plan.doneFiles.length + result.files.length > 9) {
      showWarningToast('最多 9 个附件');
      return;
    }

    setState(() => _uploading = 'file');
    final refs = List<Map<String, dynamic>>.from(plan.doneFiles);
    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) {
          showErrorToast('「${file.name}」读取失败');
          continue;
        }
        if (bytes.lengthInBytes > _maxUploadBytes) {
          showErrorToast('「${file.name}」超过 15MB 上限');
          continue;
        }
        final mime = _extMime[file.extension?.toLowerCase() ?? ''];
        if (mime == null) {
          showErrorToast('「${file.name}」类型不支持');
          continue;
        }
        final res = await ApiClient.uploadFile(
          sync.normalizedUrl,
          sync.accessToken,
          name: file.name,
          mime: mime,
          base64Data: base64Encode(bytes),
        );
        final url = '${res?['url'] ?? ''}';
        if (url.isNotEmpty) {
          refs.add(<String, dynamic>{'name': file.name, 'url': url});
        }
      }
      if (!mounted) return;
      context.read<PlanStore>().updatePlan(plan.id, doneFiles: refs);
      if (isOnline) showSuccessToast('附件已上传');
    } on ApiException catch (err) {
      showErrorToast(err.message);
    } catch (_) {
      showErrorToast('附件上传失败');
    } finally {
      if (mounted) setState(() => _uploading = '');
    }
  }

  void _removeDoneImage(Plan plan, int index) {
    final refs = List<Map<String, dynamic>>.from(plan.doneImages)..removeAt(index);
    context.read<PlanStore>().updatePlan(plan.id, doneImages: refs);
  }

  void _removeDoneFile(Plan plan, int index) {
    final refs = List<Map<String, dynamic>>.from(plan.doneFiles)..removeAt(index);
    context.read<PlanStore>().updatePlan(plan.id, doneFiles: refs);
  }

  Future<void> _openDoneFile(String url) async {
    final uri = Uri.tryParse(_absUrl(url));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 全屏预览完成详情图片：默认看 ≤1MB 压缩版，点「查看原图」才加载原图；点背景关闭
  Future<void> _showDoneImage(Map<String, dynamic> ref) {
    final original = '${ref['url'] ?? ''}';
    final preview = '${ref['preview'] ?? ''}';
    final canToggle = preview.isNotEmpty && preview != original;
    final showOriginal = ValueNotifier<bool>(false);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: showOriginal,
                  builder: (context, useOriginal, _) {
                    final url = useOriginal || preview.isEmpty ? original : preview;
                    return InteractiveViewer(
                      child: Image.network(
                        _absUrl(url),
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : const Center(
                              child: TLoading(size: TLoadingSize.medium),
                            ),
                      ),
                    );
                  },
                ),
              ),
              if (canToggle)
                Positioned(
                  top: MediaQuery.of(dialogContext).padding.top + 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: showOriginal,
                      builder: (context, useOriginal, _) => GestureDetector(
                        onTap: () => showOriginal.value = !useOriginal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            useOriginal ? '返回预览' : '查看原图',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ).whenComplete(showOriginal.dispose);
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
              if (isOnline) showSuccessToast('日程已删除');
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
          // ---------- 完成详情：仅标记完成后展示录入入口 ----------
          if (plan.done) ...<Widget>[
            AppFormField(
              label: '完成详情',
              tip: '说明完成情况，可添加图片 / 附件；分享页可查看',
              child: TTextarea(
                controller: _doneNoteController,
                hintText: '选填',
                minLines: 2,
                maxLines: 4,
                onChanged: (value) => planStore.updatePlan(widget.planId, doneNote: value),
              ),
            ),
            if (plan.doneImages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final entry in plan.doneImages.indexed)
                      GestureDetector(
                        onTap: () => _showDoneImage(
                          Map<String, dynamic>.from(entry.$2),
                        ),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: Stack(
                            children: <Widget>[
                              Container(
                                width: 72,
                                height: 72,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(theme.radiusDefault),
                                  border: Border.all(
                                    color: theme.componentStrokeColor,
                                    width: 0.5,
                                  ),
                                  image: DecorationImage(
                                    image: NetworkImage(
                                      _absUrl(
                                        '${entry.$2['preview'] ?? entry.$2['url'] ?? ''}',
                                      ),
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _removeDoneImage(plan, entry.$1),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.only(
                                        topRight: Radius.circular(6),
                                        bottomLeft: Radius.circular(6),
                                      ),
                                    ),
                                    child: const Icon(
                                      TIcons.close,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (plan.doneFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  children: <Widget>[
                    for (final entry in plan.doneFiles.indexed)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.bgColorSecondaryContainer,
                          borderRadius: BorderRadius.circular(theme.radiusDefault),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(TIcons.link, size: 14, color: theme.brandNormalColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _openDoneFile('${entry.$2['url'] ?? ''}'),
                                child: Text(
                                  '${entry.$2['name'] ?? entry.$2['url']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.brandNormalColor,
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _removeDoneFile(plan, entry.$1),
                              child: Icon(
                                TIcons.close,
                                size: 15,
                                color: theme.textColorPlaceholder,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.primary,
                    icon: const Icon(TIcons.image, size: 15),
                    child: Text(_uploading == 'image' ? '上传中…' : '添加图片'),
                    onPressed: _uploading.isEmpty ? () => _pickDoneImages(plan) : null,
                  ),
                  const SizedBox(width: 10),
                  TButton(
                    size: TButtonSize.small,
                    variant: TButtonVariant.outline,
                    colorScheme: TButtonColorScheme.defaultTheme,
                    icon: const Icon(TIcons.add, size: 15),
                    child: Text(_uploading == 'file' ? '上传中…' : '添加附件'),
                    onPressed: _uploading.isEmpty ? () => _pickDoneFiles(plan) : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
