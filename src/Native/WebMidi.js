Elm.Native.WebMidi = {};

Elm.Native.WebMidi.make = function(localRuntime) {
    localRuntime.Native = localRuntime.Native || {};
    localRuntime.Native.WebMidi = localRuntime.Native.WebMidi || {};
    if (localRuntime.Native.WebMidi.values) return localRuntime.Native.WebMidi.values;

    var Utils = Elm.Native.Utils.make(localRuntime);
    var NS = Elm.Native.Signal.make(localRuntime); 
    var Task = Elm.Native.Task.make(localRuntime);

    var note = NS.input('WebMidi.note', mnote(false,0,0,0,""));
    var connect = NS.input('WebMidi.connect', mconnect("","","","",""));
    var disconnect = NS.input('WebMidi.disconnect', mdisconnect("",""));

    // constructor function for Elm tuples
    function mnote(v, w, x, y, z)	{
	return { 
          ctor: "_Tuple5",
	  noteOn: v,
	  pitch: w,
	  velocity: x,
	  timestamp: y,
          sourceId: z
	  };
    }

    function mconnect(t,i,m,n,v) 	{
	return { 
          ctor: "_Tuple5",
	  portType: t,
	  id: i,
	  manufacturer: m,
	  name: n,
          version: v
	  };
    }

    function mdisconnect(t, i) 	{
	return { 
          ctor: "_Tuple2",
	  portType: t,
	  id: i
	  };
    }

    /* I intend eventually to return init defined like this.  In other words
     * it would allow us to detect our midi devices as an Elm Task.
     * Unfortunately it crashes in Elm runtime's stepTask in Elm 0.15
     * See https://github.com/elm-lang/core/issues/240
     */
    function init ()  {
        console.log("init: " )
            return Task.asyncFunction(function (callback) {
                midiConnect();
                callback(Task.succeed(Utils.Tuple0));
            });
        };


    function midiConnect () {

      console.log('MIDIConnect');
      // request MIDI access and then connect
      if (navigator.requestMIDIAccess) {
         navigator.requestMIDIAccess({
           sysex: false // this defaults to 'false' anyway.
         }).then(onMIDISuccess)
      } 
    }

    // Set up all the signals we expect if MIDI is supported
    function onMIDISuccess(midiAccess) {
        // console.log('MIDI Access Object', midiAccess);

        var inputs = midiAccess.inputs.values();       
        // loop over any register inputs and listen for data on each
        midiAccess.inputs.forEach( function( input, id, inputMap ) {   
          registerInput(input);       
          input.onmidimessage = onMIDIMessage;     
        });      

        // listen for connect/disconnect message
        midiAccess.onstatechange = onStateChange;
    }  

    // MIDI message signal
    function onMIDIMessage(event){
        var data = event.data, 
        cmd = data[0] >> 4,
        channel = data[0] & 0xf,
        type = data[0] & 0xf0
        pitch = data[1], 
        velocity = data[2],
        ts = event.timeStamp,
        noteOff = (velocity == 0) || (type == 128),
        noteOn  = (velocity > 0) && (type == 144);	
        sourceId = event.srcElement.id;

        // console.log('type: ', type, ' pitch:', pitch, ' velocity:', velocity, ' timestamp:', ts, ' noteOn:', noteOn, ' noteOff:', noteOff); 

        if (noteOff) {
          localRuntime.notify(note.id, mnote(false,pitch,velocity,ts,sourceId));
        }
        else if (noteOn) {
          localRuntime.notify(note.id, mnote(true,pitch,velocity,ts,sourceId));
        }
    }

    // input connect/disconnect signal
    function onStateChange(event){
	// showMIDIPorts(midi);
	var port = event.port, state = port.state, name = port.name, type = port.type, id = port.id;
	if(type == "input") {
           console.log("State change:", state);
           if (state == "connected") {
              // console.log("State Change Connect" + " name", name, "port", port, "id", id, "state", state);
              localRuntime.notify(connect.id, mconnect(port.type,port.id,port.manufacturer,port.name,port.version));    
              // register midi note callbacks on this new input      
              port.onmidimessage = onMIDIMessage;   
           }
           else if  (state == "disconnected") {
              // console.log("State Change Disconnect" + " name", name, "port", port, "id", id, "state", state);
              localRuntime.notify(disconnect.id, mdisconnect(port.type, port.id)); 
           }
        }
    }

   
    // register an input device
    function registerInput(input){
        /* */
	console.log("Input port : [ type:'" + input.type + "' id: '" + input.id + 
	    "' manufacturer: '" + input.manufacturer + "' name: '" + input.name + 
	    "' version: '" + input.version + "']");   
        /* */
        localRuntime.notify(connect.id, mconnect(input.type,input.id,input.manufacturer,input.name,input.version));  
    }

 
    return localRuntime.Native.WebMidi.values = {
        note: note,
        connect: connect,
        disconnect: disconnect,
        init: init
    };
};

