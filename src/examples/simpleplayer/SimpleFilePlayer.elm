module SimpleFilePlayer where

import Effects exposing (Effects, task)
import Html exposing (..)
import Html.Events exposing (onClick)
import Http exposing (..)
import Task exposing (..)
import List exposing (..)
import Maybe exposing (..)
import String exposing (..)
import Result exposing (Result)
import Dict exposing (Dict)
import CoMidi exposing (MidiRecording, normalise, parse, translateRunningStatus)
import SoundFont exposing (..)
import MidiPerformance exposing (..)

-- MODEL

type alias Sounds = List (Task Effects.Never ())

type alias Model =
    { samples : Dict Int SoundSample
    , loaded : Bool
    , performance : Result String MidiPerformance
    }

init : String -> (Model, Effects Action)
init topic =
  ( { 
      samples = Dict.empty, 
      loaded = False, 
      performance = Err "not started"
    }
  , Effects.none
  )

-- UPDATE

type Action
    = NoOp   
    | LoadFont (Maybe SoundSample)
    | Midi (Result String MidiPerformance )
    | Play

update : Action -> Model -> (Model, Effects Action)
update action model =
  case action of
    NoOp -> (model, Effects.none )

    LoadFont mss ->
      case mss of
        Nothing ->
          (model, Effects.none)
        Just ss -> 
          case ss.name of
            "end" ->
               ({ model | loaded = True }, loadMidi "midi/lillasystern.midi" )
            _ -> 
              let pitch = toInt ss.name
              in
                ( { model | samples = Dict.insert pitch ss model.samples }, 
                  Effects.none
                )        

    Midi result ->  ( { model | performance = result }, Effects.none ) 

    Play -> (model, playSounds <| makeSounds model.samples model.performance)   


   
mToList : Maybe (List a) -> List a
mToList m = case m of
   Nothing -> []
   Just x -> x


{- load a MIDI file -}
loadMidi : String -> Effects Action
loadMidi url = 
      let settings =  { defaultSettings | desiredResponseType  = Just "text/plain; charset=x-user-defined" }   
        in
          Http.send settings
                          { verb = "GET"
                          , headers = []
                          , url = url
                          , body = empty
                          } 
          |> Task.toResult
          |> Task.map extractResponse
          |> Task.map parseLoadedFile
          |> Task.map Midi
          |> Effects.task

{- inspect the next performance event and generate the appropriate sound command 
   which is done by looking up the sound fonts.  We may also get a new Tempo
   indicator which requires us to reset the last tempo ready for further notes.
-}
nextSound : Int -> Dict Int SoundSample -> NoteEvent -> (Sounds, Float) -> (Sounds, Float)
nextSound ticksPerBeat samples ne acc = 
  let 
    (ticks, notable) = ne
    sounds = fst acc         
    microsecondsPerBeat = snd acc
  in
    case notable of
     -- shouldn't happen - just satisfies ADT
     NoNote ->        
       acc
     -- we've hit a Note
     Note pitch velocity ->
       let 
         elapsedTime = 
           microsecondsPerBeat * Basics.toFloat ticks / (Basics.toFloat ticksPerBeat  * 1000000)
         sample = 
           Dict.get pitch samples
         maxVelocity = 0x7F
         gain =
           Basics.toFloat velocity / maxVelocity
         soundBite = { mss = sample, time = elapsedTime, gain = gain }
         fn = maybePlay soundBite
       in
         (fn :: sounds,  microsecondsPerBeat)
     -- we've hit a new Tempo indicator to replace the last one
     MicrosecondsPerBeat ms ->
       (fst acc, Basics.toFloat ms)

{- make the sounds - if we have a performance result from parsing the midi file, convert
   the performance into a list of soundbites (aka Sounds)
-}
makeSounds :  Dict Int SoundSample -> Result String MidiPerformance -> Sounds 
makeSounds ss perfResult = 
     case perfResult of
       Ok perf ->
        let 
          fn = nextSound perf.ticksPerBeat ss
          defaultPace =  Basics.toFloat 500000
          line = perf.lines
                 |> List.head
                 |> withDefault []
        in
          List.foldl fn ([], defaultPace) line
          |> fst 
          |> List.reverse 
       Err err ->
         []

{- play the sounds as a single uninterruptible task -}
playSounds : Sounds -> Effects Action
playSounds sounds = 
      sequence sounds
      |> Task.map (\x -> NoOp)
      |> Effects.task


{- extract the true response, concentrating on 200 statuses - assume other statuses are in error
   (usually 404 not found)
-}
extractResponse : Result RawError Response -> Result String Value
extractResponse result = case result of
    Ok response -> case response.status of
        200 -> Ok response.value
        _ -> Err (toString (response.status) ++ ": " ++ response.statusText)
    Err e -> Err "unexpected http error"

{- cast a String to an Int -}
toInt : String -> Int
toInt = String.toInt >> Result.toMaybe >> Maybe.withDefault 0

toPerformance : Result String MidiRecording -> Result String MidiPerformance
toPerformance r = Result.map fromRecording r


parseLoadedFile : Result String Value -> Result String MidiPerformance
parseLoadedFile r = case r of
  Ok text -> case text of
    Text s -> s |> normalise |> parse |> translateRunningStatus |> toPerformance
    Blob b -> Err "Blob unsupported"
  Err e -> Err e

-- VIEW

viewPerformanceResult : Result String MidiPerformance -> String
viewPerformanceResult mr = case mr of
      Ok res -> "OK: " ++ (toString res)
      Err errs -> "Fail: " ++ (toString errs)


view : Signal.Address Action -> Model -> Html
view address model =
  div []
    [ 
      div [  ] [ text ("parsed midi result: " ++ (viewPerformanceResult model.performance)) ]
    , button [ onClick address Play ] [ text "play" ]
    ]

-- INPUTS

-- try to load the entire piano soundfont
pianoFonts : Signal (Maybe SoundSample)
pianoFonts = loadSoundFont  "acoustic_grand_piano"

signals : List (Signal Action)
signals = [Signal.map LoadFont pianoFonts]





