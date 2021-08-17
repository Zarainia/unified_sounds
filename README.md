# unified_sounds

 Very simple unified API for playing audio on all platforms in Flutter. Uses `dart_vlc` for Windows/Linux and `just_audio` for other platforms. Should in theory work on all the platforms, though I have only tested on Windows and Android. 

## Usage

Create audio player and play sounds: 

```dart
var sound_player = AudioPlayer();
sound_player.load_file(path);
sound_player.play()
```

Also supports seeking, loading from various places. When on Windows/Linux, a temporary file is used for loading from bytes, and is deleted when the player is disposed. 

Callbacks are available for status, and position:

```dart
sound_player.position_callback = (status) {
  setState(() {
    if (status.position != null) playback_position = status.position!;
    if (status.duration != null) playback_limit = status.duration!;
  });
};
```

A couple of simple widgets (`SimpleSoundPlayer` and `DisplaySoundPlayer`) are available and the code for them provide examples on how to use it. 
