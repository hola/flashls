/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls {
    import org.mangui.hls.model.AudioTrack;

    import flash.display.Stage;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.net.URLStream;
    import flash.events.EventDispatcher;
    import flash.events.Event;
    import flash.utils.setTimeout;    

    import org.mangui.hls.model.Level;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.playlist.AltAudioTrack;
    import org.mangui.hls.loader.ManifestLoader;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.loader.FragmentLoader;
    import org.mangui.hls.stream.HLSNetStream;
    import org.hola.JSAPI;
    import flash.external.ExternalInterface;
    import org.hola.ZExternalInterface;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Class that manages the streaming process. **/
    public class HLS extends EventDispatcher {
        public var _fragmentLoader : FragmentLoader;
        private var _manifestLoader : ManifestLoader;
        private var _audioTrackController : AudioTrackController;
        /** HLS NetStream **/
        private var _hlsNetStream : HLSNetStream;
        /** HLS URLStream **/
        private var _hlsURLStream : Class;
        private var _client : Object = {};
        private var _stage : Stage;
        private var _url:String;
        private static var hola_api_inited:Boolean;
        private static var g_curr_id:Number = 0;
        private static var g_curr_hls:HLS;

        private static function hola_version() : Object
        {
            return {
                flashls_version: '0.3.5',
                patch_version: '1.0.22'
            };
        }
        private static function hola_hls_get_video_url() : String {
            return g_curr_hls._url;
        }

        private static function hola_hls_get_type():String{
            return g_curr_hls.type;
        }	

        private static function hola_hls_get_position() : Number {
            return g_curr_hls.position;
        }

        private static function hola_hls_get_duration() : Number {
            return g_curr_hls.duration;
        }

        private static function hola_hls_get_buffer_sec() : Number {
            return g_curr_hls.bufferLength;
        }

        private static function hola_hls_call(method:String, args:Array):Object{
            return g_curr_hls[method].apply(g_curr_hls, args);
        }

        private static function hola_hls_get_state() : String {
            return g_curr_hls.playbackState;
        }

        private static function hola_hls_get_levels() : Object {
	    var levels:Vector.<Object> = 
	        new Vector.<Object>(g_curr_hls.levels.length);
	    for (var i:int = 0; i<g_curr_hls.levels.length; i++)
	    {
		var l:Level = g_curr_hls.levels[i];
		// no fragments returned, use get_segment_info for fragm. info
	        levels[i] = Object({url: l.url, bitrate: l.bitrate,
		    index: l.index, fragments: []});
            }
            return levels;
        }

        private static function hola_hls_get_segment_info(url:String) : Object {
	    for (var i:int = 0; i<g_curr_hls.levels.length; i++)
	    {
		var l:Level = g_curr_hls.levels[i];
		for (var j:int = 0; j<l.fragments.length; j++)
		{
		    if (url==l.fragments[j].url)
		    {
		        return Object({fragment: l.fragments[j],
			    level: Object({url: l.url, bitrate: l.bitrate,
			    index: l.index})});
		    }
		}
            }
	    return undefined;
	}

        private static function hola_hls_get_levels_async(): void
	{
	    setTimeout(function(): void
	    {
                var levels: Array = [];
                for (var i: int = 0; i<g_curr_hls.levels.length; i++)
                    levels.push(level_to_object(g_curr_hls.levels[i]));
		ExternalInterface.call('window.postMessage', {id: 'flashls.hlsAsyncMessage', hls_id: g_curr_id, type: 'get_levels', msg: levels});
	    }, 0);
        }

        private static function hola_hls_get_bitrate(): Number
	{
   	    return g_curr_hls.levels[g_curr_hls.level] ? g_curr_hls.levels[g_curr_hls.level].bitrate : 0;
	}

        private static function hola_hls_get_level(): String
	{
            return g_curr_hls.levels[g_curr_hls.level] ? g_curr_hls.levels[g_curr_hls.level].url : undefined;
        }

        /** Create and connect all components. **/
        public function HLS() {
            JSAPI.init();
            if (!hola_api_inited && ZExternalInterface.avail())
            {
                hola_api_inited = true;
                ExternalInterface.addCallback("hola_hls_call",
                    HLS.hola_hls_call);
                ExternalInterface.addCallback("hola_version",
                    HLS.hola_version);
                ExternalInterface.addCallback("hola_hls_get_bitrate", hola_hls_get_bitrate);
                ExternalInterface.addCallback("hola_hls_get_video_url",
                    HLS.hola_hls_get_video_url);
                ExternalInterface.addCallback("hola_hls_get_position",
                    HLS.hola_hls_get_position);
                ExternalInterface.addCallback("hola_hls_get_duration",
                    HLS.hola_hls_get_duration);
                ExternalInterface.addCallback("hola_hls_get_buffer_sec",
                    HLS.hola_hls_get_buffer_sec);
                ExternalInterface.addCallback("hola_hls_get_state",
                    HLS.hola_hls_get_state);
                ExternalInterface.addCallback("hola_hls_get_levels",
                    HLS.hola_hls_get_levels);
                ExternalInterface.addCallback("hola_hls_get_segment_info",
                    HLS.hola_hls_get_segment_info);
                ExternalInterface.addCallback("hola_hls_get_level",
                    HLS.hola_hls_get_level);
                ExternalInterface.addCallback("hola_hls_get_type",
                    HLS.hola_hls_get_type);
		ExternalInterface.addCallback("hola_hls_get_levels_async", hola_hls_get_levels_async);
            }
            g_curr_id++;
            g_curr_hls = this;
            var connection : NetConnection = new NetConnection();
            connection.connect(null);
            _manifestLoader = new ManifestLoader(this);
            _audioTrackController = new AudioTrackController(this);
            _hlsURLStream = URLStream as Class;
            // default loader
            _fragmentLoader = new FragmentLoader(this, _audioTrackController);
            _hlsNetStream = new HLSNetStream(connection, this, _fragmentLoader);
            if (ZExternalInterface.avail())
            {
                ExternalInterface.call('window.postMessage',
                    {id: 'flashls.hlsNew', hls_id: g_curr_id}, '*');
            }
            add_event(HLSEvent.MANIFEST_LOADING);
            add_event(HLSEvent.MANIFEST_PARSED);
            add_event(HLSEvent.MANIFEST_LOADED);
            add_event(HLSEvent.LEVEL_LOADING);
	    this.addEventListener(HLSEvent.LEVEL_LOADED, on_event_loaded);
            add_event(HLSEvent.LEVEL_SWITCH);
            add_event(HLSEvent.LEVEL_ENDLIST);
            add_event(HLSEvent.FRAGMENT_LOADING);
            add_event(HLSEvent.FRAGMENT_LOADED);
            add_event(HLSEvent.FRAGMENT_PLAYING);
            add_event(HLSEvent.AUDIO_TRACKS_LIST_CHANGE);
            add_event(HLSEvent.AUDIO_TRACK_CHANGE);
            add_event(HLSEvent.TAGS_LOADED);
            add_event(HLSEvent.LAST_VOD_FRAGMENT_LOADED);
            add_event(HLSEvent.ERROR);
            add_event(HLSEvent.MEDIA_TIME);
            add_event(HLSEvent.PLAYBACK_STATE);
            add_event(HLSEvent.SEEK_STATE);
            add_event(HLSEvent.PLAYBACK_COMPLETE);
            add_event(HLSEvent.PLAYLIST_DURATION_UPDATED);
            add_event(HLSEvent.ID3_UPDATED);
        };

        private function on_event_loaded(e: HLSEvent): void
	{
            if (!ZExternalInterface.avail())
                return;
            ExternalInterface.call('window.postMessage', {id: 'flashls.'+e.type, hls_id: g_curr_id, 
	        level: level_to_object(g_curr_hls.levels[e.level])});	
	}

        private static function level_to_object(l: Level): Object
	{
            var fragments: Array = [];
	    for (var i: int = 0; i<l.fragments.length; i++)
	    {
	        var fragment: Fragment = l.fragments[i];
	        fragments.push({url: fragment.url, duration: fragment.duration, seqnum: fragment.seqnum});
	    }	
	    return {url: l.url, bitrate: l.bitrate, fragments: fragments, index: l.index};
	}	

        private function add_event(name:String):void{
            this.addEventListener(name, event_handler_func('flashls.'+name));
        }
        private function event_handler_func(name:String):Function{
            return function(event:HLSEvent):void{
                if (!ZExternalInterface.avail())
                    return;
                ExternalInterface.call('window.postMessage',
                    {id: name, hls_id: g_curr_id, url: event.url,
                    level: event.level, duration: event.duration,
                    levels: event.levels, error: event.error,
                    loadMetrics: event.loadMetrics,
                    playMetrics: event.playMetrics, mediatime: event.mediatime,
                    state: event.state, audioTrack: event.audioTrack}, '*');
            }
        }

        /** Forward internal errors. **/
        override public function dispatchEvent(event : Event) : Boolean {
            if (event.type == HLSEvent.ERROR) {
                CONFIG::LOGGING {
                    Log.error((event as HLSEvent).error);
                }
                _hlsNetStream.close();
            }
            return super.dispatchEvent(event);
        };

        public function dispose() : void {
            if (ZExternalInterface.avail())
            {
                ExternalInterface.call('window.postMessage',
                    {id: 'flashls.hlsDispose', hls_id: g_curr_id}, '*');
            }
            _fragmentLoader.dispose();
            _manifestLoader.dispose();
            _audioTrackController.dispose();
            _hlsNetStream.dispose_();
            _fragmentLoader = null;
            _manifestLoader = null;
            _audioTrackController = null;
            _hlsNetStream = null;
            _client = null;
            _stage = null;
            _hlsNetStream = null;
        }

        /** Return the quality level used when starting a fresh playback **/
        public function get startlevel() : int {
            return _manifestLoader.startlevel;
        };

        /** Return the quality level used after a seek operation **/
        public function get seeklevel() : int {
            return _manifestLoader.seeklevel;
        };

        /** Return the quality level of the currently played fragment **/
        public function get playbacklevel() : int {
            return _hlsNetStream.playbackLevel;
        };

        /** Return the quality level of last loaded fragment **/
        public function get level() : int {
            return _fragmentLoader.level;
        };

        /*  set quality level for next loaded fragment (-1 for automatic level selection) */
        public function set level(level : int) : void {
            _fragmentLoader.level = level;
        };

        /* check if we are in automatic level selection mode */
        public function get autolevel() : Boolean {
            return _fragmentLoader.autolevel;
        };

        /** Return a Vector of quality level **/
        public function get levels() : Vector.<Level> {
            return _manifestLoader.levels;
        };

        /** Return the current playback position. **/
        public function get position() : Number {
            return _hlsNetStream.position;
        };

        public function get video_url() : String {
            return _url;
        };

        public function get duration() : Number {
            return _hlsNetStream.duration;
        };

        /** Return the current playback state. **/
        public function get playbackState() : String {
            return _hlsNetStream.playbackState;
        };

        /** Return the current seek state. **/
        public function get seekState() : String {
            return _hlsNetStream.seekState;
        };

        /** Return the type of stream (VOD/LIVE). **/
        public function get type() : String {
            return _manifestLoader.type;
        };

        /** Load and parse a new HLS URL **/
        public function load(url : String) : void {
            _hlsNetStream.close();
            _url = url;
            _manifestLoader.load(url);
        };

        /** return HLS NetStream **/
        public function get stream() : NetStream {
            return _hlsNetStream;
        }

        public function get client() : Object {
            return _client;
        }

        public function set client(value : Object) : void {
            _client = value;
        }

        /** get current Buffer Length  **/
        public function get bufferLength() : Number {
            return _hlsNetStream.bufferLength;
        };

        /** get audio tracks list**/
        public function get audioTracks() : Vector.<AudioTrack> {
            return _audioTrackController.audioTracks;
        };

        /** get alternate audio tracks list from playlist **/
        public function get altAudioTracks() : Vector.<AltAudioTrack> {
            return _manifestLoader.altAudioTracks;
        };

        /** get index of the selected audio track (index in audio track lists) **/
        public function get audioTrack() : int {
            return _audioTrackController.audioTrack;
        };

        /** select an audio track, based on its index in audio track lists**/
        public function set audioTrack(val : int) : void {
            _audioTrackController.audioTrack = val;
        }

        /* set stage */
        public function set stage(stage : Stage) : void {
            _stage = stage;
        }

        /* get stage */
        public function get stage() : Stage {
            return _stage;
        }

        /* set URL stream loader */
        public function set URLstream(urlstream : Class) : void {
            _hlsURLStream = urlstream;
        }

        /* retrieve URL stream loader */
        public function get URLstream() : Class {
            return _hlsURLStream;
        }
    }
    ;
}
