import 'package:flutter/material.dart';
import '../services/parsers/parser_manager.dart';
import '../models/video_info.dart';

/// 链接输入组件
class UrlInputBar extends StatefulWidget {
  final void Function(String url) onParse;
  final bool isParsing;

  const UrlInputBar({
    super.key,
    required this.onParse,
    this.isParsing = false,
  });

  @override
  State<UrlInputBar> createState() => _UrlInputBarState();
}

class _UrlInputBarState extends State<UrlInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ParserManager _parserManager = ParserManager();

  bool _isValid = false;
  VideoPlatform? _detectedPlatform;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _validateUrl(String text) {
    final trimmed = text.trim();
    final valid = _parserManager.isValidUrl(trimmed);
    final platform = valid ? _parserManager.detectPlatform(trimmed) : null;

    setState(() {
      _isValid = valid;
      _detectedPlatform = platform;
    });
  }

  Future<void> _onParse() async {
    final url = _controller.text.trim();
    if (url.isEmpty || !_isValid) return;
    widget.onParse(url);
  }

  /// 粘贴监听
  void _onPaste() {
    // 粘贴后自动触发验证
    Future.microtask(() {
      _validateUrl(_controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 主输入卡片
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surface.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.03),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // 标题区
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
                      child: Icon(
                        Icons.link_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '粘贴视频链接',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '支持小红书 / 抖音 / 快手 / B站 / 微博',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.45),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 平台指示
                    if (_detectedPlatform != null)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          key: ValueKey(_detectedPlatform),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _detectedPlatform!.brandColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _detectedPlatform!.brandColor.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _detectedPlatform!.icon,
                                size: 14,
                                color: _detectedPlatform!.brandColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _detectedPlatform!.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _detectedPlatform!.brandColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 输入框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _validateUrl,
                  onTap: _onPaste,
                  decoration: InputDecoration(
                    hintText: '在此粘贴视频分享链接...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.25),
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withOpacity(0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        Icons.content_paste_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.4),
                            ),
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _isValid = false;
                                _detectedPlatform = null;
                              });
                            },
                          )
                        : null,
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _isValid ? (_) => _onParse() : null,
                ),
              ),

              const SizedBox(height: 16),

              // 按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: FilledButton.icon(
                      onPressed: _isValid && !widget.isParsing
                          ? _onParse
                          : null,
                      icon: widget.isParsing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _detectedPlatform?.icon ??
                                  Icons.search_rounded,
                              size: 20,
                            ),
                      label: Text(
                        widget.isParsing
                            ? '正在解析...'
                            : '解析视频',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        backgroundColor: _detectedPlatform?.brandColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
