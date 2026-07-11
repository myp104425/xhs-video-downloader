import 'dart:developer' as developer;
import '../../models/video_info.dart';
import 'parser_base.dart';
import 'generic_parser.dart';
import 'ytdlp_parser.dart';
import 'bilibili_parser.dart';
import 'douyin_parser.dart';
import 'xiaohongshu_parser.dart';
import 'kuaishou_parser.dart';
import 'weibo_parser.dart';

/// 解析器管理器 — 多层兜底策略
///
/// 解析顺序：
/// 1. 平台专用解析器（B站/抖音/小红书/快手/微博）
/// 2. VDH 通用嗅探器（扫 HTML 找视频源）
/// 3. yt-dlp API 兜底（通过公开 REST API）
class ParserManager {
  static const String _tag = 'ParserManager';

  static final ParserManager _instance = ParserManager._internal();
  factory ParserManager() => _instance;
  ParserManager._internal();

  final List<VideoParser> _platformParsers = [
    XiaohongshuParser(),
    DouyinParser(),
    BilibiliParser(),
    KuaishouParser(),
    WeiboParser(),
  ];

  final GenericParser _genericParser = GenericParser();
  final YtDlpParser _ytdlpParser = YtDlpParser();

  /// 解析视频链接（逐层兜底）
  Future<ParseResult> parse(String url, {String? cookie}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('请输入有效的网页链接');
    }

    final List<String> errors = [];

    // 第1层：平台专用解析器
    for (final parser in _platformParsers) {
      if (parser.canParse(url)) {
        try {
          developer.log('尝试 ${parser.platform.displayName} 解析器', name: _tag);
          final info = await parser.parse(url, cookie: cookie);
          if (info.videoUrl.isNotEmpty) {
            return ParseResult(platform: parser.platform, videoInfo: info);
          }
        } catch (e) {
          errors.add('${parser.platform.displayName}: $e');
          developer.log('${parser.platform.displayName} 解析失败: $e', name: _tag);
        }
      }
    }

    // 第2层：VDH 通用嗅探器
    try {
      developer.log('尝试 VDH 通用嗅探', name: _tag);
      final info = await _genericParser.parse(url, cookie: cookie);
      if (info.videoUrl.isNotEmpty) {
        return ParseResult(platform: info.platform, videoInfo: info);
      }
    } catch (e) {
      errors.add('VDH嗅探: $e');
      developer.log('VDH嗅探失败: $e', name: _tag);
    }

    // 第3层：yt-dlp API 兜底
    try {
      developer.log('尝试 yt-dlp API 兜底', name: _tag);
      final info = await _ytdlpParser.parse(url, cookie: cookie);
      if (info.videoUrl.isNotEmpty) {
        return ParseResult(platform: info.platform, videoInfo: info);
      }
    } catch (e) {
      errors.add('yt-dlp: $e');
      developer.log('yt-dlp 失败: $e', name: _tag);
    }

    throw Exception('所有解析方式均失败\n'
        '已尝试：\n${errors.map((e) => '• $e').join('\n')}');
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
