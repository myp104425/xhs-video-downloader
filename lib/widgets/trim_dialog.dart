import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 视频剪辑对话框 — 选择下载的起始和结束时间
class TrimDialog extends StatefulWidget {
  final int duration; // 视频总时长（秒）

  const TrimDialog({super.key, required this.duration});

  /// 显示对话框，返回 [trimStart, trimEnd]（秒），null 表示不剪辑
  static Future<List<int>?> show(BuildContext context, int duration) {
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TrimDialog(duration: duration),
    );
  }

  @override
  State<TrimDialog> createState() => _TrimDialogState();
}

class _TrimDialogState extends State<TrimDialog> {
  late int _startMin, _startSec;
  late int _endMin, _endSec;
  late int _totalMin, _totalSec;

  @override
  void initState() {
    super.initState();
    _totalMin = widget.duration ~/ 60;
    _totalSec = widget.duration % 60;
    _startMin = 0;
    _startSec = 0;
    _endMin = _totalMin;
    _endSec = _totalSec;
  }

  int get _startSeconds => _startMin * 60 + _startSec;
  int get _endSeconds => _endMin * 60 + _endSec;

  String _fmt(int m, int s) => '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxSec = widget.duration > 0 ? widget.duration : 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 手柄条
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.7),
                  ]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.content_cut_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text('视频剪辑', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),

          const SizedBox(height: 24),

          // 粗选滑块（仅有时长信息时显示）
          if (widget.duration > 0)
            RangeSlider(
              values: RangeValues(_startSeconds.toDouble(), _endSeconds.toDouble()),
              min: 0,
              max: maxSec.toDouble(),
              divisions: maxSec.clamp(1, 600),
              labels: RangeLabels(
                _fmt(_startMin, _startSec),
                _fmt(_endMin, _endSec),
              ),
              onChanged: (v) {
                setState(() {
                  final s = v.start.round();
                  final e = v.end.round();
                  _startMin = s ~/ 60;
                  _startSec = s % 60;
                  _endMin = e ~/ 60;
                  _endSec = e % 60;
                });
              },
            ),

          const SizedBox(height: 8),

          // 精确输入（即使 duration=0 也显示）
          Row(
              children: [
                // 起始时间
                Expanded(
                  child: _TimeInput(
                    label: '起始',
                    minutes: _startMin,
                    seconds: _startSec,
                    maxMinutes: _totalMin,
                    onChanged: (m, s) => setState(() { _startMin = m; _startSec = s; }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: theme.colorScheme.primary, size: 20),
                ),
                // 结束时间
                Expanded(
                  child: _TimeInput(
                    label: '结束',
                    minutes: _endMin,
                    seconds: _endSec,
                    maxMinutes: _totalMin,
                    onChanged: (m, s) => setState(() { _endMin = m; _endSec = s; }),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),

          // 预览
          if (_startSeconds > 0 || _endSeconds < widget.duration)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '将下载 ${_fmt(_startMin, _startSec)} ~ ${_fmt(_endMin, _endSec)}，共 ${(_endSeconds - _startSeconds)} 秒',
                      style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),

          // 按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('不剪辑'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, [_startSeconds, _endSeconds]),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_startSeconds > 0 || _endSeconds < widget.duration ? '剪辑下载' : '完整下载'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间输入组件（分:秒）
class _TimeInput extends StatefulWidget {
  final String label;
  final int minutes, seconds, maxMinutes;
  final void Function(int minutes, int seconds) onChanged;

  const _TimeInput({
    required this.label,
    required this.minutes,
    required this.seconds,
    required this.maxMinutes,
    required this.onChanged,
  });

  @override
  State<_TimeInput> createState() => _TimeInputState();
}

class _TimeInputState extends State<_TimeInput> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.minutes, widget.seconds));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(_TimeInput old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      _ctrl.text = _fmt(widget.minutes, widget.seconds);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  String _fmt(int m, int s) => '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              hintText: 'MM:SS',
              hintStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.3)),
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
            onSubmitted: (v) {
              final parts = v.split(':');
              if (parts.length == 2) {
                final m = int.tryParse(parts[0]) ?? 0;
                final s = int.tryParse(parts[1]) ?? 0;
                widget.onChanged(m.clamp(0, widget.maxMinutes), s.clamp(0, 59));
              }
            },
          ),
        ),
      ],
    );
  }
}
