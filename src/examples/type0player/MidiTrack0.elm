module MidiTrack0 ( MidiTrack0
                   , fromRecording) where

{-|  conversion of a MIDI recording to a performance of just Track 0

# Definition

# Data Types
@docs MidiTrack0

# Functions
@docs fromRecording

-}

import CoMidi exposing (..)
import Array exposing (Array, fromList)
import Maybe exposing (withDefault)

{-| Midi Track0 -}
type alias MidiTrack0 = 
    { ticksPerBeat : Int
    , messages : Array MidiMessage
    }

{-| translate a MIDI recording of track 0 to a MidiTrack0 description -}
fromRecording : MidiRecording -> MidiTrack0
fromRecording mr = 
   let 
      header = fst mr
      tracks = snd mr
      track0 = List.head tracks 
                |> withDefault []
                |> Array.fromList
   in 
      { ticksPerBeat = header.ticksPerBeat, messages = track0 }

