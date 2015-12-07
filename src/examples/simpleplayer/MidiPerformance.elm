module MidiPerformance ( Notable (..)
                       , NoteEvent
                       , MidiPerformance
                       , fromRecording) where

{-|  conversion of a MIDI recording to a performance

# Definition

# Data Types
@docs Notable, NoteEvent,  MidiPerformance

# Functions
@docs fromRecording

-}

import CoMidi exposing (..)

type alias AccumulatedTime = Int

{-| Note -}
{-
type alias Note = 
   { pitch : Int
   , velocity : Int
   }
-}

{-| Note descriptions we need to keep-}
type Notable =  MicrosecondsPerBeat Int
              | Note Int Int
              | NoNote

{-| Midi Message -}    
type alias NoteEvent = (AccumulatedTime, Notable)

{-| Midi Performance -}
type alias MidiPerformance = 
    { ticksPerBeat : Int
    , events : List NoteEvent
    }

{-| translate a MIDI recording to a simple performance -}
fromRecording : MidiRecording -> MidiPerformance
fromRecording mr = 
   let 
      events = List.map eventToNotable <| List.concat <| List.map accumulateTimes <| snd mr
      header = fst mr
   in 
      { ticksPerBeat = header.ticksPerBeat, events = events }

{- translate a timed MidiEvent to a timed Notable -}
eventToNotable : (Int, MidiEvent) -> (Int, Notable)
eventToNotable (t,e) = case e of 
                    NoteOn chanel pitch velocity -> (t, Note pitch velocity)
                    Tempo x -> (t, MicrosecondsPerBeat x)
                    _ -> (t, NoNote)

{- filter so we only have Tempo and NoteOn messages -}
filterEvents : Track -> Track
filterEvents = List.filter (\(t, e) -> case e of
                                NoteOn _ _ _ -> True
                                Tempo _ -> True
                                _ -> False
                            )

{- keep a running total of accumulated ticks -}
accum : MidiMessage -> List MidiMessage -> List MidiMessage 
accum nxt acc = let at = case acc of 
                      [] -> 0
                      x :: xs -> fst x
                    nt = fst nxt
                    nv = snd nxt
                 in
                    (at + nt, nv) :: acc

{-| accumulate the timings and leave only Tempo and NoteOn messages -}
accumulateTimes : Track -> Track
accumulateTimes = filterEvents << List.reverse << List.foldl accum [] 
