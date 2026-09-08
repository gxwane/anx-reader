import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class TtsFab extends StatefulWidget {
  const TtsFab({
    super.key,
    this.epubPlayerKey,
    this.decoupledNotifierForTest,
    this.onReturnToVoiceForTest,
  });

  final GlobalKey<EpubPlayerState>? epubPlayerKey;
  final ValueNotifier<bool>? decoupledNotifierForTest;
  final Future<void> Function()? onReturnToVoiceForTest;

  @override
  State<TtsFab> createState() => _TtsFabState();
}

class _TtsFabState extends State<TtsFab> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _collapse() {
    if (_isExpanded) {
      setState(() {
        _isExpanded = false;
        _animationController.reverse();
      });
    }
  }

  Future<void> _handleReturnToVoice() async {
    if (widget.onReturnToVoiceForTest != null) {
      await widget.onReturnToVoiceForTest!();
      return;
    }
    final playerState = widget.epubPlayerKey?.currentState;
    if (playerState != null) {
      await playerState.ttsResumeFollow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = widget.epubPlayerKey?.currentState;
    final decoupledNotifier = widget.decoupledNotifierForTest ??
        playerState?.isTtsViewportDecoupledNotifier;

    return ValueListenableBuilder<TtsStateEnum>(
      valueListenable: TtsHandler().ttsStateNotifier,
      builder: (context, ttsState, _) {
        final isPlaying = ttsState == TtsStateEnum.playing;
        final ttsActive =
            ttsState == TtsStateEnum.playing || ttsState == TtsStateEnum.paused;

        // Collapse when TTS stops, but keep widget alive so State is preserved
        // during brief stopped transitions (e.g. between sentences).
        if (ttsState == TtsStateEnum.stopped) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _collapse());
        }

        Widget buildFabRow(bool isDecoupled) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Expanded action buttons (slide in from right, appear to left of main FAB)
              AnimatedBuilder(
                animation: _expandAnimation,
                builder: (context, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.centerRight,
                      widthFactor: _expandAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilledContainer(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6.0, vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            icon: EvaIcons.chevron_left,
                            onPressed: () {
                              TtsHandler().playPrevious();
                            },
                          ),
                          _ActionButton(
                            icon: isPlaying
                                ? EvaIcons.pause_circle_outline
                                : EvaIcons.play_circle_outline,
                            onPressed: () {
                              if (isPlaying) {
                                audioHandler.pause();
                              } else {
                                audioHandler.play();
                              }
                            },
                          ),
                          _ActionButton(
                            icon: EvaIcons.chevron_right,
                            onPressed: () {
                              TtsHandler().playNext();
                            },
                          ),
                          _ActionButton(
                            icon: EvaIcons.stop_circle_outline,
                            onPressed: () {
                              audioHandler.stop();
                              _collapse();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Morphing Pill-FAB:
              // When decoupled: morphs into [🎯 回朗读处] pill
              // When coupled: stays compact 40dp circular FAB
              _buildMainFab(
                context,
                isPlaying: isPlaying,
                isDecoupled: isDecoupled,
              ),
            ],
          );
        }

        final content = decoupledNotifier != null
            ? ValueListenableBuilder<bool>(
                valueListenable: decoupledNotifier,
                builder: (context, isDecoupled, _) =>
                    buildFabRow(isDecoupled),
              )
            : buildFabRow(false);

        return AnimatedOpacity(
          opacity: ttsActive ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !ttsActive,
            child: PointerInterceptor(child: content),
          ),
        );
      },
    );
  }

  Widget _buildMainFab(
    BuildContext context, {
    required bool isPlaying,
    required bool isDecoupled,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // If controls are expanded, show close toggle
    if (_isExpanded) {
      return FloatingActionButton(
        key: const ValueKey('tts-fab-close'),
        heroTag: null,
        mini: true,
        onPressed: _toggleExpanded,
        elevation: 4,
        child: const Icon(
          Icons.close,
          size: 20,
        ),
      );
    }

    // When decoupled, morph into a Pill FAB with return action
    if (isDecoupled) {
      return Material(
        key: const ValueKey('tts-fab-decoupled-pill'),
        color: colorScheme.primaryContainer,
        elevation: 4,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _handleReturnToVoice,
          onLongPress: _toggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  L10n.of(context).ttsReturnToVoice,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Default coupled mini FAB
    return FloatingActionButton(
      key: const ValueKey('tts-fab-main'),
      heroTag: null,
      mini: true,
      onPressed: _toggleExpanded,
      elevation: 4,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isPlaying
              ? EvaIcons.pause_circle_outline
              : EvaIcons.play_circle_outline,
          key: ValueKey(isPlaying),
          size: 20,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      onPressed: onPressed,
      splashRadius: 20,
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}
