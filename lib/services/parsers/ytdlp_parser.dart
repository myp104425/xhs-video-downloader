import 'dart:developer' as developer;
import 'package:extractor/extractor.dart' as yt;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// yt-dlp 原生解析器 — 使用 youtubedl-android（yt-dlp 编译进 APK）
///
/// 无需外部 API，不依赖网络服务，覆盖 1000+ 网站。
/// yt-dlp 社区活跃，平台结构变更后自动适配更新。
class YtDlpParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'YtDlpParser';

  static yt.YoutubeDLFlutter? _instance;
  static bool _initialized = false;

  /// 初始化 extractor（首次调用时自动执行）
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _instance = yt.YoutubeDLFlutter.instance;
    await _instance!.initialize(enableFFmpeg: false);
    _initialized = true;
    developer.log('extractor 初始化完成', name: _tag);
  }

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('yt-dlp 解析: $url', name: _tag);

    try {
      await ensureInitialized();

      // 用 yt-dlp 获取视频信息
      final info = await _instance!.getVideoInfo(url);

      // 提取视频直链（取最佳画质）
      String? videoUrl;
      String? title = info.title;
      String? author = info.uploader;
      String? coverUrl = info.thumbnail;
      final noteId = info.id ?? DateTime.now().millisecondsSinceEpoch.toString();
      final duration = info.duration ?? 0;

      // 从 formats 中找最佳视频 URL
      final formats = info.formats;
      if (formats != null && formats.isNotEmpty) {
        // 优先找带视频+音频的格式
        for (final fmt in formats) {
          if (fmt == null) continue;
          if (fmt.url != null && fmt.url!.isNotEmpty) {
            final hasVideo = fmt.vcodec != null && fmt.vcodec != 'none';
            final hasAudio = fmt.acodec != null && fmt.acodec != 'none';
            if (hasVideo && hasAudio) {
              videoUrl = fmt.url;
              developer.log('选取格式: ${fmt.formatId} ${fmt.resolution} ${fmt.ext}', name: _tag);
              break;
            }
          }
        }
        // 如果没找到，取第一个有 URL 的格式
        if (videoUrl == null) {
          for (final fmt in formats) {
            if (fmt == null) continue;
            if (fmt.url != null && fmt.url!.isNotEmpty) {
              videoUrl = fmt.url;
              break;
            }
          }
        }
      }

      // 兜底：用 info.url（可能是原页面地址）
      videoUrl ??= info.url;

      if (videoUrl == null || videoUrl.isEmpty) {
        throw Exception('未找到可下载的视频地址');
      }

      return VideoInfo(
        noteId: noteId,
        title: title ?? '',
        author: author ?? '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl,
        sourceUrl: url,
        duration: duration,
        platform: VideoPlatform.unknown,
      );
    } catch (e) {
      developer.log('yt-dlp 解析失败: $e', name: _tag);
      if (e is Exception) rethrow;
      throw Exception('解析失败: $e');
    }
  }
}
