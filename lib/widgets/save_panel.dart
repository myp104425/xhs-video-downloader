import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../models/video_info.dart';
import '../services/settings_service.dart';
import '../services/history_service.dart';

/// 保存面板 — 下载完成后显示：试听+剪辑+重命名+保存
class SavePanel extends StatefulWidget {
  final VideoInfo videoInfo;
  final String filePath;

  const SavePanel({
    super.key,
    required this.videoInfo,
    required this.filePath,
  });

  @override
  State<SavePanel> createState() => _SavePanelState();
}

class _SavePanelState extends State<SavePanel> {
  late TextEditingController _nameCtrl;
  bool _isMp3 = false;

  // 剪辑
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  int _durationSec = 0;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _defaultName);
    _startCtrl = TextEditingController(text: '00:00');
    _endCtrl = TextEditingController(text: '');
    // 尝试用 ffprobe 获取时长
    _detectDuration();
  }

  String get _defaultName {
    var name = widget.videoInfo.title;
    if (name.isEmpty) name = '视频文件';
    // 清理非法字符
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.length > 100) name = name.substring(0, 100);
    return name;
  }

  Future<void> _detectDuration() async {
    if (!File(widget.filePath).existsSync()) return;
    try {
      // 用 FFmpeg probe 获取时长
      final cmd = '-i "${widget.filePath}" 2>&1';
      final session = await FFmpegKit.execute(cmd);
      final output = (await session.getOutput()) ?? '';
      final match = RegExp(r'Duration: (\d+):(\d+):(\d+)\.\d+').firstMatch(output);
      if (match != null) {
        final h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final s = int.parse(match.group(3)!);
        _durationSec = h * 3600 + m * 60 + s;
        if (mounted) {
          setState(() {
            _endCtrl.text = _fmtDuration(_durationSec);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  String _fmtDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// FFmpeg 用的时长格式（秒，不带 HH:）
  String _fmtDurationTrim(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  int _parseTime(String str) {
    final parts = str.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    }
    return 0;
  }

  /// 保存的路径（供 SnackBar 打开使用）
  String? _lastSavedPath;

  Future<void> _play() async {
    final path = _lastSavedPath ?? widget.filePath;
    if (!File(path).existsSync()) return;
    try {
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final fileName = _nameCtrl.text.trim();
      if (fileName.isEmpty) {
        throw Exception('请输入文件名');
      }

      final ext = _isMp3 ? '.mp3' : '.mp4';
      final defaultName = '$fileName$ext';

      // ★ 直接使用 SettingsService 的下载目录（无需用户选择）
      final settings = SettingsService();
      final saveDir = await settings.getDownloadDirectory();

      // 确保目录存在
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final savePath = '${saveDir.path}/$defaultName';
      final startSec = _parseTime(_startCtrl.text);
      final endSec = _parseTime(_endCtrl.text);
      final needsTrim = (startSec > 0 || (endSec > 0 && endSec < _durationSec));

      if (_isMp3 || needsTrim) {
        // ★ FFmpeg 输出到临时目录（总是可写）
        final tempDir = await getTemporaryDirectory();
        final tempExt = _isMp3 ? '.mp3' : '.mp4';
        final tempFilePath = '${tempDir.path}/save_temp_${DateTime.now().millisecondsSinceEpoch}$tempExt';

        final cmdBuf = StringBuffer();
        cmdBuf.write('-i "${widget.filePath}"');
        // -ss 放在 -i 后面（精准 seek）+ copyts
        if (startSec > 0) cmdBuf.write(' -ss ${_fmtDurationTrim(startSec)}');
        if (endSec > 0 && endSec > startSec) {
          final dur = endSec - startSec;
          cmdBuf.write(' -t ${_fmtDurationTrim(dur)}');
        }
        if (_isMp3) {
          cmdBuf.write(' -vn -acodec libmp3lame -ab 192k');
        } else {
          cmdBuf.write(' -c copy -avoid_negative_ts make_zero');
        }
        cmdBuf.write(' -y "$tempFilePath"');

        developer.log('FFmpeg save: ${cmdBuf.toString()}', name: 'SavePanel');

        bool ok = false;
        final session = await FFmpegKit.execute(cmdBuf.toString());
        if (ReturnCode.isSuccess(await session.getReturnCode())) {
          ok = true;
        } else {
          // 降级：最简命令
          final simple = '-i "${widget.filePath}"${_isMp3 ? ' -vn -acodec libmp3lame' : ''} -y "$tempFilePath"';
          final fbSession = await FFmpegKit.execute(simple);
          if (ReturnCode.isSuccess(await fbSession.getReturnCode())) ok = true;
        }

        if (!ok) throw Exception('处理失败');
        if (!await File(tempFilePath).exists()) throw Exception('临时文件未生成');

        // ★ 临时文件 → 目标路径（都在 app 可控目录内，不会权限失败）
        await File(tempFilePath).copy(savePath);
        try { await File(tempFilePath).delete(); } catch (_) {}
      } else {
        // 不剪辑、不转MP3 → 直接复制（app 可控目录）
        await File(widget.filePath).copy(savePath);
      }

      if (mounted) {
        // ★ 记录最后保存的路径，供播放按钮使用
        _lastSavedPath = savePath;

        // ★ 更新 videoInfo.localPath 指向保存的文件（供下载管理使用）
        widget.videoInfo.localPath = savePath;
        widget.videoInfo.downloadTime = DateTime.now();
        // 持久化到历史记录
        final history = HistoryService();
        history.updateRecord(widget.videoInfo);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到: ${saveDir.path}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '打开',
              onPressed: () {
                try {
                  OpenFilex.open(savePath);
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(widget.filePath);
    final fileSize = file.existsSync() ? file.lengthSync() : 0;
    final sizeStr = fileSize > 1024 * 1024
        ? '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(fileSize / 1024).toStringAsFixed(1)} KB';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ——— 标题区域 ———
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('下载完成', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      Text(sizeStr, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                ),
                // 播放按钮
                FilledButton.icon(
                  onPressed: _play,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('试听/预览'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ——— 文件名 + 格式 ———
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: '文件名',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                // 格式切换
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _formatBtn('MP4', false),
                      _formatBtn('MP3', true),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ——— 剪辑 ———
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.content_cut_rounded, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('MM:SS 剪辑', style: TextStyle(fontSize: 13)),
                const Spacer(),
                SizedBox(
                  width: 70, height: 36,
                  child: TextField(
                    controller: _startCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [LengthLimitingTextInputFormatter(5)],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: EdgeInsets.zero,
                      hintText: 'MM:SS',
                      hintStyle: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                    ),
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                    onChanged: (v) {
                      // 自动补全冒号
                      final digits = v.replaceAll(RegExp(r'[^\d]'), '');
                      if (digits.length >= 2) {
                        final m = digits.substring(0, 2);
                        final s = digits.length > 2 ? digits.substring(2, digits.length.clamp(2, 4)) : '';
                        _startCtrl.text = s.isNotEmpty ? '$m:$s' : m;
                        _startCtrl.selection = TextSelection.collapsed(offset: _startCtrl.text.length);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                ),
                SizedBox(
                  width: 70, height: 36,
                  child: TextField(
                    controller: _endCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [LengthLimitingTextInputFormatter(5)],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: EdgeInsets.zero,
                      hintText: 'MM:SS',
                      hintStyle: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                    ),
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                    onChanged: (v) {
                      final digits = v.replaceAll(RegExp(r'[^\d]'), '');
                      if (digits.length >= 2) {
                        final m = digits.substring(0, 2);
                        final s = digits.length > 2 ? digits.substring(2, digits.length.clamp(2, 4)) : '';
                        _endCtrl.text = s.isNotEmpty ? '$m:$s' : m;
                        _endCtrl.selection = TextSelection.collapsed(offset: _endCtrl.text.length);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ——— 保存按钮 ———
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(_saving ? '保存中...' : '保存到本地'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  backgroundColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatBtn(String label, bool isMp3) {
    final selected = _isMp3 == isMp3;
    return GestureDetector(
      onTap: () => setState(() => _isMp3 = isMp3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(selected ? 8 : 0),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}
