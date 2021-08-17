import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'sounds.dart';

Duration _duration_clamp(Duration duration, Duration min, Duration max) {
  if (duration < min) return min;
  if (duration > max) return max;
  return duration;
}

KeyEventResult _control_sound_via_keyboard(RawKeyEvent event, AudioPlayer sound_player) {
  print("pressed");
  if (event.isKeyPressed(LogicalKeyboardKey.space)) {
    sound_player.play_or_pause();
    return KeyEventResult.handled;
  }
  var position = sound_player.status.position;
  var duration = sound_player.status.duration;
  if (position != null && duration != null) {
    if (event.isKeyPressed(LogicalKeyboardKey.arrowLeft))
      sound_player.seek(_duration_clamp(position - Duration(seconds: 10), Duration.zero, duration));
    else if (event.isKeyPressed(LogicalKeyboardKey.arrowRight)) sound_player.seek(_duration_clamp(position + Duration(seconds: 10), Duration.zero, duration));
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

class PlaybackControls extends StatelessWidget {
  AnimationController animation_controller;
  AudioPlayer sound_player;
  double play_icon_size;
  VoidCallback? on_click;

  PlaybackControls({required this.animation_controller, required this.sound_player, this.play_icon_size = 35, this.on_click});

  @override
  Widget build(BuildContext context) {
    var themedata = Theme.of(context);

    return Row(
      children: [
        ElevatedButton(
          child: AnimatedIcon(
            icon: AnimatedIcons.pause_play,
            progress: animation_controller,
            color: themedata.colorScheme.onPrimary,
            size: play_icon_size,
          ),
          style: ElevatedButton.styleFrom(primary: themedata.primaryColor, shape: CircleBorder(), padding: EdgeInsets.all(15)),
          onPressed: () {
            sound_player.play_or_pause();
            on_click?.call();
          },
        ),
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }
}

class PlaybackSlider extends StatelessWidget {
  static NumberFormat seconds_formatter = NumberFormat('00');

  AudioPlayer sound_player;
  Duration playback_position;
  Duration playback_limit;
  Function(double new_position)? on_change;
  Color? position_colour;

  PlaybackSlider({required this.sound_player, required this.playback_position, required this.playback_limit, this.on_change, this.position_colour});

  static String format_duration(Duration duration) {
    return "${duration.inMinutes.remainder(60)}:${seconds_formatter.format(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    var position_text_style = TextStyle(color: position_colour);

    return Row(
      children: [
        Text(format_duration(playback_position), style: position_text_style),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(showValueIndicator: ShowValueIndicator.always),
            child: Slider(
              min: 0,
              max: playback_limit.inMilliseconds.toDouble(),
              value: playback_position.inMilliseconds.toDouble().clamp(0, playback_limit.inMilliseconds.toDouble()),
              onChanged: (double new_position) {
                this.on_change?.call(new_position);
                sound_player.seek(Duration(milliseconds: new_position.toInt()));
              },
              label: format_duration(playback_position),
            ),
          ),
        ),
        Text(format_duration(playback_limit), style: position_text_style)
      ],
    );
  }
}

class DisplaySoundPlayer extends StatefulWidget {
  String name;
  Uint8List contents;
  Widget display_widget;
  Color shadow_colour;
  Color position_colour;

  DisplaySoundPlayer({required this.name, required this.contents, required this.display_widget, this.shadow_colour = Colors.grey, this.position_colour = Colors.white});

  @override
  _DisplaySoundPlayerState createState() => _DisplaySoundPlayerState();
}

class _DisplaySoundPlayerState extends State<DisplaySoundPlayer> with TickerProviderStateMixin {
  late AudioPlayer sound_player;
  Duration playback_position = Duration();
  Duration playback_limit = Duration();
  late AnimationController button_animation_controller;

  @override
  void initState() {
    sound_player = AudioPlayer();
    sound_player.load_bytes(widget.contents, widget.name);
    sound_player.position_callback = (status) {
      setState(() {
        if (status.position != null) playback_position = status.position!;
        if (status.duration != null) playback_limit = status.duration!;
      });
    };
    sound_player.playback_callback = (status) {
      button_animation_controller.animateTo(status.is_playing ? 0 : 1);
    };
    button_animation_controller = AnimationController(vsync: this, duration: Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    super.dispose();
    sound_player.dispose();
    button_animation_controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
        child: Stack(
          children: [
            SizedBox.expand(
              child: widget.display_widget,
            ),
            Positioned(
              child: Stack(
                children: [
                  Column(
                    children: [
                      SizedBox(height: 25),
                      Container(
                        child: PlaybackSlider(
                          sound_player: sound_player,
                          playback_limit: playback_limit,
                          playback_position: playback_position,
                          on_change: (double new_position) {
                            setState(() {
                              playback_position = Duration(milliseconds: new_position.toInt());
                            });
                          },
                          position_colour: widget.position_colour,
                        ),
                        padding: EdgeInsets.only(top: 20, left: 10, right: 10),
                        color: widget.shadow_colour,
                      ),
                    ],
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  ),
                  PlaybackControls(
                    animation_controller: button_animation_controller,
                    sound_player: sound_player,
                  ),
                ],
                clipBehavior: Clip.none,
              ),
              bottom: 0,
              left: 0,
              right: 0,
            ),
          ],
        ),
        autofocus: true,
        onKey: (_, event) => _control_sound_via_keyboard(event, sound_player));
  }
}

class SimpleSoundPlayer extends StatefulWidget {
  String name;
  Uint8List contents;
  Color? position_colour;
  Color? focused_colour;

  SimpleSoundPlayer({required this.name, required this.contents, this.position_colour, this.focused_colour});

  @override
  _SimpleSoundPlayerState createState() => _SimpleSoundPlayerState();
}

class _SimpleSoundPlayerState extends State<SimpleSoundPlayer> with TickerProviderStateMixin {
  late AudioPlayer sound_player;
  Duration playback_position = Duration();
  Duration playback_limit = Duration();
  late AnimationController button_animation_controller;
  bool focused = false;
  late FocusScopeNode focus_node;

  @override
  void initState() {
    sound_player = AudioPlayer();
    sound_player.load_bytes(widget.contents, widget.name);
    sound_player.position_callback = (status) {
      setState(() {
        playback_position = status.position!;
        playback_limit = status.duration!;
      });
    };
    sound_player.playback_callback = (status) {
      button_animation_controller.animateTo(status.is_playing ? 0 : 1);
    };
    button_animation_controller = AnimationController(vsync: this, duration: Duration(milliseconds: 500));
    focus_node = FocusScopeNode();
  }

  @override
  void dispose() {
    super.dispose();
    sound_player.dispose();
    button_animation_controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Card(
        child: InkWell(
          child: Container(
            child: Column(
              children: [
                PlaybackControls(
                  animation_controller: button_animation_controller,
                  sound_player: sound_player,
                  play_icon_size: 30,
                  on_click: () {
                    Future.delayed(const Duration(milliseconds: 50), () {
                      focus_node.requestFocus();
                    });
                  },
                ),
                PlaybackSlider(
                  sound_player: sound_player,
                  playback_limit: playback_limit,
                  playback_position: playback_position,
                  on_change: (double new_position) {
                    setState(() {
                      playback_position = Duration(milliseconds: new_position.toInt());
                    });
                  },
                  position_colour: widget.position_colour,
                ),
              ],
            ),
            constraints: BoxConstraints(maxWidth: 300),
            padding: EdgeInsets.only(top: 10, left: 10, right: 10),
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 50), () {
              focus_node.requestFocus();
            });
          },
          excludeFromSemantics: true,
        ),
        color: focused ? widget.focused_colour : null,
      ),
      node: focus_node,
      onKey: (_, event) => _control_sound_via_keyboard(event, sound_player),
      onFocusChange: (now_focused) {
        setState(() {
          focused = now_focused;
        });
      },
    );
  }
}
