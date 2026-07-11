import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/video_info.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../widgets/platform_badge.dart';

/// 下载管理页面
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen>
    with SingleTickerProviderStateMixin {
  final HistoryService _historyService = HistoryService();
  final DownloadService _downloadService = DownloadService();
  List<VideoInfo> _downloadedVideos = [];

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _historyService.loadHistory();
    if (mounted) {
      setState(() {
        _downloadedVideos = _historyService.history
            .where((v) => v.downloadStatus == DownloadStatus.completed)
            .toList();
      });
      _animController.forward(from: 0);
    }
  }

  Future<void> _openVideo(VideoInfo videoInfo) async {
    if (videoInfo.localPath == null) return;

    final file = File(videoInfo.localPath!);
    if (!await file.exists()) {
      if (mounted) {
        _showSnackBar('视频文件已不存在');
        await _historyService.deleteRecord(videoInfo.noteId);
        _loadData();
      }
      return;
    }

    try {
      await OpenFilex.open(videoInfo.localPath!);
    } catch (e) {
      if (mounted) {
        _showSnackBar('无法打开文件: $e');
      }
    }
  }

  Future<void> _deleteVideo(VideoInfo videoInfo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('删除确认'),
        content: Text('确定要删除「${videoInfo.title}」吗？\n视频文件也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (videoInfo.localPath != null) {
        await _downloadService.deleteVideo(videoInfo.localPath!);
      }
      await _historyService.deleteRecord(videoInfo.noteId);
      _loadData();
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          '下载管理',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_downloadedVideos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空列表',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Stack(
        children: [
          // 背景装饰
          Positioned.fill(
            child: CustomPaint(
              painter: _DownloadBgPainter(theme.colorScheme.primary),
            ),
          ),
          SafeArea(
            child: _downloadedVideos.isEmpty
                ? _buildEmptyState(theme)
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: _downloadedVideos.length,
                      itemBuilder: (context, index) {
                        final video = _downloadedVideos[index];
                        return _buildDownloadItem(video, theme, index);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              Icons.download_outlined,
              size: 50,
              color: theme.colorScheme.onSurface.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '还没有下载视频',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '解析并下载视频后，会显示在这里',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text('返回首页'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadItem(
      VideoInfo videoInfo, ThemeData theme, int index) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final delay = index * 0.05;
        final animValue = CurvedAnimation(
          parent: _animController,
          curve: Interval(
            delay.clamp(0.0, 0.8),
            (delay + 0.15).clamp(0.0, 1.0),
            curve: Curves.easeOut,
          ),
        ).value;

        return Opacity(
          opacity: animValue,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - animValue)),
            child: child,
          ),
        );
      },
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openVideo(videoInfo),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // 缩略图
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: theme.colorScheme.surfaceVariant,
                    child: Stack(
                      children: [
                        if (videoInfo.coverUrl.isNotEmpty)
                          Image.network(
                            videoInfo.coverUrl,
                            fit: BoxFit.cover,
                            width: 72,
                            height: 72,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.video_file, color: Colors.grey),
                          )
                        else
                          const Icon(Icons.video_file, color: Colors.grey),
                        // 平台小标
                        Positioned(
                          top: 4,
                          left: 4,
                          child: PlatformBadge(
                            platform: videoInfo.platform,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        videoInfo.title.isNotEmpty
                            ? videoInfo.title
                            : '未命名视频',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 13,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.4)),
                          const SizedBox(width: 4),
                          Text(
                            videoInfo.author.isNotEmpty
                                ? videoInfo.author
                                : '未知作者',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.45),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle,
                                    size: 12, color: Colors.green),
                                SizedBox(width: 3),
                                Text(
                                  '已下载',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                          if (videoInfo.fileSize > 0) ...[
                            const SizedBox(width: 10),
                            Text(
                              videoInfo.formattedSize,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                          if (videoInfo.downloadTime != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              _formatDate(videoInfo.downloadTime!),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.3),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // 删除按钮
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.error.withOpacity(0.15),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        color: theme.colorScheme.error, size: 20),
                    onPressed: () => _deleteVideo(videoInfo),
                    tooltip: '删除',
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '刚刚';
      return '${diff.inHours}小时前';
    }
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('清空列表'),
        content: Text('确定要删除所有 ${_downloadedVideos.length} 个下载记录吗？\n（视频文件也会被删除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final video in _downloadedVideos) {
        if (video.localPath != null) {
          await _downloadService.deleteVideo(video.localPath!);
        }
      }
      await _historyService.saveHistory();
      _loadData();
    }
  }
}

/// 下载页背景装饰
class _DownloadBgPainter extends CustomPainter {
  final Color color;

  _DownloadBgPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width, 0),
      size.width * 0.5,
      paint..color = color.withOpacity(0.04),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
