# Audio Files Migration Note

## Action Required

The audio files in the `songs/` folder need to be converted from MP3 to WAV format for compatibility with `System.Media.SoundPlayer`.

### Current files:
- click.mp3
- notif.mp3

### Required files:
- click.wav
- notif.wav

### Conversion Instructions:

**Option 1: Using FFmpeg (recommended)**
```powershell
ffmpeg -i click.mp3 -acodec pcm_s16le -ar 44100 click.wav
ffmpeg -i notif.mp3 -acodec pcm_s16le -ar 44100 notif.wav
```

**Option 2: Using online converters**
- Visit https://cloudconvert.com/mp3-to-wav
- Upload each MP3 file and download the WAV version

**Option 3: Using Windows Media Player**
1. Open file in Windows Media Player
2. Go to File > Save As
3. Choose WAV format

### Note:
The code has been updated to reference .wav files. The .mp3 files can be deleted once the .wav files are in place.
