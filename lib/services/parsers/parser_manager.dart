import 'dart:developer' as developer;
import '../../models/video_info.dart';
import 'parser_base.dart';
import 'generic_parser.dart';

/// 解析器管理器 — VDH 风格嗅探
///
/// 核心思路：不依赖平台 API（总是会过时），而是用页面嗅探 + Content-Type 验证。
/// 所有 URL 都先尝试通用嗅探，平台特定的只是 URL 格式提示。
class ParserManager {
  static const String _tag = 'ParserManager';

  static final ParserManager _instance = ParserManager._internal();
  factory ParserManager() => _instance;
  ParserManager._internal();

  final GenericParser _genericParser = GenericParser();

  /// 解析视频链接（VDH 通用嗅探）
  Future<ParseResult> parse(String url, {String? cookie}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('请输入有效的网页链接（以 http:// 或 https:// 开头）');
    }

    developer.log('VDH嗅探: $url', name: _tag);

    try {
      final videoInfo = await _genericParser.parse(url, cookie: cookie);
      return ParseResult(platform: videoInfo.platform, videoInfo: videoInfo);
    } catch (e) {
      developer.log('嗅探失败: $e', name: _tag);
      rethrow;
    }
  }

  /// 验证链接是否可解析
  bool isValidUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 检测平台（仅作展示用）
  VideoPlatform detectPlatform(String url) {
    if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) return VideoPlatform.xiaohongshu;
    if (url.contains('douyin.com') || url.contains('iesdouyin.com')) return VideoPlatform.douyin;
    if (url.contains('kuaishou.com')) return VideoPlatform.kuaishou;
    if (url.contains('bilibili.com') || url.contains('b23.tv')) return VideoPlatform.bilibili;
    if (url.contains('weibo.com')) return VideoPlatform.weibo;
    return VideoPlatform.unknown;
  }
}
