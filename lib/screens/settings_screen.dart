import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/settings_service.dart';

/// 设置页面 — 下载路径管理
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  String _displayPath = '';
  bool _useCustomPath = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final path = await _settings.getDisplayPath();
    final custom = _settings.useCustomPath;
    if (mounted) {
      setState(() {
        _displayPath = path;
        _useCustomPath = custom;
        _loading = false;
      });
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载保存目录',
    );

    if (result != null) {
      await _settings.setDownloadPath(result);
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已设置下载目录: $result'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _resetToDefault() async {
    await _settings.resetToDefault();
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已恢复默认下载目录'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SettingsBgPainter(theme.colorScheme.primary),
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      const SizedBox(height: 8),

                      // 下载目录卡片
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          theme.colorScheme.primary,
                                          theme.colorScheme.primary.withOpacity(0.7),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.folder_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '下载目录',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 路径显示
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _useCustomPath
                                          ? Icons.folder_open_rounded
                                          : Icons.storage_rounded,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _displayPath.isNotEmpty
                                            ? _displayPath
                                            : '默认目录',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_useCustomPath)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 18,
                                        color: Colors.green,
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 按钮区
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: FilledButton.icon(
                                      onPressed: _pickFolder,
                                      icon: const Icon(Icons.create_new_folder_rounded,
                                          size: 20),
                                      label: const Text('选择目录'),
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_useCustomPath) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 44,
                                      child: OutlinedButton.icon(
                                        onPressed: _resetToDefault,
                                        icon: const Icon(Icons.restore_rounded,
                                            size: 18),
                                        label: const Text('恢复默认'),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          foregroundColor: theme.colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 说明
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 18, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  '说明',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '• 默认路径为应用内部存储目录\n'
                              '• 自定义目录可设置为 Download 文件夹\n'
                              '• 视频保存为 .mp4 格式\n'
                              '• 音频保存为 .mp3 格式（192kbps）',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsBgPainter extends CustomPainter {
  final Color color;
  _SettingsBgPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.03)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width, 0), size.width * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
