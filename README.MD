# NyanCat for PC/XT CGA
Nyancat (Pop Tart Cat) animation on a PC/XT 8088 @ 4.77mhz, with CGA graphics and PC speaker audio, fits into a 360k 5.25" floppy.
## Features
* 12-frame animation cycling at ~14 fps (70ms per frame)
* 160x100x16 color mode
* 8 kHz audio playback
## System requirements
* DOS 2.0 or higher
* CGA or a compatible clone graphic adapter installed
* ~340k free RAM
## Build
- For audio, buy yourself a good nyan from [daniwellP](https://aidn.jp/sound/), or hum a nyan song yourself. And then process it with something like:
``ffmpeg -i input.wav -ss 4.96 -t 34.52 -f u8 -acodec pcm_u8 -ar 8000 -ac 1 NYAN.RAW``
- As for the executable,
``nasm -f bin NYANCAXT.ASM -o NYANCAXT.COM``

Put the `NYAN.RAW` along with `NYANCAXT.COM` and you can now enjoy Nyancat on a XT.
## Hardware issues
If you're using a XT clone, ensure that your XT clone is not equipped with a piezoelectric speaker. Otherwise, the audio playback will generate a sharp, 8 kHz carrier wave noise.

This program was successfully tested on 86Box, DOSBox and MartyPC, and the high-frequency carrier wave was "emulated" on the latter two.
## References
The original source of the Pop Tart Cat animation is
[prguitarman](http://www.prguitarman.com/index.php?id=348).
