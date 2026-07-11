import 'dart:async';
import 'package:flutter/material.dart';
import '../models/video_info.dart';
import '../services/parsers/parser_manager.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../widgets/url_input_bar.dart';
import '../widgets/video_card.dart';
import '../widgets/platform_badge.dart';
import '../widgets/trim_dialog.dart';

/// 首页
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ParserManager _parserManager = ParserManager();
  final DownloadService _downloadService = DownloadService();
  final HistoryService _historyService = HistoryService();

  VideoInfo? _currentVideo;
  bool _isParsing = false;
  String? _errorMessage;
  StreamSubscription? _downloadSubscription;

  double _downloadProgress = 0;
  String _downloadStatusText = '';
  bool _isDownloading = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _loadHistory();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _downloadService.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _historyService.loadHistory();
  }

  /// 解析视频
  Future<void> _parseVideo(String url) async {
    if (!mounted) return;

    setState(() {
      _isParsing = true;
      _errorMessage = null;
      _currentVideo = null;
      _downloadProgress = 0;
      _downloadStatusText = '';
      _isDownloading = false;
    });

    try {
      if (!_parserManager.isValidUrl(url)) {
        throw Exception('不支持的链接格式\n\n'
            '目前支持以下平台：\n'
            '📕 小红书    xiaohongshu.com\n'
            '🎵 抖音      douyin.com\n'
            '📱 快手      kuaishou.com\n'
            '📺 B站      bilibili.com\n'
            '📰 微博      weibo.com');
      }

      final result = await _parserManager.parse(url);
      if (!mounted) return;

      setState(() {
        _currentVideo = result.videoInfo;
        _isParsing = false;
      });

      _animController.forward(from: 0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(result.platform.icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('解析成功: ${result.videoInfo.title}'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 下载视频
  Future<void> _downloadVideo(VideoInfo videoInfo) async {
    if (_isDownloading) return;

    // 显示剪辑对话框
    final trimResult = await TrimDialog.show(context, videoInfo.duration);

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatusText = '准备下载...';
    });

    await _historyService.addRecord(videoInfo);

    final int trimStart = trimResult != null ? trimResult[0] : 0;
    final int trimEnd = trimResult != null ? trimResult[1] : 0;

    final stream = _downloadService.downloadVideo(
      videoInfo,
      trimStart: trimStart,
      trimEnd: trimEnd,
    );

    _downloadSubscription = stream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress.percentage;
          _downloadStatusText =
              '${progress.formattedReceived} / ${progress.formattedTotal} · ${progress.formattedSpeed}';
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
        _historyService.updateRecord(videoInfo);
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1.0;
          _downloadStatusText = '下载完成 ✓';
        });
        _historyService.updateRecord(videoInfo);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('视频下载完成！'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: '查看',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/downloads');
              },
            ),
          ),
        );
      },
    );
  }

  /// 下载 MP3
  Future<void> _downloadMp3(VideoInfo videoInfo) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatusText = '准备下载...';
    });

    await _historyService.addRecord(videoInfo);

    final stream = _downloadService.downloadVideo(videoInfo, format: DownloadFormat.mp3);

    _downloadSubscription = stream.listen(
      (progress) {
        if (!mounted) return;
        final stageText = progress.stage == DownloadStage.converting
            ? '正在处理...'
            : '${progress.formattedReceived} / ${progress.formattedTotal} · ${progress.formattedSpeed}';
        setState(() {
          _downloadProgress = progress.percentage;
          _downloadStatusText = stageText;
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
        _historyService.updateRecord(videoInfo);
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1.0;
          _downloadStatusText = '下载完成 ✓';
        });
        _historyService.updateRecord(videoInfo);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('MP3 下载完成！'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: '查看',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/downloads');
              },
            ),
          ),
        );
      },
    );
  }

  void _cancelDownload() {
    if (_currentVideo != null) {
      _downloadService.cancelDownload(_currentVideo!.noteId);
      _downloadSubscription?.cancel();
      setState(() {
        _isDownloading = false;
        _downloadStatusText = '已取消';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          '六月妈妈视频解析',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载管理',
            onPressed: () => Navigator.pushNamed(context, '/downloads'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 背景渐变
          Positioned.fill(
            child: CustomPaint(
              painter: _BackgroundPainter(theme.colorScheme.primary),
            ),
          ),

          // 主内容
          SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 头部
                  _buildHeader(theme),

                  const SizedBox(height: 24),

                  // URL 输入
                  UrlInputBar(
                    onParse: _parseVideo,
                    isParsing: _isParsing,
                  ),

                  const SizedBox(height: 24),

                  // 解析中
                  if (_isParsing) _buildLoadingIndicator(theme),

                  // 错误
                  if (_errorMessage != null) _buildErrorCard(theme),

                  // 结果
                  if (_currentVideo != null && !_isParsing)
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          children: [
                            if (_isDownloading)
                              _buildDownloadProgress(theme),
                            VideoCard(
                              videoInfo: _currentVideo!,
                              onDownload: () =>
                                  _downloadVideo(_currentVideo!),
                              onDownloadMp3: () =>
                                  _downloadMp3(_currentVideo!),
                              onTrim: () =>
                                  _downloadVideo(_currentVideo!),
                              onOpen: _currentVideo!.localPath != null
                                  ? () {}
                                  : null,
                              onDelete: () => _deleteVideo(_currentVideo!),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_currentVideo == null && !_isParsing && _errorMessage == null)
                    _buildPlatformGuide(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.download_for_offline_outlined,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '多平台视频解析',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '专门给明琛翊妈妈做的小工具——by明琛翊爸爸',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.4),
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(40),
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
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '正在解析视频信息...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请稍候，正在获取视频数据',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.error.withOpacity(0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '解析失败',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _errorMessage = null),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('关闭', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                        color: theme.colorScheme.error.withOpacity(0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withOpacity(0.6),
            theme.colorScheme.primaryContainer.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '正在下载',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                _downloadStatusText,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _cancelDownload,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformGuide(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
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
              Icon(Icons.lightbulb_outline_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '支持平台',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPlatformRow(
              theme, VideoPlatform.xiaohongshu, 'xiaohongshu.com / xhslink.com'),
          _buildPlatformRow(
              theme, VideoPlatform.douyin, 'douyin.com / iesdouyin.com'),
          _buildPlatformRow(
              theme, VideoPlatform.kuaishou, 'kuaishou.com'),
          _buildPlatformRow(
              theme, VideoPlatform.bilibili, 'bilibili.com / b23.tv'),
          _buildPlatformRow(
              theme, VideoPlatform.weibo, 'weibo.com'),
        ],
      ),
    );
  }

  Widget _buildPlatformRow(
      ThemeData theme, VideoPlatform platform, String domains) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          PlatformBadge(platform: platform, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
                Text(
                  domains,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteVideo(VideoInfo videoInfo) async {
    if (videoInfo.localPath != null) {
      await _downloadService.deleteVideo(videoInfo.localPath!);
    }
    await _historyService.deleteRecord(videoInfo.noteId);
    if (mounted) {
      setState(() => _currentVideo = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已删除'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}

/// 背景装饰
class _BackgroundPainter extends CustomPainter {
  final Color color;

  _BackgroundPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    // 左上角装饰圆
    canvas.drawCircle(
      Offset(0, 0),
      size.width * 0.6,
      paint..color = color.withOpacity(0.04),
    );

    // 右下角装饰
    final paint2 = Paint()
      ..color = color.withOpacity(0.03)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width, size.height),
      size.width * 0.5,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
