module PianoPlayer where

import Effects exposing (Effects, task)
import Html exposing (..)
import Task exposing (..)
import List exposing (..)
import Maybe exposing (..)
import String exposing (..)
import SoundFont exposing (..)
import Dict exposing (Dict)
import WebMidi exposing (..)

-- MODEL

type alias Model =
    { samples : Dict Int SoundSample
    , loaded : Bool
    }

init : String -> (Model, Effects Action)
init topic =
  ( {samples = Dict.empty, loaded = False }
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
               ({ samples = model.samples, loaded = True },  connectMidiDevices)
            _ -> 
              let pitch = toInt ss.name
              in
                ( { samples = Dict.insert pitch ss model.samples, loaded = model.loaded }, 
                  Effects.none
                )        
   
    Play note ->  (model, playNote note model.samples )
  
   

showSample : Model -> String
showSample m =
   case Dict.isEmpty m.samples of
     True ->  "nothing"
     False -> (Dict.keys m.samples)
              |> toString


playNote : MidiNote -> Dict Int SoundSample -> Effects Action
playNote note samples =       
    let n = Dict.get note.pitch samples  
        np = SoundBite n 0
    in
       maybePlay np
      |> Task.map (\x -> NoOp)
      |> Effects.task

{- Fails with annoying stepTask bug if init implemented in JS -}
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

startMessage : Bool -> String
startMessage ready =
   if (ready) then "Now you can attach your MIDI keyboard and play it" else ""

view : Signal.Address Action -> Model -> Html
view address model =
  div []
    [ 
      div [  ] [ text ("loaded soundfonts for midi notes: " ++ showSample model) ],
      div [  ] [ text (startMessage model.loaded) ]
    ]

-- INPUTS
defaultNote : MidiNote
defaultNote = MidiNote False 0 0 0 ""

-- try to load the entire piano soundfont
pianoFonts : Signal (Maybe SoundSample)
pianoFonts = loadSoundFont  "acoustic_grand_piano"

pianoNotes : Signal MidiNote
pianoNotes = WebMidi.midiNoteS
          |> Signal.filter (\n -> n.noteOn) defaultNote

signals : List (Signal Action)
signals = [Signal.map Load pianoFonts, Signal.map Play pianoNotes]


