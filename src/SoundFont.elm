module SoundFont
    (  SoundSample
      ,SoundBite
      ,loadSoundFont
      ,getCurrentTime
      ,maybePlay
    ) where

{-|  Library for working with the WebAudio API using SoundFonts,

# Definition

# Data Types
@docs SoundSample, SoundBite

# Functions
@docs loadSoundFont, getCurrentTime, maybePlay

-}

import Native.SoundFont
import Task exposing (Task, andThen, mapError, succeed)
import Http exposing (..)
import Maybe exposing (Maybe)

{-| Bobs redefined -}
type Blob = Blob

{-| AudioBuffers -}
type AudioBuffer = AudioBuffer

{-| Sound Samples -}
type alias SoundSample =
  { name   : String
   ,buffer : AudioBuffer
  }

{-| Sound Bites -}
type alias SoundBite =
  { mss  : Maybe SoundSample
   ,time : Float
  }


{-| Load an Audio Buffer Sound Sample from a URL -}
loadSoundFont: String -> Signal (Maybe SoundSample)
loadSoundFont name =  Native.SoundFont.loadSoundFont name


{-| Get the ausio context's current time -}
getCurrentTime : () -> Float
getCurrentTime = Native.SoundFont.getCurrentTime


{-| play an optional sound sample (if it's there) -}
maybePlay : SoundBite -> Task x ()
maybePlay sb =
    case sb.mss of 
      Nothing ->
         succeed ()
      Just ss -> 
         Native.SoundFont.play ss.buffer (getCurrentTime() + sb.time)
