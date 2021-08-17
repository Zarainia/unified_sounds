import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_vlc/dart_vlc.dart' as dart_vlc;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<dart_vlc.Media> media_from_bytes(String filename, Uint8List contents) async {
  // File memory_file = MemoryFileSystem().file(filename)..writeAsBytesSync(contents, flush: true);
  // return Media.file(memory_file);
  String temp_dir = (await getTemporaryDirectory()).path;
  File file = new File(p.join(temp_dir, filename));
  await file.writeAsBytes(contents);
  return dart_vlc.Media.file(file);
}

class BytesAudioSource extends just_audio.StreamAudioSource {
  Uint8List bytes;

  BytesAudioSource(this.bytes);

  @override
  Future<just_audio.StreamAudioResponse> request([int? start, int? end]) {
    start = start ?? 0;
    end = end ?? bytes.length;

    return Future.value(
      just_audio.StreamAudioResponse(
        sourceLength: bytes.length,
        contentLength: end - start,
        offset: start,
        contentType: 'audio/mpeg',
        stream: Stream.value(List<int>.from(bytes.skip(start).take(end - start))),
      ),
    );
  }
}

class AudioPlayerStatus {
  bool is_playing = false;
  bool is_completed = false;
  Duration? position;
  Duration? duration;
}

class AudioPlayer {
  static int _curr_dart_vlc_id = 2;
  static Uuid _uuid_provider = Uuid();

  bool is_desktop;
  int dart_vlc_id;
  dart_vlc.Player? desktop_player;
  dart_vlc.Media? curr_media;
  just_audio.AudioPlayer? other_player;
  Set<String> _temp_file_names = {};

  AudioPlayerStatus status = AudioPlayerStatus();
  Function(AudioPlayerStatus)? playback_callback;
  Function(AudioPlayerStatus)? position_callback;

  StreamSubscription? _desktop_playback_stream;
  StreamSubscription? _desktop_position_stream;
  StreamSubscription? _other_playback_stream;
  StreamSubscription? _other_position_stream;
  StreamSubscription? _other_duration_stream;

  static int _get_next_id() {
    return _curr_dart_vlc_id++;
  }

  AudioPlayer({bool multi_player = true})
      : is_desktop = (!kIsWeb && (Platform.isWindows || Platform.isLinux)),
        dart_vlc_id = multi_player ? _get_next_id() : 1 {
    if (is_desktop) {
      desktop_player = dart_vlc.Player(id: dart_vlc_id);
      _desktop_playback_stream = desktop_player!.playbackStream.listen((event) {
        status.is_playing = event.isPlaying;
        status.is_completed = event.isCompleted;
        playback_callback?.call(status);
        if (event.isCompleted) reset();
      });
      _desktop_position_stream = desktop_player!.positionStream.listen((event) {
        status.position = event.position;
        status.duration = event.duration;
        position_callback?.call(status);
      });
    } else {
      other_player = just_audio.AudioPlayer();
      _other_playback_stream = other_player!.playerStateStream.listen((event) {
        status.is_playing = event.playing;
        status.is_completed = event.processingState == just_audio.ProcessingState.completed;
        playback_callback?.call(status);
        if (status.is_completed) reset();
      });
      _other_position_stream = other_player!.positionStream.listen((event) {
        status.position = event;
        position_callback?.call(status);
      });
      _other_duration_stream = other_player!.durationStream.listen((event) {
        status.duration = event;
        position_callback?.call(status);
      });
    }
  }

  void load_file(String path) {
    curr_media = dart_vlc.Media.file(File(path));
    if (is_desktop)
      desktop_player!.open(curr_media!, autoStart: false);
    else
      other_player!.setFilePath(path);
  }

  void load_url(String url) {
    curr_media = dart_vlc.Media.network(url);
    if (is_desktop)
      desktop_player!.open(curr_media!, autoStart: false);
    else
      other_player!.setUrl(url);
  }

  void load_asset(String path) {
    curr_media = dart_vlc.Media.asset(path);
    if (is_desktop)
      desktop_player!.open(curr_media!, autoStart: false);
    else
      other_player!.setAsset(path);
  }

  void load_bytes(Uint8List bytes, String? name) {
    if (name == null) name = _uuid_provider.v1();
    if (is_desktop) {
      media_from_bytes(name, bytes).then((dart_vlc.Media new_media) {
        curr_media = new_media;
        desktop_player!.open(curr_media!, autoStart: false);
      });
      _temp_file_names.add(name);
    } else
      other_player!.setAudioSource(BytesAudioSource(bytes));
  }

  void play() {
    if (is_desktop)
      desktop_player!.play();
    else
      other_player!.play();
  }

  void pause() {
    if (is_desktop)
      desktop_player!.pause();
    else
      other_player!.pause();
  }

  void stop() {
    if (is_desktop)
      desktop_player!.stop();
    else
      other_player!.stop();
  }

  void play_or_pause() {
    if (is_desktop)
      desktop_player!.playOrPause();
    else {
      if (other_player!.playing)
        other_player!.pause();
      else
        other_player!.play();
    }
  }

  void seek(Duration position) {
    if (is_desktop)
      desktop_player!.seek(position);
    else
      other_player!.seek(position);
  }

  void reset() {
    if (is_desktop && curr_media != null) desktop_player!.open(curr_media!, autoStart: false);
    if (!is_desktop) {
      other_player!.pause();
      seek(Duration(milliseconds: 0));
    }
  }

  void dispose() async {
    stop();
    _desktop_playback_stream?.cancel();
    _desktop_position_stream?.cancel();
    desktop_player?.dispose();
    _other_playback_stream?.cancel();
    _other_position_stream?.cancel();
    _other_duration_stream?.cancel();
    other_player?.dispose();
    String temp_dir = (await getTemporaryDirectory()).path;
    for (var filename in _temp_file_names) {
      File file = File(p.join(temp_dir, filename));
      try {
        file.delete();
      } catch (e) {}
    }
  }
}
