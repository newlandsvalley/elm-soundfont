
import Effects exposing (Never)
import MidiController exposing (init, update, view, signals)
import StartApp
import Task exposing (Task)

app =
  StartApp.start
    { init = init "controller for playing midi type 0 files"
    , update = update
    , view = view
    , inputs = signals
    }

main =
  app.html

port tasks : Signal (Task Never ())
port tasks =
  app.tasks


