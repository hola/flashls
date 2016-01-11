package org.mangui.hls
{
    import flash.external.ExternalInterface;
    import org.hola.ZExternalInterface;
    import org.hola.JSAPI;
    import org.hola.HSettings;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.constant.HLSPlayStates;

    public class HLSJS
    {
        private static var _inited:Boolean = false;
        private static var _duration:Number;
        private static var _bandwidth:Number = -1;
        private static var _url:String;
        private static var _state:String;
        private static var _hls:HLS;

        public static function init():void{
            if (_inited || !ZExternalInterface.avail())
                return;
            _inited = true;
            JSAPI.init();
            ExternalInterface.addCallback("hola_version", hola_version);
            ExternalInterface.addCallback("hola_hls_get_video_url",
                hola_hls_get_video_url);
            ExternalInterface.addCallback("hola_hls_get_position",
                hola_hls_get_position);
            ExternalInterface.addCallback("hola_hls_get_duration",
                hola_hls_get_duration);
            ExternalInterface.addCallback("hola_hls_get_buffer_sec",
                hola_hls_get_buffer_sec);
            ExternalInterface.addCallback("hola_hls_get_state",
                hola_hls_get_state);
            ExternalInterface.addCallback("hola_hls_get_levels",
                hola_hls_get_levels);
            ExternalInterface.addCallback("hola_hls_get_level",
                hola_hls_get_level);
            ExternalInterface.addCallback("hola_setBandwidth",
                hola_setBandwidth);
        }

        public static function HLSnew(hls:HLS):void{
            _hls = hls;
            _state = HLSPlayStates.IDLE;
            // track duration events
            hls.addEventListener(HLSEvent.MANIFEST_LOADED, on_manifest_loaded);
            hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED,
                on_playlist_duration_updated);
            // track playlist-url/state
            hls.addEventListener(HLSEvent.MANIFEST_LOADING, on_manifest_loading);
            hls.addEventListener(HLSEvent.PLAYBACK_STATE, on_playback_state);
            // notify js events
            hls.addEventListener(HLSEvent.MANIFEST_LOADING, on_event);
            hls.addEventListener(HLSEvent.MANIFEST_PARSED, on_event);
            hls.addEventListener(HLSEvent.MANIFEST_LOADED, on_event);
            hls.addEventListener(HLSEvent.LEVEL_LOADING, on_event);
            hls.addEventListener(HLSEvent.LEVEL_LOADED, on_event);
            hls.addEventListener(HLSEvent.LEVEL_SWITCH, on_event);
            hls.addEventListener(HLSEvent.LEVEL_ENDLIST, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_LOADING, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_LOADED, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, on_event);
            hls.addEventListener(HLSEvent.AUDIO_TRACKS_LIST_CHANGE, on_event);
            hls.addEventListener(HLSEvent.AUDIO_TRACK_SWITCH, on_event);
            hls.addEventListener(HLSEvent.AUDIO_LEVEL_LOADING, on_event);
            hls.addEventListener(HLSEvent.AUDIO_LEVEL_LOADED, on_event);
            hls.addEventListener(HLSEvent.TAGS_LOADED, on_event);
            hls.addEventListener(HLSEvent.LAST_VOD_FRAGMENT_LOADED, on_event);
            hls.addEventListener(HLSEvent.ERROR, on_event);
            hls.addEventListener(HLSEvent.MEDIA_TIME, on_event);
            hls.addEventListener(HLSEvent.PLAYBACK_STATE, on_event);
            hls.addEventListener(HLSEvent.SEEK_STATE, on_event);
            hls.addEventListener(HLSEvent.PLAYBACK_COMPLETE, on_event);
            hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED,
                on_event);
            hls.addEventListener(HLSEvent.ID3_UPDATED, on_event);
            JSAPI.postMessage2({id: 'flashls.hlsNew', hls_id: hls.id});
        }

        public static function HLSdispose(hls:HLS):void{
            JSAPI.postMessage2({id: 'flashls.hlsDispose', hls_id: hls.id});
            _duration = 0;
            _bandwidth = -1;
            _url = null;
            _state = HLSPlayStates.IDLE;
            _hls = null;
        }

        public static function get bandwidth():Number{
            return HSettings.hls_mode ? _bandwidth : -1;
        }

        private static function on_manifest_loaded(e:HLSEvent):void{
            _duration = e.levels[_hls.startLevel].duration;
        }

        private static function on_playlist_duration_updated(e:HLSEvent):void{
            _duration = e.duration;
        }

        private static function on_manifest_loading(e:HLSEvent):void{
            _url = e.url;
            _state = "LOADING";
            on_event(new HLSEvent(HLSEvent.PLAYBACK_STATE, _state));
        }

        private static function on_playback_state(e:HLSEvent):void{
            _state = e.state;
        }

        private static function on_event(e:HLSEvent):void{
            JSAPI.postMessage2({id: 'flashls.'+e.type, hls_id: _hls.id,
                url: e.url, level: e.level, duration: e.duration, levels: e.levels,
                error: e.error, loadMetrics: e.loadMetrics,
                playMetrics: e.playMetrics, mediatime: e.mediatime, state: e.state,
                audioTrack: e.audioTrack});
        }

        private static function hola_version():Object{
            return {
                flashls_version: '0.4.1.1',
                patch_version: '2.0.2'
            };
        }

        private static function hola_hls_get_video_url():String{
            return _url;
        }

        private static function hola_hls_get_position():Number{
            return _hls.position;
        }

        private static function hola_hls_get_duration():Number{
            return _duration;
        }

        private static function hola_hls_get_buffer_sec():Number{
            return _hls.stream.bufferLength;
        }

        private static function hola_hls_get_state():String{
            return _state;
        }

        private static function hola_hls_get_levels():Object{
            return _hls.levels;
        }

        private static function hola_hls_get_level():Number{
            return _hls.loadLevel;
        }

        private static function hola_setBandwidth(bandwidth:Number):void{
            _bandwidth = bandwidth;
        }
    }
}
