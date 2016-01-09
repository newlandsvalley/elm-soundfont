elm-soundfont
=============

This project explores the possibilities of playing MIDI directly in the browser within an Elm (0.16) application.  It uses three putative Elm libraries:

*   Elm-webmidi.  This library is a simple wrapper round [Web-MIDI](http://www.w3.org/TR/webmidi/) and provides signals of connection/disconnection of MIDI input devices and also of MIDI notes (for example whenever a key is pressed on a MIDI keyboard).  I doubt if I will ever now publish this as a 'blessed' Elm Community Package because of the moratorium on Native libraries and the lack of clarity about what the future might hold. Unfortunately, this code must be reproduced from [newlandsvalley/elm-webmidi](https://github.com/newlandsvalley/elm-webmidi) because linking seems difficult in any other manner.

*   Elm-comidi.  This is a parser for MIDI file images which uses the elm-combine parser combinator library and is now 'sanctified' as a community package. 

*   SoundFont.  This library is a simple native code wrapper around the essential features of the [soundfont-player](https://github.com/danigb/soundfont-player) from danigb. At the moment it chooses just one sound font - an acoustic grand piano - taken from Benjamin Gleitzman's package of [pre-rendered sound fonts](https://github.com/gleitz/midi-js-soundfonts). It provides a signal of Audio Buffers for each possible MIDI note and uses [Web-Audio](https://webaudio.github.io/web-audio-api/) to play the sounds. Much of this would eventually probably better written in pure Elm but the reliance on Web-Audio by means of some sort of native interface remains.

At the moment, the sample file players handle only Type-0 MIDI files but the intention is eventually to handle Type-1 and Type-2 as well.


Examples
--------

#### MIDI Keyboard

Main.elm in the examples/piano directory is a bare-bones application that plays notes that are detected from an attached MIDI keyboard.  It first loads the acoustic grand piano soundfont into a Dictionary of AudioBuffers (one for each note).  It then detects keyboard presses and plays the corresponding note using the Web-Audio API.  To build, use:

elm-make src/examples/piano/Main.elm --output=Main.html

#### MIDI File

Main.elm in the examples/simpleplayer directory is a simple MIDI file player (it plays a Swedish tune called 'Lillasystern').  It first loads the acoustic grand piano soundfont as before, loads and parses the MIDI file and converts this into a performance simply by accumulating the elapsed times of each 'NoteOn' event. It then converts each of these to a playable 'sound bite' attached to the appropriate soundfont and plays them as a single uninterruptable Task. The player can be used with any type of MIDI file, but for multi-track input only the first melody track will be played. To build use:

elm-make src/examples/simpleplayer/Main.elm --output=Main.html

#### MIDI Audio Controller

Main.elm in the examples/type0player directory is another MIDI file player. But here, the playback is controlled by means of start/pause/continue buttons in a half-finished CSS-styled player. The file must conform to MIDI type-0 (i.e. single track). To build use:

elm-make src/examples/type0player/Main.elm --output=Main.html


Issues
------

The sample tune has a tempo of 120 bpm which is what the simple player delivers. However, with the audio controller, the tempo slows to something closer to 110 bpm.  In other words, Elm's Tasks impose a significant burden on responsiveness.

I was hamstrung under Elm 0.15 by [this issue](https://github.com/elm-lang/core/issues/240) whenever I attempted to use Native Task.asyncFunction when the function implementation itself uses asynchronous javascript methods.  In consequence, I modeled all asynchronous interfaces as signals rather than tasks. This bug is now fixed in Elm 0.16, which in turn allows me to initialise connections to MIDI devices as a Task.  However I have (so far) retained the use of signals for loading soundfonts.

I think it is not yet possible to build a player for Type-1 files (multiple tracks played simultaneously) with Elm in its current state.  This is because we need concurrency primitives which can be used with the Task library.  See [this discussion](https://groups.google.com/forum/#!topic/elm-discuss/NDAYIAML438).







 




