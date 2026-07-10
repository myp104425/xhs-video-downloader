import '../../models/video_info.dart';

/// 解析器基类
///
/// 每个平台解析器继承此类，实现 canParse() 和 parse() 方法。
abstract class VideoParser {
  /// 平台标识
  VideoPlatform get platform;

  /// 验证 URL 是否属于此平台
  bool canParse(String url);

  /// 执行解析，返回视频信息
  Future<VideoInfo> parse(String url, {String? cookie});

  /// 桌面端 User-Agent（核心：防止手机页面弹窗跳转 App）
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 通用请求头（桌面端）
  static Map<String, String> commonHeaders({String? cookie, String? referer}) {
    final headers = <String, String>{
      'User-Agent': desktopUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-User': '?1',
      'Cache-Control': 'max-age=0',
      'DNT': '1',
    };

    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }

    return headers;
  }
}

/// 解析结果
class ParseResult {
  final VideoPlatform platform;
  final VideoInfo videoInfo;

  const ParseResult({required this.platform, required this.videoInfo});
}
