import 'dart:developer' as developer;
import '../../models/video_info.dart';
import 'parser_base.dart';
import 'xiaohongshu_parser.dart';
import 'douyin_parser.dart';
import 'kuaishou_parser.dart';
import 'bilibili_parser.dart';
import 'weibo_parser.dart';

/// 解析器管理器 — 自动检测平台并路由到对应的解析器
class ParserManager {
  static const String _tag = 'ParserManager';

  static final ParserManager _instance = ParserManager._internal();
  factory ParserManager() => _instance;
  ParserManager._internal();

  /// 所有注册的解析器
  late final List<VideoParser> _parsers = [
    XiaohongshuParser(),
    DouyinParser(),
    KuaishouParser(),
    BilibiliParser(),
    WeiboParser(),
  ];

  /// 检测 URL 对应的平台
  VideoPlatform detectPlatform(String url) {
    for (final parser in _parsers) {
      if (parser.canParse(url)) {
        return parser.platform;
      }
    }
    return VideoPlatform.unknown;
  }

  /// 获取能解析此 URL 的解析器
  VideoParser? findParser(String url) {
    for (final parser in _parsers) {
      if (parser.canParse(url)) {
        return parser;
      }
    }
    return null;
  }

  /// 解析视频链接（自动检测平台）
  Future<ParseResult> parse(String url, {String? cookie}) async {
    final parser = findParser(url);
    if (parser == null) {
      throw Exception('不支持的链接格式\n\n'
          '目前支持以下平台：\n'
          '📕 小红书    xiaohongshu.com / xhslink.com\n'
          '🎵 抖音 / TikTok    douyin.com\n'
          '📱 快手    kuaishou.com\n'
          '📺 B站    bilibili.com\n'
          '📰 微博    weibo.com\n\n'
          '请粘贴以上平台的分享链接');
    }

    developer.log('检测到平台: ${parser.platform.displayName}', name: _tag);

    final videoInfo = await parser.parse(url, cookie: cookie);
    return ParseResult(platform: parser.platform, videoInfo: videoInfo);
  }

  /// 验证是否为支持的链接
  bool isValidUrl(String url) {
    return findParser(url) != null;
  }
}
