import 'dart:developer' as developer;
import '../../models/video_info.dart';
import 'parser_base.dart';
import 'ytdlp_parser.dart';

/// 解析器管理器 — 仅使用 yt-dlp API
class ParserManager {
  static const String _tag = 'ParserManager';

  static final ParserManager _instance = ParserManager._internal();
  factory ParserManager() => _instance;
  ParserManager._internal();

  final YtDlpParser _parser = YtDlpParser();

  /// 解析视频链接
  Future<ParseResult> parse(String url, {String? cookie}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('请输入有效的网页链接');
    }

    try {
      developer.log('yt-dlp 解析: $url', name: _tag);
      final info = await _parser.parse(url, cookie: cookie);
      return ParseResult(platform: info.platform, videoInfo: info);
    } catch (e) {
      developer.log('yt-dlp 失败: $e', name: _tag);
      throw Exception('解析失败，请检查链接是否有效');
    }
  }

  /// 验证链接是否可解析
  bool isValidUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 检测平台
  VideoPlatform detectPlatform(String url) {
    if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) return VideoPlatform.xiaohongshu;
    if (url.contains('douyin.com') || url.contains('iesdouyin.com')) return VideoPlatform.douyin;
    if (url.contains('kuaishou.com')) return VideoPlatform.kuaishou;
    if (url.contains('bilibili.com') || url.contains('b23.tv')) return VideoPlatform.bilibili;
    if (url.contains('weibo.com')) return VideoPlatform.weibo;
    return VideoPlatform.unknown;
  }
}
