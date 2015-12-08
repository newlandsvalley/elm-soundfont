module MidiController where

{-
  Proof of concept of a MIDI audio controller

  This allows buttons of start/pause/continue/reset

  in order to contol the playing of the MIDI file
  (again played by means of soundfonts and Web-Audio)

-}

import Effects exposing (Effects, task)
import Html exposing (..)
import Html.Events exposing (onClick)
import Http exposing (..)
import Task exposing (..)
import List exposing (..)
import Array exposing (get)
import Maybe exposing (Maybe)
import String exposing (..)
import Result exposing (Result)
import Dict exposing (Dict)
import CoMidi exposing (MidiRecording, MidiEvent(..), normalise, parse)
import SoundFont exposing (..)
import MidiTrack0 exposing (..)

-- MODEL

--  a delta time measured in milliseconds and a MIDI event
type alias SoundEvent = 
   { deltaTime: Float
   , event : MidiEvent
   }

-- the current state of the playback 
type alias PlaybackState =
   { index : Int
   , microsecondsPerBeat : Float
   , playing : Bool
   }

type alias Model =
    { samples : Dict Int SoundSample
    , loaded : Bool
    , track0 : Result String MidiTrack0
    , playbackState : PlaybackState
    }

init : String -> (Model, Effects Action)
init topic =
  ( { 
      samples = Dict.empty
    , loaded = False 
    , track0 = Err "not started"
    , playbackState = { index = 0 
                      , microsecondsPerBeat = Basics.toFloat 500000
                      , playing = False 
                      }
    }
  , Effects.none
  )

-- UPDATE

type Action
    = NoOp   
    | LoadFont (Maybe SoundSample)
    | Midi (Result String MidiTrack0 )
    | Play PlaybackState
    -- controller actions
    | Start
    | Stop
    | MoveTo Int

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

    Midi result ->  ( { model | track0 = result }, Effects.none ) 

    Start ->
        -- rather roundabout way of chaining the next action when we have no real Task associated
        let 
           state =  model.playbackState 
           newState = { state | playing = True }
           newModel = { model | playbackState = newState }
           effect = Task.succeed (Play newState)
                    |> Effects.task
        in        
          (newModel, effect)

    Stop ->   
       let  
         state =  model.playbackState 
         newState = { state | playing = False }
         newModel = { model | playbackState = newState }
       in
         (newModel, Effects.none)  

    MoveTo index ->
        let 
           state =  model.playbackState 
           newState = { state | playing = False, index=index }
           newModel = { model | playbackState = newState }
        in        
          (newModel, Effects.none)

       

    Play playbackState -> 
       -- check to ensure that the UI hasn't issued a stop command
       if  model.playbackState.playing then
         let 
           event = nextEvent playbackState model.track0
           nextAction = interpretSoundEvent event playbackState model.samples
           -- get the new state from the result of the last sound we've played
           newModel = { model | playbackState = playbackState }
         in
           (newModel, nextAction)    
       -- otherwise stop    
       else
         (model, Effects.none )
   
   
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


{- get the next event - if we have a recording result from parsing the midi file, convert
   the next indexed midi event to a delayed action (perhaps a NoteOn sound)
-}
nextEvent :  PlaybackState -> Result String MidiTrack0 -> SoundEvent
nextEvent state track0Result = 
     case track0Result of
       Ok track0 ->
        let 
          maybeNextMessage = track0.messages
                             |> Array.get state.index
          nextMessage = Maybe.withDefault (0, TrackEnd) maybeNextMessage
          nextEvent = snd nextMessage     
          -- work out the interval to the next note in milliseconds       
          deltaTime = fst nextMessage * state.microsecondsPerBeat  / (Basics.toFloat track0.ticksPerBeat  * 1000)
        in
          { deltaTime = deltaTime, event = nextEvent }
       Err err ->
          { deltaTime = 0.0, event = TrackEnd }

{- interpret the sound event - delay for the specified time and play the note if it's a NoteOn event -}
interpretSoundEvent : SoundEvent -> PlaybackState -> Dict Int SoundSample -> Effects Action
interpretSoundEvent soundEvent state ss = 
      (Task.sleep soundEvent.deltaTime 
        `andThen` \_ -> playEvent soundEvent state ss)
      |> Task.map (\s -> 
         if s.playing then Play s else NoOp)
      |> Effects.task

{- step through the state, and play the note if it's a NoteOn message -}
playEvent : SoundEvent -> PlaybackState -> Dict Int SoundSample -> Task x PlaybackState 
playEvent soundEvent state samples = 
  if state.playing then
    case soundEvent.event of
      TrackEnd ->
        succeed { state | playing = False }
      Tempo t -> 
        succeed { state | microsecondsPerBeat = Basics.toFloat t, index = state.index + 1}
      NoteOn channel pitch velocity ->
        let
          newstate = 
           { state | index = state.index + 1}
          sample = 
           Dict.get pitch samples
          soundBite = 
           { mss = sample, time = 0.0 }
        in
          Task.map (\_ -> newstate) <| maybePlay soundBite
      _  -> 
        succeed { state | index = state.index + 1}
   else
     succeed state


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

toTrack0 : Result String MidiRecording -> Result String MidiTrack0
toTrack0 r = Result.map fromRecording r


parseLoadedFile : Result String Value -> Result String MidiTrack0
parseLoadedFile r = case r of
  Ok text -> case text of
    Http.Text s -> s |> normalise |> parse |> toTrack0
    Blob b -> Err "Blob unsupported"
  Err e -> Err e

-- VIEW

viewRecordingResult : Result String MidiTrack0 -> String
viewRecordingResult mr = 
   case mr of
      Ok res -> 
         "OK: " ++ (toString res)
      Err errs -> 
         "Fail: " ++ (toString errs)

{-
view : Signal.Address Action -> Model -> Html
view address model =
  div []
    [ 
      div [  ] [ text ("parsed midi result: " ++ (viewRecordingResult model.track0)) ]
    , button [ onClick address (Start) ] [ text "start" ]
    , button [ onClick address (Stop) ] [ text "pause" ]
    , button [ onClick address (MoveTo 0) ] [ text "reset" ]
    ]
-}

view : Signal.Address Action -> Model -> Html
view address model =
  div [] (buttons address model)
    
    

buttons : Signal.Address Action -> Model -> List Html
buttons address model =
  case model.playbackState.playing of
    True -> 
      [ button [ onClick address (Stop) ] [ text "pause" ]
      , button [ onClick address (MoveTo 0) ] [ text "reset" ]
      ]
    False -> 
      let buttonText =
        case model.playbackState.index of
          0 -> "start"
          _ -> "continue"
      in
        [ button [ onClick address (Start) ] [ text buttonText ] ]

-- INPUTS

-- try to load the entire piano soundfont
pianoFonts : Signal (Maybe SoundSample)
pianoFonts = loadSoundFont  "acoustic_grand_piano"

signals : List (Signal Action)
signals = [Signal.map LoadFont pianoFonts]





