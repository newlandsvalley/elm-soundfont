elm-soundfont
=============

This project explores the possibilities of playing MIDI directly in the browser within an Elm (0.16) application.  It contains two putative Elm Native libraries:

*   Elm-WebMidi.  This library is a simple wrapper round [Web-MIDI](http://www.w3.org/TR/webmidi/) and provides signals of connection/disconnection of MIDI input devices and also of MIDI notes (for example whenever a key is pressed on a MIDI keyboard).  Unfortunately, this code is reproduced from [newlandsvalley/elm-WebMidi](https://github.com/newlandsvalley/elm-WebMidi) because it is not yet 'blessed' as an Elm Community Package and linking seems difficult in any other manner.

*   SoundFont.  This library is a simple wrapper around the essential features of the [soundfont-player](https://github.com/danigb/soundfont-player) from danigb. At the moment it chooses just one sound font - an acoustic grand piano - taken from Benjamin Gleitzman's package of [pre-rendered sound fonts](https://github.com/gleitz/midi-js-soundfonts). It provides a signal of Audio Buffers for each possible MIDI note.


Examples
--------

Main.elm in the examples/piano directory is a bare-bones application that plays notes that are detected from an attached MIDI keyboard.  It first loads the acoustic grand piano soundfont into a Dictionary of AudioBuffers (one for each note).  It then detects keyboard presses and plays the corresponsing note using the Web-Audio API.  To build, use:

elm-make src/examples/SoundFontSignal.elm --output=Main.html


Issues
------

I seem to be have been hamstrung under Elm 0.15 by [this issue](https://github.com/elm-lang/core/issues/240) whenever I attempted to use Native Task.asyncFunction when the function implementation itself uses asynchronous javascript methods.  In consequence, all asynchronous interfaces have been modeled as signals rather than tasks. 







 




