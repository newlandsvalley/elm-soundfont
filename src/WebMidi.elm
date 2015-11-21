module WebMidi 
   ( MidiConnect
   , MidiNote
   , MidiDisconnect
   , midiInputS
   , midiDisconnectS
   , midiNoteS
   , init
   ) where

{-|  Library for working with midi input devices,

# Definition

# Data Types
@docs MidiNote, MidiConnect, MidiDisconnect

# Signals
@docs midiInputS, midiNoteS, midiDisconnectS

# Functions
@docs init

-}

-- native WebMidi implementation
import Native.WebMidi
import Signal exposing (Signal)
import Task exposing (Task)

{-| Representation of a basic MIDI note message which indicates whether it is being switched on or off,
    the pitch, and the velocity (e.g. keyboard pressure).  (Velocity of 0 is synonymous with note off)
    sourceId is the identity of the owning input device that produced the note.
-}
type alias MidiNote =
  { noteOn    : Bool
  , pitch     : Int
  , velocity  : Int
  , timestamp : Int
  , sourceId  : String
  }

{-| A Midi Connection - could be used for both input and output devices but only inputs are currently supported -}
type alias MidiConnect =
  { portType     : String 
  , id           : String 
  , manufacturer : String 
  , name         : String 
  , version      : String 
  }

{-| A Midi Disconnection of a device previously connected -}
type alias MidiDisconnect =
  { portType     : String 
  , id           : String 
  }


{-| The midi note signal. 
    Generated, for example when a MIDI keyboard key is depressed or released. 
-}
midiNoteS: Signal MidiNote
midiNoteS =  
   Native.WebMidi.note

{-| The midi input connect signal. 
    Generated when a MIDI device is connected or when an Elm-WebMidi program starts up
    and there are already decices connected. 
-}
midiInputS: Signal MidiConnect
midiInputS =
   Native.WebMidi.connect

{-| The midi input disconnect signal. 
    Generated when a MIDI device is disconnected.
-}
midiDisconnectS: Signal MidiDisconnect
midiDisconnectS =
   Native.WebMidi.disconnect

{-| Initialise MIDI to set up the signals -}
init : Task x ()
init = Native.WebMidi.init () 



