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
import Html.Attributes exposing (src, type', style, value, max)
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
   { index : Int                    -- index into the MidiMessage Array
   , microsecondsPerBeat : Float    -- current Tempo
   , playing : Bool                 -- are we currently playing?
   , noteOnSequence : Bool          -- are we in the midst of a NoteOn sequence
   , noteOnChannel : Int            -- if so, what's its channel
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
                      , noteOnSequence = False
                      , noteOnChannel = -1
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
    | Pause
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

    Pause ->   
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
           nextAction = interpretSoundEvent event playbackState model
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
interpretSoundEvent : SoundEvent -> PlaybackState -> Model -> Effects Action
interpretSoundEvent soundEvent state model = 
      (Task.sleep soundEvent.deltaTime 
        `andThen` \_ -> playEvent soundEvent state model)
      |> Task.map (\s -> 
         if s.playing then Play s else NoOp)
      |> Effects.task

{- step through the state, and play the note if it's a NoteOn message
   if it's a RunningStatus message, then play the note if the previous message was NoteOn 
-}
playEvent : SoundEvent -> PlaybackState -> Model -> Task x PlaybackState 
playEvent soundEvent state model = 
  if state.playing then
    case soundEvent.event of
      TrackEnd ->
        succeed { state | playing = False, noteOnSequence = False }

      Tempo t -> 
        succeed { state | microsecondsPerBeat = Basics.toFloat t, index = state.index + 1, noteOnSequence = False}
     
      {- Running Status inherits the channel from the last event but only (in our case)
         if the state shows we're in the midst of a NoteOn sequence (i.e. a NoteOn followed 
         immediately by 0 or more RunningStatus) then we generate a new NoteOn
      -}
      RunningStatus p1 p2 ->
        if state.noteOnSequence then
            let 
              newEvent = { deltaTime = soundEvent.deltaTime, event = NoteOn state.noteOnChannel p1 p2 }
            in
              playEvent newEvent state model
          else
            -- ignore anything else and reset the sequence state
            succeed { state | index = state.index + 1, noteOnSequence = False}
      
      NoteOn channel pitch velocity ->
        let
          newstate = 
           { state | index = state.index + 1, noteOnSequence = True, noteOnChannel = channel }
          sample = 
           Dict.get pitch model.samples
          maxVelocity = 0x7F
          gain =
            Basics.toFloat velocity / maxVelocity
          soundBite = 
           { mss = sample, time = 0.0, gain = gain }
        in
          Task.map (\_ -> newstate) <| maybePlay soundBite
      _  -> 
        succeed { state | index = state.index + 1, noteOnSequence = False}
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

view : Signal.Address Action -> Model -> Html
view address model =
  div [] [(player address model)]
    
    
player : Signal.Address Action -> Model -> Html
player address model =
  let start = "images/play.png"
      stop  = "images/stop.png"
      pause = "images/pause.png"
      maxRange = case model.track0 of
       Ok track0 -> Array.length track0.messages |> toString
       _ -> "0"
      sliderPos = model.playbackState.index |> toString
      playButton = 
        case model.playbackState.playing of
          True -> 
            pause
          False ->
            start
      playAction = 
        case model.playbackState.playing of
          True -> 
            Pause
          False ->
            Start
      in
        div [ style playerBlock ]
          [ div [ style (playerBase ++ playerStyle) ]
             [ progress [ Html.Attributes.max maxRange
                        , value sliderPos 
                        , style capsuleStyle
                        ] [] 
             , div [ style buttonStyle ] 
               [ input [ type' "image"
                       , src playButton
                       , onClick address (playAction) 
                       ] [ ]
               , input [ type' "image"
                       , src stop
                       , onClick address (MoveTo 0) 
                       ] [ ]
               ]
             ]
          ]
    


buttons : Signal.Address Action -> Model -> Html
buttons address model =
  case model.playbackState.playing of
    True ->  
      div []
        [ button [ onClick address (Pause) ] [ text "pause" ]
        , button [ onClick address (MoveTo 0) ] [ text "stop" ]
        ]
    False -> 
      div []
        [ button [ onClick address (Start) ] [ text "play" ] 
        , button [ onClick address (MoveTo 0) ] [ text "stop" ]
        ]

-- CSS
{- Only half-successful attempt to reuse the styling of the MIDI.js player on which this project is based
   I've lost access to identicalsnowflake/elm-dynamic-style for effects like hover which is no longer
   compatible with Elm 0.16 and my gradient effects don't seem to work.  Not sure what the future
   holds for libraries such as elm-style or elm-css. 
-}
playerBlock : List (String, String)
playerBlock =
  [ ("border", "1px solid #000")
  --, ("background", "#000")
  , ("border-radius", "10px")
  , ("width", "360px")
  , ("position", "relative; z-index: 2")
  -- , ("margin-bottom", "15px")
  ]


playerStyle : List (String, String)
playerStyle =
  [ ("height", "30px")
  , ("box-shadow", "-1px #000")
  , ("border-bottom-right-radius", "10")
  , ("border-bottom-left-radius", "10")
  --, ("margin-bottom", "0" )
  ]

playerBase : List (String, String)
playerBase =
  [ ("background", "rgba(0,0,0,0.7)")
    -- ("background", "#000")
  , ("background-image", "-webkit-gradient(linear,left top,left bottom,from(rgba(66,66,66,1)),to(rgba(22,22,22,1)))")
  , ("background-image", "-webkit-linear-gradient(top, rgba(66, 66, 66, 1) 0%, rgba(22, 22, 22, 1) 100%)")
  , ("background-image", "-moz-linear-gradient(top, rgba(66, 66, 66, 1) 0%, rgba(22, 22, 22, 1) 100%)")
  , ("background-image", "-ms-gradient(top, rgba(66, 66, 66, 1) 0%, rgba(22, 22, 22, 1) 100%)")
  , ("background-image", "-o-gradient(top, rgba(66, 66, 66, 1) 0%, rgba(22, 22, 22, 1) 100%)")
  , ("background-image", "linear-gradient(top, rgba(66, 66, 66, 1) 0%, rgba(22, 22, 22, 1) 100%)")
  , ("padding", "15px 20px")
  , ("border", "1px solid #000")
  , ("box-shadow", "0 0 10px #fff")
  , ("-moz-box-shadow", "0 0 10px #fff")
  , ("-webkit-box-shadow", "0 0 10px #fff")
  , ("border-radius", "10px")
  , ("-moz-border-radius", "10px")
  , ("-webkit-border-radius", "10px")
  , ("color", "#FFFFFF")
  , ("color", "rgba(255, 255, 255, 0.8)")
  , ("text-shadow", "1px 1px 2px #000")
  , ("-moz-text-shadow", "1px 1px 2px #000")
  -- , ("margin-bottom", "15px")
  ]

buttonStyle : List (String, String)
buttonStyle = 
  [ ("margin", "0 auto")
  , ("width", "80px")
  , ("float", "right")
  , ("opacity", "0.7")
  ]

capsuleStyle : List (String, String)
capsuleStyle = 
  [ ("border", "1px solid #000")
  , ("box-shadow", "0 0 10px #555")
  , ("-moz-box-shadow", "0 0 10px #555")
  , ("-webkit-box-shadow", "0 0 10px #555")
  , ("background", "#000")
  , ("background-image", "-webkit-gradient(linear, left top, left bottom, color-stop(1, rgba(0,0,0,0.5)), color-stop(0, #333))")
  , ("background-image", "-webkit-linear-gradient(top, rgba(0, 0, 0, 0.5) 1, #333 0)")
  , ("background-image", "-moz-linear-gradient(top, rgba(0, 0, 0, 0.5) 1, #333 0)")
  , ("background-image", "-ms-gradient(top, rgba(0, 0, 0, 0.5) 1, #333 0)")
  , ("background-image", "-o-gradient(top, rgba(0, 0, 0, 0.5) 1, #333 0)")
  , ("background-image", "linear-gradient(top, rgba(0, 0, 0, 0.5) 1, #333 0)")
  , ("overflow", "hidden")
  , ("border-radius", "5px")
  , ("-moz-border-radius", "5px")
  , ("-webkit-border-radius", "5px")
  , ("width", "220px")
  , ("display", "inline-block")
  , ("height", "30px")
  ]
   
  


-- INPUTS

-- try to load the entire piano soundfont
pianoFonts : Signal (Maybe SoundSample)
pianoFonts = loadSoundFont  "acoustic_grand_piano"

signals : List (Signal Action)
signals = [Signal.map LoadFont pianoFonts]





