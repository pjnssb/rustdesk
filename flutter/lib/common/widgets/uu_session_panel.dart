import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';

const Color kUUOrange = Color(0xFFFF6B1A);
const Color kUURed = Color(0xFFE5484D);
const Color kUUGreen = Color(0xFF22C55E);

String _formatDelay(String? rawDelay) {
  if (rawDelay == null || rawDelay.isEmpty) return '--ms';
  return rawDelay.contains('ms') ? rawDelay : '${rawDelay}ms';
}

String _formatSpeed(String? rawSpeed) {
  if (rawSpeed == null || rawSpeed.isEmpty) return '--';
  return rawSpeed;
}

String _formatFps(String? rawFps) {
  if (rawFps == null || rawFps.isEmpty) return '--';
  return rawFps.split(' ').first;
}

void _connectSubFeature(
  BuildContext context,
  String id,
  FFI ffi, {
  bool isFileTransfer = false,
  bool isViewCamera = false,
  bool isTcpTunneling = false,
  bool isTerminal = false,
}) {
  final connToken = bind.sessionGetConnToken(sessionId: ffi.sessionId);
  connect(
    context,
    id,
    loginMethod: bind.sessionGetCommonSync(
            sessionId: ffi.sessionId, key: 'login_method', param: '') ??
        '',
    isFileTransfer: isFileTransfer,
    isViewCamera: isViewCamera,
    isTerminal: isTerminal,
    isTcpTunneling: isTcpTunneling,
    connToken: connToken,
  );
}

class UUSessionSettingsPanel extends StatefulWidget {
  final String id;
  final FFI ffi;
  final VoidCallback onClose;
  final bool isMobileStyle;
  final bool screenDrawActive;
  final VoidCallback? onToggleScreenDraw;
  final VoidCallback? onOpenKeyboard;
  final VoidCallback? onToggleGestureHelp;
  final VoidCallback? onAdjustWindow;

  const UUSessionSettingsPanel({
    Key? key,
    required this.id,
    required this.ffi,
    required this.onClose,
    required this.isMobileStyle,
    this.screenDrawActive = false,
    this.onToggleScreenDraw,
    this.onOpenKeyboard,
    this.onToggleGestureHelp,
    this.onAdjustWindow,
  }) : super(key: key);

  @override
  State<UUSessionSettingsPanel> createState() => _UUSessionSettingsPanelState();
}

class _UUSessionSettingsPanelState extends State<UUSessionSettingsPanel> {
  int _tabIndex = 0;

  String _imageQuality = kRemoteImageQualityBest;
  int _customQualityValue = 50;
  int _fpsLimit = 60;
  String _codecPref = 'auto';
  List<bool> _supportedCodecs = [true, false, true, false];
  int _audioVolume = 100;
  String _keyboardMode = 'legacy';
  String _scrollStyle = kRemoteScrollStyleAuto;
  bool _superScreenActive = false;
  bool _secondaryScreenActive = false;

  FFI get ffi => widget.ffi;
  SessionID get sessionId => ffi.sessionId;
  PeerInfo get pi => ffi.ffiModel.pi;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final q = await bind.sessionGetImageQuality(sessionId: sessionId);
    final customQ =
        await bind.sessionGetCustomImageQuality(sessionId: sessionId);
    final fpsOpt =
        await bind.sessionGetOption(sessionId: sessionId, arg: 'custom-fps');
    final codec = await bind.sessionGetOption(
        sessionId: sessionId, arg: kOptionCodecPreference);
    final altStr = await bind.sessionAlternativeCodecs(sessionId: sessionId);
    final volOpt = await bind.sessionGetOption(
        sessionId: sessionId, arg: kOptionAudioVolume);
    final kbMode = await bind.sessionGetKeyboardMode(sessionId: sessionId);
    final scroll = await bind.sessionGetScrollStyle(sessionId: sessionId);

    List<bool> codecs = [false, false, false, false];
    try {
      final map = jsonDecode(altStr) as Map<String, dynamic>;
      codecs = [
        map['vp8'] == true,
        map['av1'] == true,
        map['h264'] == true,
        map['h265'] == true,
      ];
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      if (q != null && q.isNotEmpty) _imageQuality = q;
      if (customQ != null && customQ.isNotEmpty) {
        _customQualityValue = customQ[0].clamp(10, 200);
      }
      _fpsLimit = int.tryParse(fpsOpt ?? '') ?? 30;
      _codecPref = (codec != null && codec.isNotEmpty) ? codec : 'auto';
      _supportedCodecs = codecs;
      _audioVolume = (int.tryParse(volOpt ?? '') ?? 100).clamp(0, 100);
      _keyboardMode = (kbMode != null && kbMode.isNotEmpty) ? kbMode : 'legacy';
      _scrollStyle =
          (scroll != null && scroll.isNotEmpty) ? scroll : kRemoteScrollStyleAuto;
    });
  }

  bool get _isDark =>
      widget.isMobileStyle ||
      Theme.of(context).brightness == Brightness.dark;

  Color get _panelBg =>
      _isDark ? const Color(0xF0181B22) : const Color(0xF8F7F8FA);
  Color get _cardBg =>
      _isDark ? const Color(0xFF232732) : Colors.white;
  Color get _cardBorder =>
      _isDark ? Colors.white10 : const Color(0xFFE5E7EB);
  Color get _textPrimary =>
      _isDark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _chipBg =>
      _isDark ? const Color(0xFF2D3342) : const Color(0xFFF3F4F6);

  Future<void> _selectQuality(String mode) async {
    setState(() => _imageQuality = mode);
    if (mode == 'ultra') {
      await bind.sessionSetCustomImageQuality(
          sessionId: sessionId, value: 120);
      if (_fpsLimit < 60) {
        await _selectFps(60);
      }
    } else if (mode == kRemoteImageQualityCustom) {
      await bind.sessionSetCustomImageQuality(
          sessionId: sessionId, value: _customQualityValue);
    } else {
      await bind.sessionSetImageQuality(sessionId: sessionId, value: mode);
    }
  }

  Future<void> _selectFps(int fps) async {
    setState(() => _fpsLimit = fps);
    await bind.sessionSetCustomFps(sessionId: sessionId, fps: fps);
  }

  Future<void> _selectCodec(String codec) async {
    setState(() => _codecPref = codec);
    await bind.sessionPeerOption(
        sessionId: sessionId, name: kOptionCodecPreference, value: codec);
    bind.sessionChangePreferCodec(sessionId: sessionId);
  }

  Future<void> _changeResolutionPreset(String preset) async {
    if (pi.currentDisplay == kAllDisplayValue) return;
    int? w;
    int? h;
    if (preset == 'follow') {
      final size = MediaQuery.of(context).size;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final rawW = (size.width * dpr).round();
      final rawH = (size.height * dpr).round();
      w = rawW >= rawH ? rawW : rawH;
      h = rawW >= rawH ? rawH : rawW;
      // Snap to nearest even dimensions
      w = (w ~/ 2) * 2;
      h = (h ~/ 2) * 2;
    } else if (preset == '1080p') {
      w = 1920;
      h = 1080;
    } else if (preset == '2k') {
      w = 2560;
      h = 1440;
    } else if (preset == 'original') {
      final orig = pi.tryGetDisplayIfNotAllDisplay()?.originalResolution;
      if (orig != null && orig.width > 0 && orig.height > 0) {
        w = orig.width;
        h = orig.height;
      }
    }
    if (w != null && h != null && w > 0 && h > 0) {
      await bind.sessionChangeResolution(
        sessionId: sessionId,
        display: pi.currentDisplay,
        width: w,
        height: h,
      );
      showToast('${translate('Resolution')}: ${w}x$h');
    }
  }

  Future<void> _toggleSuperScreen(bool enable) async {
    if (!showVirtualDisplayMenu(ffi)) {
      showToast(translate('Virtual display is not supported on this peer'));
      return;
    }
    setState(() => _superScreenActive = enable);
    final privacyState = PrivacyModeState.find(widget.id);
    if (enable) {
      if (pi.isRustDeskIdd) {
        await bind.sessionToggleVirtualDisplay(
            sessionId: sessionId, index: 1, on: true);
      } else if (pi.isAmyuniIdd && pi.amyuniVirtualDisplayCount == 0) {
        await bind.sessionToggleVirtualDisplay(
            sessionId: sessionId, index: 0, on: true);
      }
      if (privacyState.isEmpty) {
        await bind.sessionTogglePrivacyMode(
          sessionId: sessionId,
          implKey: 'privacy_mode_impl_virtual_display',
          on: true,
        );
      }
      showToast(translate('Super screen enabled (virtual primary + physical screen off)'));
    } else {
      if (privacyState.isNotEmpty) {
        await bind.sessionTogglePrivacyMode(
          sessionId: sessionId,
          implKey: privacyState.value,
          on: false,
        );
      }
      await bind.sessionToggleVirtualDisplay(
          sessionId: sessionId, index: kAllVirtualDisplay, on: false);
      showToast(translate('Super screen exited'));
    }
  }

  Future<void> _toggleSecondaryScreen(bool enable) async {
    if (!showVirtualDisplayMenu(ffi)) {
      showToast(translate('Virtual display is not supported on this peer'));
      return;
    }
    setState(() => _secondaryScreenActive = enable);
    if (enable) {
      final idx = pi.isRustDeskIdd ? 1 : 0;
      await bind.sessionToggleVirtualDisplay(
          sessionId: sessionId, index: idx, on: true);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (pi.displays.length > 1) {
          openMonitorInTheSameTab(pi.displays.length - 1, ffi, pi);
        }
      });
      showToast(translate('Wireless extended display enabled'));
    } else {
      await bind.sessionToggleVirtualDisplay(
          sessionId: sessionId, index: kAllVirtualDisplay, on: false);
      if (pi.displays.isNotEmpty) {
        openMonitorInTheSameTab(0, ffi, pi);
      }
      showToast(translate('Wireless extended display exited'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.isMobileStyle
        ? [
            translate('Display'),
            translate('Control'),
            translate('Audio'),
            translate('More'),
          ]
        : [
            translate('Screen'),
            translate('Control'),
            translate('Audio'),
            translate('Advanced'),
          ];

    return AnimatedBuilder(
      animation: Listenable.merge([
        ffi.qualityMonitorModel,
        ffi.canvasModel,
        ffi.ffiModel,
      ]),
      builder: (context, _) {
        final qm = ffi.qualityMonitorModel;
        final canvas = ffi.canvasModel;
        return Material(
          color: Colors.transparent,
          child: Container(
            width: widget.isMobileStyle ? 340 : 356,
            decoration: BoxDecoration(
              color: _panelBg,
              border: Border(left: BorderSide(color: _cardBorder)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(-4, 0),
                ),
              ],
            ),
            child: SafeArea(
              left: false,
              child: Column(
                children: [
                  _buildHeader(qm),
                  _buildTabBar(tabs),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: _buildTabContent(qm, canvas),
                    ),
                  ),
                  _buildFooter(qm),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(QualityMonitorModel qm) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 6),
      child: Row(
        children: [
          Text(
            translate('Settings'),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: kUUGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${translate('Connected')} ${_formatDelay(qm.data.delay)}',
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: widget.onClose,
            icon: Icon(Icons.close, size: 18, color: _textSecondary),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<String> tabs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final active = _tabIndex == idx;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tabIndex = idx),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active && widget.isMobileStyle
                      ? _cardBg
                      : Colors.transparent,
                  borderRadius:
                      widget.isMobileStyle ? BorderRadius.circular(18) : null,
                  border: !widget.isMobileStyle
                      ? Border(
                          bottom: BorderSide(
                            color: active ? kUUOrange : Colors.transparent,
                            width: 2,
                          ),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[idx],
                  style: TextStyle(
                    color: active
                        ? (widget.isMobileStyle ? Colors.white : kUUOrange)
                        : _textSecondary,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFooter(QualityMonitorModel qm) {
    final fps = _formatFps(qm.data.fps);
    final delay = _formatDelay(qm.data.delay);
    final speed = _formatSpeed(qm.data.speed);
    final codec = qm.data.codecFormat ?? _codecPref.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: widget.isMobileStyle
            ? [
                _footerStat(translate('Real FPS'), fps),
                _footerStat(translate('Delay'), delay),
                _footerStat(translate('Bitrate'), speed),
              ]
            : [
                _footerStat(translate('Codec'), codec),
                _footerStat(translate('FPS'), fps),
                _footerStat(translate('Delay'), delay),
              ],
      ),
    );
  }

  Widget _footerStat(String label, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: TextStyle(color: _textSecondary, fontSize: 11)),
        Text(val,
            style: TextStyle(
                color: _textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionHeader(String title, [String? trailing]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                color: kUUOrange,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? kUUOrange.withOpacity(_isDark ? 0.2 : 0.12)
              : _chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? kUUOrange : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: !enabled
                ? _textSecondary.withOpacity(0.5)
                : (selected ? kUUOrange : _textPrimary),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: _textPrimary, fontSize: 13)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle,
                        style: TextStyle(color: _textSecondary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: kUUOrange,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(QualityMonitorModel qm, CanvasModel canvas) {
    switch (_tabIndex) {
      case 0:
        return _buildDisplayTab(qm, canvas);
      case 1:
        return _buildControlTab(canvas);
      case 2:
        return _buildAudioTab();
      default:
        return _buildMoreTab(canvas);
    }
  }

  Widget _buildDisplayTab(QualityMonitorModel qm, CanvasModel canvas) {
    final i444 = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: kOptionI444);
    final hdr = qm.hdrMode.value;
    final standardColor = !i444 && !hdr;
    final qualityLabelMap = {
      kRemoteImageQualityLow: translate('Smooth'),
      kRemoteImageQualityBalanced: translate('Balanced'),
      kRemoteImageQualityBest: translate('HD'),
      'ultra': translate('Ultra HD'),
      kRemoteImageQualityCustom: translate('Custom'),
    };
    final fpsOptions = widget.isMobileStyle ? [30, 60, 90, 120] : [30, 60, 90, 144];
    final curDisplay = pi.tryGetDisplayIfNotAllDisplay();
    final resText = curDisplay != null
        ? '${curDisplay.width}×${curDisplay.height}'
        : '${canvas.getDisplayWidth()}×${canvas.getDisplayHeight()}';
    final curZoom = canvas.currentZoomPercent;

    return Column(
      children: [
        if (pi.displays.length > 1 && pi.currentDisplay != kAllDisplayValue)
          _card(children: [
            _sectionHeader(translate('Monitor'), '${pi.currentDisplay + 1}/${pi.displays.length}'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(pi.displays.length, (i) {
                return _chipButton(
                  label: '${translate('Display')} ${i + 1}',
                  selected: pi.currentDisplay == i,
                  onTap: () {
                    openMonitorInTheSameTab(i, ffi, pi);
                    setState(() {});
                  },
                );
              }),
            ),
          ]),
        _card(children: [
          _sectionHeader(
            translate('Image quality preset'),
            qualityLabelMap[_imageQuality] ?? translate('Custom'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipButton(
                label: translate('Smooth'),
                selected: _imageQuality == kRemoteImageQualityLow,
                onTap: () => _selectQuality(kRemoteImageQualityLow),
              ),
              _chipButton(
                label: translate('Balanced'),
                selected: _imageQuality == kRemoteImageQualityBalanced,
                onTap: () => _selectQuality(kRemoteImageQualityBalanced),
              ),
              _chipButton(
                label: translate('HD'),
                selected: _imageQuality == kRemoteImageQualityBest,
                onTap: () => _selectQuality(kRemoteImageQualityBest),
              ),
              _chipButton(
                label: translate('Ultra HD'),
                selected: _imageQuality == 'ultra',
                onTap: () => _selectQuality('ultra'),
              ),
              _chipButton(
                label: translate('Custom'),
                selected: _imageQuality == kRemoteImageQualityCustom,
                onTap: () => _selectQuality(kRemoteImageQualityCustom),
              ),
            ],
          ),
          if (_imageQuality == kRemoteImageQualityCustom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${translate('Bitrate')}: $_customQualityValue%',
                    style: TextStyle(color: _textSecondary, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _customQualityValue.toDouble(),
                    min: 10,
                    max: 200,
                    divisions: 38,
                    activeColor: kUUOrange,
                    onChanged: (v) {
                      setState(() => _customQualityValue = v.round());
                    },
                    onChangeEnd: (v) {
                      bind.sessionSetCustomImageQuality(
                          sessionId: sessionId, value: v.round());
                    },
                  ),
                ),
              ],
            ),
          ],
        ]),
        _card(children: [
          _sectionHeader(translate('FPS limit'), '$_fpsLimit fps'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fpsOptions
                .map((fps) => _chipButton(
                      label: '$fps',
                      selected: _fpsLimit == fps,
                      onTap: () => _selectFps(fps),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          _sectionHeader(translate('Resolution'), resText),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipButton(
                label: translate('Follow client'),
                selected: false,
                onTap: () => _changeResolutionPreset('follow'),
              ),
              _chipButton(
                label: '1080P',
                selected: curDisplay?.width == 1920 && curDisplay?.height == 1080,
                onTap: () => _changeResolutionPreset('1080p'),
              ),
              _chipButton(
                label: '2K',
                selected: curDisplay?.width == 2560 && curDisplay?.height == 1440,
                onTap: () => _changeResolutionPreset('2k'),
              ),
              if (pi.resolutions.length > 1)
                _chipButton(
                  label: translate('More'),
                  selected: false,
                  onTap: () => _showAllResolutionsDialog(),
                ),
            ],
          ),
        ]),
        _card(children: [
          _sectionHeader(translate('View zoom'), '$curZoom%'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipButton(
                label: translate('Fit'),
                selected: canvas.viewStyle.style == kRemoteViewStyleAdaptive,
                onTap: () => canvas.applyZoomPreset(kRemoteViewStyleAdaptive),
              ),
              _chipButton(
                label: '100%',
                selected: canvas.viewStyle.style == kRemoteViewStyleOriginal,
                onTap: () => canvas.applyZoomPreset('100'),
              ),
              _chipButton(
                label: '150%',
                selected: curZoom == 150,
                onTap: () => canvas.applyZoomPreset('150'),
              ),
              _chipButton(
                label: '200%',
                selected: curZoom == 200,
                onTap: () => canvas.applyZoomPreset('200'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    size: 18, color: _textSecondary),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                onPressed: () =>
                    canvas.setZoomPercent((curZoom - 10).clamp(25, 400)),
              ),
              Expanded(
                child: Slider(
                  value: curZoom.clamp(25, 400).toDouble(),
                  min: 25,
                  max: 400,
                  divisions: 75,
                  activeColor: kUUOrange,
                  onChanged: (v) => canvas.setZoomPercent(v.round()),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline,
                    size: 18, color: _textSecondary),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                onPressed: () =>
                    canvas.setZoomPercent((curZoom + 10).clamp(25, 400)),
              ),
              TextButton(
                onPressed: () => canvas.applyZoomPreset('reset'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                child: Text(translate('Reset'),
                    style: const TextStyle(color: kUUOrange, fontSize: 12)),
              ),
            ],
          ),
        ]),
        _card(children: [
          _sectionHeader(
            translate('Codec mode'),
            '${_codecPref.toUpperCase()} · ${qm.data.codecFormat ?? ''}',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipButton(
                label: translate('Auto'),
                selected: _codecPref == 'auto',
                onTap: () => _selectCodec('auto'),
              ),
              if (_supportedCodecs[2])
                _chipButton(
                  label: 'H.264',
                  selected: _codecPref == 'h264',
                  onTap: () => _selectCodec('h264'),
                ),
              if (_supportedCodecs[3])
                _chipButton(
                  label: 'H.265',
                  selected: _codecPref == 'h265',
                  onTap: () => _selectCodec('h265'),
                ),
              _chipButton(
                label: 'VP9',
                selected: _codecPref == 'vp9',
                onTap: () => _selectCodec('vp9'),
              ),
              if (_supportedCodecs[1])
                _chipButton(
                  label: 'AV1',
                  selected: _codecPref == 'av1',
                  onTap: () => _selectCodec('av1'),
                ),
              if (_supportedCodecs[0])
                _chipButton(
                  label: 'VP8',
                  selected: _codecPref == 'vp8',
                  onTap: () => _selectCodec('vp8'),
                ),
            ],
          ),
          const Divider(height: 18),
          _switchRow(
            title: translate('True color (4:4:4)'),
            subtitle: translate('4:4:4 sampling for sharper text (uses VP9/AV1, higher bandwidth)'),
            value: i444,
            onChanged: (v) async {
              await qm.setTrueColor(v);
              setState(() {});
            },
          ),
          _switchRow(
            title: 'HDR',
            subtitle: translate('Mutually exclusive with True Color; disables True Color automatically'),
            value: hdr,
            onChanged: (v) async {
              await qm.setHdrMode(v);
              setState(() {});
            },
          ),
          _switchRow(
            title: translate('Standard color'),
            subtitle: translate('Standard 4:2:0 color mode'),
            value: standardColor,
            onChanged: (v) async {
              if (v) {
                await qm.setStandardColor();
                setState(() {});
              }
            },
          ),
          Obx(() => _switchRow(
                title: translate('Auto downgrade on congestion'),
                subtitle: translate('Downgrade order when constrained: HDR -> True Color -> Quality'),
                value: qm.autoColorDowngrade.value,
                onChanged: (v) => qm.setAutoColorDowngrade(v),
              )),
        ]),
        _card(children: [
          _switchRow(
            title: translate('Show quality monitor'),
            value: qm.show,
            onChanged: (v) async {
              await bind.sessionToggleOption(
                  sessionId: sessionId, value: 'show-quality-monitor');
              await qm.checkShowQualityMonitor(sessionId);
            },
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(translate('Rotate screen'),
                style: TextStyle(color: _textPrimary, fontSize: 13)),
            trailing: Text('${canvas.rotationTurns * 90}°',
                style: const TextStyle(color: kUUOrange, fontSize: 12)),
            onTap: () => canvas.rotateQuarter(),
          ),
        ]),
      ],
    );
  }

  Widget _buildControlTab(CanvasModel canvas) {
    final ffiModel = ffi.ffiModel;
    final inputModel = ffi.inputModel;
    final showRemoteCursor = ShowRemoteCursorState.find(widget.id);
    final sensitivityPct = (inputModel.mouseSensitivity * 100).round();

    return Column(
      children: [
        if (isMobile)
          _card(children: [
            _sectionHeader(translate('Touch & mouse mode')),
            Obx(() {
              final mode = inputModel.mobileInputMode.value;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (ffiModel.isPeerWindows)
                    _chipButton(
                      label: translate('Windows native touch (no cursor)'),
                      selected: mode == kMobileInputNativeTouch,
                      onTap: () =>
                          inputModel.setMobileInputMode(kMobileInputNativeTouch),
                    ),
                  _chipButton(
                    label: translate('Touch mode'),
                    selected: mode == kMobileInputTouchMouse,
                    onTap: () =>
                        inputModel.setMobileInputMode(kMobileInputTouchMouse),
                  ),
                  _chipButton(
                    label: translate('Mouse mode'),
                    selected: mode == kMobileInputMouse,
                    onTap: () =>
                        inputModel.setMobileInputMode(kMobileInputMouse),
                  ),
                ],
              );
            }),
            const SizedBox(height: 8),
            _switchRow(
              title: translate('Multi-touch passthrough (lock zoom)'),
              subtitle: translate('When off, 2 fingers zoom/pan locally; when on, all fingers pass to Windows'),
              value: canvas.locked,
              onChanged: (v) => canvas.setLocked(v),
            ),
            if (widget.onToggleGestureHelp != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onToggleGestureHelp,
                  icon: const Icon(Icons.help_outline,
                      size: 16, color: kUUOrange),
                  label: Text(translate('Gesture help'),
                      style: const TextStyle(color: kUUOrange, fontSize: 12)),
                ),
              ),
          ]),
        _card(children: [
          _sectionHeader(translate('Smart mouse & sensitivity')),
          Obx(() => _switchRow(
                title: translate('Smart / Game mouse (Relative mode)'),
                subtitle: translate('Enable for 3D games or when normal mouse cannot operate'),
                value: inputModel.smartMouse.value ||
                    inputModel.relativeMouseMode.value,
                onChanged: inputModel.isRelativeMouseModeSupported
                    ? (v) => inputModel.setSmartMouse(v)
                    : null,
              )),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${translate('Sensitivity')}: $sensitivityPct%',
                  style: TextStyle(color: _textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: sensitivityPct.toDouble(),
                  min: 10,
                  max: 300,
                  divisions: 29,
                  activeColor: kUUOrange,
                  onChanged: (v) {
                    setState(() {
                      inputModel.mouseSensitivity = v / 100.0;
                    });
                  },
                  onChangeEnd: (v) =>
                      inputModel.setMouseSensitivityPercent(v.round()),
                ),
              ),
            ],
          ),
          if (isMobile && !inputModel.isNativeTouchMode) ...[
            _switchRow(
              title: translate('Show virtual mouse'),
              value: ffiModel.virtualMouseMode.showVirtualMouse,
              onChanged: (_) async {
                await ffiModel.virtualMouseMode.toggleVirtualMouse();
                setState(() {});
              },
            ),
            _switchRow(
              title: translate('Show virtual joystick'),
              value: ffiModel.virtualMouseMode.showVirtualJoystick,
              onChanged: (_) async {
                await ffiModel.virtualMouseMode.toggleVirtualJoystick();
                setState(() {});
              },
            ),
          ],
        ]),
        _card(children: [
          _sectionHeader(translate('Cursor & keyboard')),
          if (!ffiModel.isPeerAndroid && !canvas.cursorEmbedded)
            Obx(() => _switchRow(
                  title: translate('Show remote cursor'),
                  value: showRemoteCursor.value,
                  onChanged: ffiModel.viewOnly
                      ? null
                      : (v) async {
                          await bind.sessionToggleOption(
                              sessionId: sessionId,
                              value: 'show-remote-cursor');
                          showRemoteCursor.value =
                              bind.sessionGetToggleOptionSync(
                                  sessionId: sessionId,
                                  arg: 'show-remote-cursor');
                        },
                )),
          if (!isMobile && !ffiModel.isPeerAndroid)
            _switchRow(
              title: translate('Zoom cursor'),
              value: bind.sessionGetToggleOptionSync(
                  sessionId: sessionId, arg: kOptionZoomCursor),
              onChanged: (v) async {
                await bind.sessionToggleOption(
                    sessionId: sessionId, value: kOptionZoomCursor);
                setState(() {});
              },
            ),
          _switchRow(
            title: translate('swap-left-right-mouse'),
            value: bind.sessionGetToggleOptionSync(
                sessionId: sessionId, arg: 'swap-left-right-mouse'),
            onChanged: ffiModel.viewOnly
                ? null
                : (v) async {
                    await bind.sessionToggleOption(
                        sessionId: sessionId, value: 'swap-left-right-mouse');
                    setState(() {});
                  },
          ),
          _switchRow(
            title: translate('View Mode'),
            subtitle: translate('View screen only without sending input'),
            value: ffiModel.viewOnly,
            onChanged: (v) async {
              await bind.sessionToggleOption(
                  sessionId: sessionId, value: kOptionToggleViewOnly);
              ffiModel.setViewOnly(widget.id, v);
              setState(() {});
            },
          ),
          if (ffiModel.isPeerWindows &&
              ffiModel.permissions['block_input'] != false)
            Obx(() {
              final blk = BlockInputState.find(widget.id);
              return _switchRow(
                title: translate('Block user input'),
                value: blk.value,
                onChanged: (v) async {
                  await bind.sessionToggleOption(
                      sessionId: sessionId,
                      value: '${blk.value ? 'un' : ''}block-input');
                  blk.value = !blk.value;
                },
              );
            }),
          if (!isMobile) ...[
            const SizedBox(height: 6),
            _sectionHeader(translate('Keyboard mode'), _keyboardMode),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['legacy', 'map', 'translate', 'auto']
                  .map((m) => _chipButton(
                        label: m.toUpperCase(),
                        selected: _keyboardMode == m,
                        onTap: () async {
                          await bind.sessionSetKeyboardMode(
                              sessionId: sessionId, value: m);
                          setState(() => _keyboardMode = m);
                        },
                      ))
                  .toList(),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _buildAudioTab() {
    final audioDisabled = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: 'disable-audio');
    return Column(
      children: [
        _card(children: [
          _sectionHeader(translate('Remote audio')),
          _switchRow(
            title: translate('Audio'),
            subtitle: audioDisabled ? translate('Muted') : translate('Enabled'),
            value: !audioDisabled,
            onChanged: (v) async {
              await bind.sessionToggleOption(
                  sessionId: sessionId, value: 'disable-audio');
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _audioVolume == 0 ? Icons.volume_off : Icons.volume_up,
                size: 18,
                color: _textSecondary,
              ),
              const SizedBox(width: 8),
              Text('${translate('Volume')} $_audioVolume%',
                  style: TextStyle(color: _textPrimary, fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _audioVolume.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: kUUOrange,
                  onChanged: (v) {
                    setState(() => _audioVolume = v.round());
                  },
                  onChangeEnd: (v) async {
                    await bind.sessionPeerOption(
                      sessionId: sessionId,
                      name: kOptionAudioVolume,
                      value: v.round().toString(),
                    );
                  },
                ),
              ),
            ],
          ),
        ]),
        _card(children: [
          _sectionHeader(translate('Voice call')),
          Obx(() {
            final status = ffi.chatModel.voiceCallStatus.value;
            final inCall = status == VoiceCallStatus.waitingForResponse ||
                status == VoiceCallStatus.connected;
            return Row(
              children: [
                Expanded(
                  child: Text(
                    inCall
                        ? translate('Voice call active')
                        : translate('Start voice call with peer'),
                    style: TextStyle(color: _textSecondary, fontSize: 12),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: inCall ? kUURed : kUUOrange,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () {
                    if (inCall) {
                      bind.sessionCloseVoiceCall(sessionId: sessionId);
                    } else {
                      bind.sessionRequestVoiceCall(sessionId: sessionId);
                    }
                  },
                  child: Text(inCall
                      ? translate('End voice call')
                      : translate('Voice call')),
                ),
              ],
            );
          }),
          if (isDesktop && !isWeb) ...[
            const Divider(height: 16),
            AudioInput(
              isCm: false,
              isVoiceCall: true,
              builder: (devices, current, setDevice) {
                return DropdownButtonFormField<String>(
                  value: devices.contains(current) ? current : null,
                  dropdownColor: _cardBg,
                  decoration: InputDecoration(
                    labelText: translate('Microphone'),
                    labelStyle: TextStyle(color: _textSecondary, fontSize: 12),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  items: devices
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _textPrimary, fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDevice(v);
                  },
                );
              },
            ),
          ],
        ]),
      ],
    );
  }

  Widget _buildMoreTab(CanvasModel canvas) {
    final privacyState = PrivacyModeState.find(widget.id);
    final disableClipboard = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: 'disable-clipboard');
    final fileCopyPaste = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: kOptionEnableFileCopyPaste);
    final lockAfterEnd = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: 'lock-after-session-end');

    return Column(
      children: [
        _card(children: [
          _sectionHeader(translate('Special features')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip(
                icon: Icons.brush_outlined,
                label: translate('Screen draw'),
                active: widget.screenDrawActive,
                onTap: () {
                  widget.onToggleScreenDraw?.call();
                  widget.onClose();
                },
              ),
              _actionChip(
                icon: Icons.folder_outlined,
                label: translate('Transfer file'),
                onTap: () => _connectSubFeature(
                    context, widget.id, ffi, isFileTransfer: true),
              ),
              _actionChip(
                icon: Icons.terminal,
                label: translate('Terminal'),
                onTap: () => _connectSubFeature(
                    context, widget.id, ffi, isTerminal: true),
              ),
              _actionChip(
                icon: Icons.videocam_outlined,
                label: translate('View camera'),
                onTap: () => _connectSubFeature(
                    context, widget.id, ffi, isViewCamera: true),
              ),
              _actionChip(
                icon: Icons.chat_bubble_outline,
                label: translate('Text chat'),
                onTap: () {
                  ffi.chatModel.changeCurrentKey(
                      MessageKey(widget.id, ChatModel.clientModeID));
                  ffi.chatModel.toggleChatOverlay();
                },
              ),
              if (isDesktop)
                _actionChip(
                  icon: Icons.lan_outlined,
                  label: translate('TCP tunneling'),
                  onTap: () => _connectSubFeature(
                      context, widget.id, ffi, isTcpTunneling: true),
                ),
            ],
          ),
        ]),
        if (showVirtualDisplayMenu(ffi))
          _card(children: [
            _sectionHeader(translate('Virtual display & privacy')),
            _switchRow(
              title: translate('Super screen'),
              subtitle: translate('Create high-res virtual primary display & turn off physical screen'),
              value: _superScreenActive,
              onChanged: (v) => _toggleSuperScreen(v),
            ),
            _switchRow(
              title: translate('Wireless secondary display'),
              subtitle: translate('Add extended desktop screen on controlled PC'),
              value: _secondaryScreenActive,
              onChanged: (v) => _toggleSecondaryScreen(v),
            ),
            if (pi.features.privacyMode)
              Obx(() => _switchRow(
                    title: translate('Privacy mode'),
                    subtitle: translate('Black out physical screen on controlled device'),
                    value: privacyState.isNotEmpty,
                    onChanged: (v) async {
                      await bind.sessionTogglePrivacyMode(
                        sessionId: sessionId,
                        implKey: privacyState.isNotEmpty
                            ? privacyState.value
                            : kPrivacyModeImplMag,
                        on: v,
                      );
                    },
                  )),
          ]),
        _card(children: [
          _sectionHeader(translate('Clipboard & session')),
          _switchRow(
            title: translate('Clipboard sync'),
            value: !disableClipboard,
            onChanged: ffi.ffiModel.viewOnly
                ? null
                : (v) async {
                    await bind.sessionToggleOption(
                        sessionId: sessionId, value: 'disable-clipboard');
                    setState(() {});
                  },
          ),
          _switchRow(
            title: translate('Enable file copy and paste'),
            value: fileCopyPaste,
            onChanged: ffi.ffiModel.viewOnly
                ? null
                : (v) async {
                    await bind.sessionToggleOption(
                        sessionId: sessionId,
                        value: kOptionEnableFileCopyPaste);
                    setState(() {});
                  },
          ),
          _switchRow(
            title: translate('Lock after session end'),
            value: lockAfterEnd,
            onChanged: ffi.ffiModel.viewOnly
                ? null
                : (v) async {
                    await bind.sessionToggleOption(
                        sessionId: sessionId, value: 'lock-after-session-end');
                    setState(() {});
                  },
          ),
          if (isDesktop) ...[
            const SizedBox(height: 6),
            _sectionHeader(translate('Scroll mode')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipButton(
                  label: translate('ScrollAuto'),
                  selected: _scrollStyle == kRemoteScrollStyleAuto,
                  onTap: () async {
                    await bind.sessionSetScrollStyle(
                        sessionId: sessionId, value: kRemoteScrollStyleAuto);
                    await canvas.updateScrollStyle();
                    setState(() => _scrollStyle = kRemoteScrollStyleAuto);
                  },
                ),
                _chipButton(
                  label: translate('Scrollbar'),
                  selected: _scrollStyle == kRemoteScrollStyleBar,
                  onTap: () async {
                    await bind.sessionSetScrollStyle(
                        sessionId: sessionId, value: kRemoteScrollStyleBar);
                    await canvas.updateScrollStyle();
                    setState(() => _scrollStyle = kRemoteScrollStyleBar);
                  },
                ),
                _chipButton(
                  label: translate('ScrollEdge'),
                  selected: _scrollStyle == kRemoteScrollStyleEdge,
                  onTap: () async {
                    await bind.sessionSetScrollStyle(
                        sessionId: sessionId, value: kRemoteScrollStyleEdge);
                    await canvas.updateScrollStyle();
                    setState(() => _scrollStyle = kRemoteScrollStyleEdge);
                  },
                ),
              ],
            ),
          ],
        ]),
        _card(children: [
          _sectionHeader(translate('System shortcuts')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (pi.platform == kPeerPlatformLinux || pi.sasEnabled)
                _actionChip(
                  icon: Icons.security,
                  label: 'Ctrl+Alt+Del',
                  onTap: () => bind.sessionCtrlAltDel(sessionId: sessionId),
                ),
              _actionChip(
                icon: Icons.desktop_windows,
                label: translate('Show desktop'),
                onTap: () {
                  ffi.inputModel.command = true;
                  ffi.inputModel.inputKey('VK_D');
                  ffi.inputModel.command = false;
                },
              ),
              _actionChip(
                icon: Icons.monitor_heart_outlined,
                label: translate('Task manager'),
                onTap: () {
                  ffi.inputModel.ctrl = true;
                  ffi.inputModel.shift = true;
                  ffi.inputModel.inputKey('VK_ESCAPE');
                  ffi.inputModel.ctrl = false;
                  ffi.inputModel.shift = false;
                },
              ),
              _actionChip(
                icon: Icons.lock_outline,
                label: translate('Insert Lock'),
                onTap: () => bind.sessionLockScreen(sessionId: sessionId),
              ),
              _actionChip(
                icon: Icons.refresh,
                label: translate('Refresh'),
                onTap: () => sessionRefreshVideo(sessionId, pi),
              ),
              if (isDesktop && pi.currentDisplay != kAllDisplayValue)
                _actionChip(
                  icon: Icons.camera_alt_outlined,
                  label: translate('Take screenshot'),
                  onTap: () => bind.sessionTakeScreenshot(
                      sessionId: sessionId, display: pi.currentDisplay),
                ),
              _actionChip(
                icon: ffi.recordingModel.start
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record_outlined,
                label: ffi.recordingModel.start
                    ? translate('Stop recording')
                    : translate('Record'),
                active: ffi.recordingModel.start,
                onTap: () {
                  ffi.recordingModel.toggle();
                  setState(() {});
                },
              ),
              if (widget.onAdjustWindow != null)
                _actionChip(
                  icon: Icons.fit_screen,
                  label: translate('Adjust Window'),
                  onTap: widget.onAdjustWindow!,
                ),
              _actionChip(
                icon: Icons.restart_alt,
                label: translate('Restart'),
                onTap: () => showRestartRemoteDevice(
                    pi, widget.id, sessionId, ffi.dialogManager),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? kUUOrange.withOpacity(0.18)
              : _chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? kUUOrange : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? kUUOrange : _textPrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? kUUOrange : _textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllResolutionsDialog() {
    final resolutions = pi.resolutions;
    final cur = pi.tryGetDisplayIfNotAllDisplay(display: pi.currentDisplay);
    ffi.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('Resolution')),
        content: SizedBox(
          width: 260,
          child: ListView(
            shrinkWrap: true,
            children: resolutions
                .map((e) => getRadio<String>(
                      Text('${e.width}x${e.height}'),
                      '${e.width}x${e.height}',
                      '${cur?.width ?? 0}x${cur?.height ?? 0}',
                      (v) {
                        close();
                        bind.sessionChangeResolution(
                          sessionId: sessionId,
                          display: pi.currentDisplay,
                          width: e.width,
                          height: e.height,
                        );
                      },
                    ))
                .toList(),
          ),
        ),
      );
    }, clickMaskDismiss: true, backDismiss: true);
  }
}

class UUMobileTopStatusPill extends StatelessWidget {
  final FFI ffi;
  const UUMobileTopStatusPill({Key? key, required this.ffi}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ffi.ffiModel, ffi.qualityMonitorModel]),
      builder: (context, _) {
        final pi = ffi.ffiModel.pi;
        final qm = ffi.qualityMonitorModel;
        final display = pi.tryGetDisplayIfNotAllDisplay();
        final res = display != null ? '${display.width}×${display.height}' : '';
        final codec = qm.data.codecFormat ?? '';
        final host = pi.hostname.isNotEmpty ? pi.hostname : pi.username;

        return IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xAA11141A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (host.isNotEmpty)
                  Text(
                    '$host · ${pi.platform}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                if (res.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(res,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
                if (codec.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(codec,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class UUMobileZoomHud extends StatelessWidget {
  final FFI ffi;
  final VoidCallback onClose;

  const UUMobileZoomHud({
    Key? key,
    required this.ffi,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ffi.canvasModel,
      builder: (context, _) {
        final canvas = ffi.canvasModel;
        final pct = canvas.currentZoomPercent;
        return Material(
          color: const Color(0xE6181B22),
          borderRadius: BorderRadius.circular(20),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 16, color: Colors.white),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      canvas.setZoomPercent((pct - 15).clamp(25, 400)),
                ),
                Text(
                  '$pct%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      canvas.setZoomPercent((pct + 15).clamp(25, 400)),
                ),
                const SizedBox(width: 4),
                _pillBtn(translate('Fit'), () => canvas.applyZoomPreset('fit')),
                const SizedBox(width: 4),
                _pillBtn('100%', () => canvas.applyZoomPreset('100')),
                const SizedBox(width: 4),
                _pillBtn(
                  canvas.locked
                      ? translate('Multi-touch')
                      : translate('2F Zoom'),
                  () => canvas.setLocked(!canvas.locked),
                  active: canvas.locked,
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClose,
                  child:
                      const Icon(Icons.close, size: 15, color: Colors.white60),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pillBtn(String text, VoidCallback onTap, {bool active = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? kUUOrange : const Color(0xFF2B303C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}

class UUMobileSessionDock extends StatelessWidget {
  final String id;
  final FFI ffi;
  final bool drawerOpen;
  final bool zoomHudOpen;
  final VoidCallback onToggleDrawer;
  final VoidCallback onToggleZoomHud;
  final VoidCallback onOpenKeyboard;
  final VoidCallback onToggleInputMode;
  final VoidCallback onDisconnect;
  final VoidCallback onCollapse;

  const UUMobileSessionDock({
    Key? key,
    required this.id,
    required this.ffi,
    required this.drawerOpen,
    required this.zoomHudOpen,
    required this.onToggleDrawer,
    required this.onToggleZoomHud,
    required this.onOpenKeyboard,
    required this.onToggleInputMode,
    required this.onDisconnect,
    required this.onCollapse,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(builder: (context, setDockState) {
      final audioDisabled = bind.sessionGetToggleOptionSync(
          sessionId: ffi.sessionId, arg: 'disable-audio');
      return Material(
        color: const Color(0xEA161920),
        borderRadius: BorderRadius.circular(24),
        elevation: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dockCircle(
                icon: Icons.zoom_in,
                active: zoomHudOpen,
                onTap: onToggleZoomHud,
              ),
              const SizedBox(width: 8),
              _dockCircle(
                icon: Icons.tune,
                active: drawerOpen,
                onTap: onToggleDrawer,
              ),
              const SizedBox(width: 8),
              Obx(() {
                final isNative = ffi.inputModel.mobileInputMode.value ==
                    kMobileInputNativeTouch;
                return _dockCircle(
                  icon: isNative ? Icons.touch_app : Icons.mouse,
                  active: isNative,
                  onTap: onToggleInputMode,
                );
              }),
              const SizedBox(width: 8),
              _dockCircle(
                icon: Icons.keyboard_outlined,
                onTap: onOpenKeyboard,
              ),
              const SizedBox(width: 8),
              _dockCircle(
                icon: Icons.folder_outlined,
                onTap: () =>
                    _connectSubFeature(context, id, ffi, isFileTransfer: true),
              ),
              const SizedBox(width: 8),
              _dockCircle(
                icon: audioDisabled
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
                onTap: () async {
                  await bind.sessionToggleOption(
                      sessionId: ffi.sessionId, value: 'disable-audio');
                  setDockState(() {});
                },
              ),
              const SizedBox(width: 8),
              _dockCircle(
                icon: Icons.power_settings_new,
                bgColor: kUURed,
                onTap: onDisconnect,
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onCollapse,
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 18, color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _dockCircle({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? bgColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: bgColor ?? (active ? kUUOrange : const Color(0xFF272B36)),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: Colors.white),
      ),
    );
  }
}

class UUDesktopTopBar extends StatelessWidget {
  final String id;
  final FFI ffi;
  final bool drawerOpen;
  final bool pinned;
  final VoidCallback onToggleDrawer;
  final VoidCallback onTogglePin;
  final VoidCallback onCollapse;
  final VoidCallback onDisconnect;
  final VoidCallback onShowShortcuts;

  const UUDesktopTopBar({
    Key? key,
    required this.id,
    required this.ffi,
    required this.drawerOpen,
    required this.pinned,
    required this.onToggleDrawer,
    required this.onTogglePin,
    required this.onCollapse,
    required this.onDisconnect,
    required this.onShowShortcuts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ffi.ffiModel,
        ffi.qualityMonitorModel,
        ffi.canvasModel,
      ]),
      builder: (context, _) {
        final pi = ffi.ffiModel.pi;
        final qm = ffi.qualityMonitorModel;
        final canvas = ffi.canvasModel;
        final title = pi.hostname.isNotEmpty ? pi.hostname : id;
        final delay = _formatDelay(qm.data.delay);
        final speed = _formatSpeed(qm.data.speed);
        final fps = '${_formatFps(qm.data.fps)}fps';

        return StatefulBuilder(builder: (context, setBarState) {
          final audioDisabled = bind.sessionGetToggleOptionSync(
              sessionId: ffi.sessionId, arg: 'disable-audio');
          return Material(
            color: const Color(0xF0171A21),
            elevation: 6,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 14,
                    width: 1,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.network_check, size: 14, color: kUUGreen),
                  const SizedBox(width: 6),
                  Text(
                    '$delay · $speed · $fps',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (pi.displays.length > 1 &&
                      pi.currentDisplay != kAllDisplayValue) ...[
                    const SizedBox(width: 12),
                    for (var i = 0; i < pi.displays.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () => openMonitorInTheSameTab(i, ffi, pi),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: pi.currentDisplay == i
                                  ? kUUOrange
                                  : const Color(0xFF272B36),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                  ],
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232732),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => canvas.setZoomPercent(
                              (canvas.currentZoomPercent - 15).clamp(25, 400)),
                          child: const Icon(Icons.remove,
                              size: 14, color: Colors.white70),
                        ),
                        InkWell(
                          onTap: () => canvas.applyZoomPreset(
                              canvas.viewStyle.style == kRemoteViewStyleAdaptive
                                  ? '100'
                                  : 'fit'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '${canvas.currentZoomPercent}%',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => canvas.setZoomPercent(
                              (canvas.currentZoomPercent + 15).clamp(25, 400)),
                          child: const Icon(Icons.add,
                              size: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _topBtn(
                    icon: Icons.tune,
                    label: translate('Settings'),
                    active: drawerOpen,
                    onTap: onToggleDrawer,
                  ),
                  _topBtn(
                    icon: Icons.folder_outlined,
                    label: translate('Files'),
                    onTap: () => _connectSubFeature(context, id, ffi,
                        isFileTransfer: true),
                  ),
                  _topBtn(
                    icon: Icons.terminal,
                    label: translate('Terminal'),
                    onTap: () =>
                        _connectSubFeature(context, id, ffi, isTerminal: true),
                  ),
                  _topBtn(
                    icon: Icons.keyboard_outlined,
                    label: translate('Shortcuts'),
                    onTap: onShowShortcuts,
                  ),
                  _topBtn(
                    icon: audioDisabled
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    label: translate('Audio'),
                    onTap: () async {
                      await bind.sessionToggleOption(
                          sessionId: ffi.sessionId, value: 'disable-audio');
                      setBarState(() {});
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 15,
                      color: pinned ? kUUOrange : Colors.white60,
                    ),
                    tooltip: translate('Pin'),
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: onTogglePin,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up,
                        size: 17, color: Colors.white60),
                    tooltip: translate('Hide'),
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: onCollapse,
                  ),
                  const SizedBox(width: 4),
                  _topBtn(
                    icon: Icons.power_settings_new,
                    label: translate('Disconnect'),
                    color: const Color(0xFFF87171),
                    onTap: onDisconnect,
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _topBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? color,
  }) {
    final c = color ?? (active ? kUUOrange : Colors.white70);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: c,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

class UUDesktopBottomTelemetry extends StatelessWidget {
  final FFI ffi;
  const UUDesktopBottomTelemetry({Key? key, required this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ffi.ffiModel, ffi.qualityMonitorModel]),
      builder: (context, _) {
        final d = ffi.ffiModel.pi.tryGetDisplayIfNotAllDisplay();
        final res = d != null ? '${d.width}×${d.height}' : '';
        final codec = ffi.qualityMonitorModel.data.codecFormat ?? '';
        final delay = _formatDelay(ffi.qualityMonitorModel.data.delay);
        if (res.isEmpty && codec.isEmpty) return const SizedBox.shrink();

        return IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xBB161920),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (res.isNotEmpty) _badge(res),
                if (codec.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _badge(codec),
                ],
                const SizedBox(width: 6),
                _badge(delay),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF232732),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}
