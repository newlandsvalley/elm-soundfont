module PianoPlayer where

import Effects exposing (Effects, task)
import Html exposing (..)
import Task exposing (..)
import List exposing (..)
import Maybe exposing (..)
import String exposing (..)
import Dict exposing (Dict)
import SoundFont exposing (..)
import WebMidi exposing (..)

-- MODEL

type alias Model =
    { samples : Dict Int SoundSample
    , loaded : Bool
    , maybeContext : Maybe AudioContext
    }

init : String -> (Model, Effects Action)
init topic =
  ( {samples = Dict.empty, loaded = False, maybeContext = Nothing }
  , Effects.none
  )

-- UPDATE

type Action
    = NoOp
    | Load (Maybe SoundSample)
    | Play MidiNote

update : Action -> Model -> (Model, Effects Action)
update action model =
  case action of
    NoOp -> (model, Effects.none )

    Load mss ->
      case mss of
        Nothing ->
          (model, Effects.none)
        Just ss -> 
          case ss.name of
            "end" ->
               (finaliseModel model,  connectMidiDevices)
            _ -> 
              let 
                pitch = toInt ss.name
              in
                ( {model |  samples = Dict.insert pitch ss model.samples }, 
                  Effects.none
                )        
   
    Play note ->  (model, playNote model.maybeContext note model.samples )

{- finalise the model by setting the audio context -}
finaliseModel : Model -> Model
finaliseModel m =
  let
    ctx = 
      if (isWebAudioEnabled) then
        Just getAudioContext
      else
        Nothing
  in
    { m | maybeContext = ctx, loaded = True }


playNote : Maybe AudioContext -> MidiNote -> Dict Int SoundSample -> Effects Action
playNote mctx note samples =       
    let n = Dict.get note.pitch samples  
        maxVelocity = 0x7F
        gain =
          Basics.toFloat note.velocity / maxVelocity
        np = SoundBite n 0 gain
    in
      case mctx of
        Just ctx ->
          maybePlay ctx np
           |> Task.map (\x -> NoOp)
           |> Effects.task
        _ -> 
          Effects.none

{- inistialise any connected MIDI devices -}
connectMidiDevices : Effects Action
connectMidiDevices = 
      WebMidi.init
      |> Task.map (\x -> NoOp)
      |> Effects.task

{- cast a String to an Int -}
toInt : String -> Int
toInt = String.toInt >> Result.toMaybe >> Maybe.withDefault 0

-- VIEW

(=>) = (,)

-- show the highest numbered soundfont so far loaded
showSample : Model -> String
showSample m =
   case Dict.isEmpty m.samples of
     True ->  "nothing"
     False -> (Dict.keys m.samples)
              |> maximum              
              |> withDefault 0
              |> toString

startMessage : Bool -> String
startMessage ready =
   if (ready) then "Now you can attach your MIDI keyboard and play it" else ""

view : Signal.Address Action -> Model -> Html
view address model =
  div []
    [ 
      div [  ] [ text ("loaded soundfont for midi note: " ++ showSample model) ],
      div [  ] [ text (startMessage model.loaded) ]
    ]

-- INPUTS

defaultNote : MidiNote
defaultNote = MidiNote False 0 0 0 ""

-- try to load the entire piano soundfont
pianoFonts : Signal (Maybe SoundSample)
pianoFonts = loadSoundFont getAudioContext "acoustic_grand_piano"

-- MIDI notes from the keyboard
pianoNotes : Signal MidiNote
pianoNotes = WebMidi.midiNoteS
          |> Signal.filter (\n -> n.noteOn) defaultNote

signals : List (Signal Action)
signals = [Signal.map Load pianoFonts, Signal.map Play pianoNotes]


