import 'package:flutter/material.dart';
import '../models/video_info.dart';
import 'platform_badge.dart';

/// 视频信息卡片组件
class VideoCard extends StatelessWidget {
  final VideoInfo videoInfo;
  final VoidCallback? onDownload;
  final VoidCallback? onDownloadMp3;
  final VoidCallback? onTrim;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  const VideoCard({
    super.key,
    required this.videoInfo,
    this.onDownload,
    this.onDownloadMp3,
    this.onTrim,
    this.onOpen,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = videoInfo.downloadStatus == DownloadStatus.completed;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 封面图
          _buildCoverSection(theme, isCompleted),

          // 信息
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 平台 + 标题
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlatformBadge(
                      platform: videoInfo.platform,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            videoInfo.title.isNotEmpty
                                ? videoInfo.title
                                : '未命名视频',
                            style:
                                theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (videoInfo.author.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 15,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.4),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  videoInfo.author,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                                if (videoInfo.likes > 0) ...[
                                  const SizedBox(width: 14),
                                  Icon(
                                    Icons.favorite_border_rounded,
                                    size: 14,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatCount(videoInfo.likes),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 标签
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildTag(
                      theme,
                      icon: Icons.timer_outlined,
                      label: videoInfo.formattedDuration.isNotEmpty
                          ? videoInfo.formattedDuration
                          : '--:--',
                    ),
                    _buildTag(
                      theme,
                      icon: Icons.high_quality_rounded,
                      label: videoInfo.resolution.isNotEmpty
                          ? videoInfo.resolution
                          : '1080P',
                    ),
                    if (videoInfo.fileSize > 0)
                      _buildTag(
                        theme,
                        icon: Icons.storage_outlined,
                        label: videoInfo.formattedSize,
                      ),
                    if (onTrim != null)
                      GestureDetector(
                        onTap: onTrim,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              theme.colorScheme.primary.withOpacity(0.6),
                              theme.colorScheme.primary.withOpacity(0.4),
                            ]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.content_cut_rounded, size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('剪辑', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // 描述
                if (videoInfo.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    videoInfo.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 18),

                // 操作按钮
                Row(
                  children: [
                    if (!isCompleted) ...[
                      if (onDownload != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_rounded, size: 20),
                            label: const Text('下载视频'),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: videoInfo.platform.brandColor,
                            ),
                          ),
                        ),
                      if (onDownloadMp3 != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onDownloadMp3,
                            icon: const Icon(Icons.audio_file_rounded, size: 20),
                            label: const Text('下载 MP3'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      if (onOpen != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onOpen,
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('播放'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                              ),
                            ),
                          ),
                        ),
                      if (onOpen != null && onDelete != null)
                        const SizedBox(width: 10),
                      if (onDelete != null)
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.error.withOpacity(0.2),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: onDelete,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: theme.colorScheme.error,
                            ),
                            tooltip: '删除',
                          ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverSection(ThemeData theme, bool isCompleted) {
    return Stack(
      children: [
        // 封面
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant,
          ),
          child: videoInfo.coverUrl.isNotEmpty
              ? Image.network(
                  videoInfo.coverUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return _buildPlaceholder(theme);
                  },
                )
              : _buildPlaceholder(theme),
        ),

        // 渐变遮罩
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.15),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // 播放按钮
        Positioned.fill(
          child: Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),

        // 已下载标签
        if (isCompleted)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.shade600,
                    Colors.green.shade400,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    '已下载',
                    style:
                        TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

        // 时长
        if (videoInfo.formattedDuration.isNotEmpty)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    videoInfo.formattedDuration,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      height: 200,
      color: theme.colorScheme.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.video_library_rounded,
          size: 48,
          color: theme.colorScheme.onSurface.withOpacity(0.15),
        ),
      ),
    );
  }

  Widget _buildTag(ThemeData theme,
      {required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 10000) return count.toString();
    if (count < 1000000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
}
