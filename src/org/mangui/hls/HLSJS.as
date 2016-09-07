package org.mangui.hls
{
    import flash.external.ExternalInterface;
    import org.hola.ZExternalInterface;
    import org.hola.JSAPI;
    import org.hola.HSettings;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.model.Fragment;
    import flash.utils.setTimeout;
    import flash.net.NetStreamAppendBytesAction;

    public class HLSJS
    {
        private static var _inited: Boolean = false;
        private static var _duration: Number;
        private static var _bandwidth: Number = -1;
        private static var _url: String;
        private static var _currentFrag: String;
        private static var _state: String;
        private static var _hls: HLS;
        private static var _silence: Boolean = false;

        public static function init():void{
            if (_inited || !ZExternalInterface.avail())
                return;
            _inited = true;
            JSAPI.init();
            ExternalInterface.addCallback("hola_version", hola_version);
            ExternalInterface.addCallback("hola_hls_version", hola_version);
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
            ExternalInterface.addCallback("hola_hls_get_current_fragment",
                hola_hls_get_current_fragment);
            ExternalInterface.addCallback("hola_hls_get_levels",
                hola_hls_get_levels);
            ExternalInterface.addCallback("hola_hls_get_levels_async",
                hola_hls_get_levels_async);
            ExternalInterface.addCallback("hola_hls_get_segment_info",
                hola_hls_get_segment_info);
            ExternalInterface.addCallback("hola_hls_get_level",
                hola_hls_get_level);
            ExternalInterface.addCallback("hola_hls_get_bitrate",
                hola_hls_get_bitrate);
            ExternalInterface.addCallback("hola_hls_get_decoded_frames",
                hola_hls_get_decoded_frames);
            ExternalInterface.addCallback("hola_setBandwidth",
                hola_setBandwidth);
            ExternalInterface.addCallback("hola_hls_setBandwidth",
                hola_setBandwidth);
            ExternalInterface.addCallback("hola_hls_get_type",
                hola_hls_get_type);
            ExternalInterface.addCallback("hola_hls_load_fragment", hola_hls_load_fragment);
            ExternalInterface.addCallback("hola_hls_abort_fragment", hola_hls_abort_fragment);
            ExternalInterface.addCallback("hola_hls_load_level", hola_hls_load_level);
            ExternalInterface.addCallback('hola_hls_flush_stream', hola_hls_flush_stream);
        }

        public static function HLSnew(hls:HLS):void{
            _hls = hls;
            _state = HLSPlayStates.IDLE;
            // track duration events
            hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED,
                on_playlist_duration_updated);
            // track playlist-url/state
            hls.addEventListener(HLSEvent.PLAYBACK_STATE, on_playback_state);
            hls.addEventListener(HLSEvent.SEEK_STATE, on_seek_state);
            hls.addEventListener(HLSEvent.MANIFEST_LOADED, on_manifest_loaded);
            hls.addEventListener(HLSEvent.MANIFEST_LOADING, on_manifest_loading);
            hls.addEventListener(HLSEvent.FRAGMENT_LOADING, on_fragment_loading);
            // notify js events
            hls.addEventListener(HLSEvent.MANIFEST_LOADING, on_event);
            hls.addEventListener(HLSEvent.MANIFEST_PARSED, on_event);
            hls.addEventListener(HLSEvent.MANIFEST_LOADED, on_event);
            hls.addEventListener(HLSEvent.LEVEL_LOADING, on_event);
            hls.addEventListener(HLSEvent.LEVEL_LOADING_ABORTED, on_event);
            hls.addEventListener(HLSEvent.LEVEL_LOADED, on_level_loaded);
            hls.addEventListener(HLSEvent.LEVEL_SWITCH, on_event);
            hls.addEventListener(HLSEvent.LEVEL_ENDLIST, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_LOADING, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_LOADED, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_LOAD_EMERGENCY_ABORTED,
                on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, on_event);
            hls.addEventListener(HLSEvent.FRAGMENT_SKIPPED, on_event);
            hls.addEventListener(HLSEvent.AUDIO_TRACKS_LIST_CHANGE, on_event);
            hls.addEventListener(HLSEvent.AUDIO_TRACK_SWITCH, on_event);
            hls.addEventListener(HLSEvent.AUDIO_LEVEL_LOADING, on_event);
            hls.addEventListener(HLSEvent.AUDIO_LEVEL_LOADED, on_event);
            hls.addEventListener(HLSEvent.TAGS_LOADED, on_event);
            hls.addEventListener(HLSEvent.LAST_VOD_FRAGMENT_LOADED, on_event);
            hls.addEventListener(HLSEvent.WARNING, on_event);
            hls.addEventListener(HLSEvent.ERROR, on_event);
            hls.addEventListener(HLSEvent.MEDIA_TIME, on_event);
            hls.addEventListener(HLSEvent.PLAYBACK_STATE, on_event);
            hls.addEventListener(HLSEvent.STREAM_TYPE_DID_CHANGE, on_event);
            hls.addEventListener(HLSEvent.PLAYBACK_COMPLETE, on_event);
            hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED,
                on_event);
            hls.addEventListener(HLSEvent.ID3_UPDATED, on_event);
            hls.addEventListener(HLSEvent.FPS_DROP, on_event);
            hls.addEventListener(HLSEvent.FPS_DROP_LEVEL_CAPPING, on_event);
            hls.addEventListener(HLSEvent.FPS_DROP_SMOOTH_LEVEL_SWITCH,
                on_event);
            hls.addEventListener(HLSEvent.LIVE_LOADING_STALLED, on_event);
            JSAPI.postMessage('flashls.hlsNew');
        }

        public static function HLSdispose(hls:HLS):void{
            JSAPI.postMessage('flashls.hlsDispose');
            _duration = 0;
            _bandwidth = -1;
            _url = null;
            _state = HLSPlayStates.IDLE;
            _hls = null;
        }

        public static function get bandwidth():Number{
            return HSettings.gets('mode')=='adaptive' ? _bandwidth : -1;
        }

        private static function on_manifest_loaded(e:HLSEvent):void{
            _duration = e.levels[_hls.startLevel].duration;
        }

        private static function on_playlist_duration_updated(e:HLSEvent):void{
            _duration = e.duration;
        }

        private static function on_fragment_loading(e: HLSEvent): void
        {
            _currentFrag = e.url;
        }

        private static function on_manifest_loading(e:HLSEvent):void{
            _url = e.url;
            _state = "LOADING";
            on_event(new HLSEvent(HLSEvent.PLAYBACK_STATE, _state));
        }

        private static function on_playback_state(e:HLSEvent):void{
            _state = e.state;
        }

        private static function on_level_loaded(e: HLSEvent): void
        {
            JSAPI.postMessage('flashls.'+e.type, {level: level_to_object(_hls.levels[e.loadMetrics.level])});
        }

        private static function on_seek_state(e: HLSEvent): void
        {
            JSAPI.postMessage('flashls.'+e.type, {state: e.state, seek_pos: _hls.position, buffer: _hls.stream.bufferLength});
        }

        private static function on_event(e: HLSEvent): void
        {
            if (_silence)
                return;
            JSAPI.postMessage('flashls.'+e.type, {url: e.url, level: e.level,
                duration: e.duration, levels: e.levels, error: e.error,
                loadMetrics: e.loadMetrics, playMetrics: e.playMetrics,
                mediatime: e.mediatime, state: e.state,
                audioTrack: e.audioTrack, streamType: e.streamType});
        }

        private static function hola_version(): Object
        {
            return {
                flashls_version: '0.4.4.20',
                patch_version: '2.0.14'
            };
        }

        private static function hola_hls_get_video_url(): String
        {
            return _url;
        }

        private static function hola_hls_get_position(): Number
        {
            return _hls.position;
        }

        private static function hola_hls_get_duration(): Number
        {
            return _duration;
        }

        private static function hola_hls_get_decoded_frames(): Number
        {
            return _hls.stream.decodedFrames;
        }

        private static function hola_hls_get_buffer_sec(): Number
        {
            return _hls.stream.bufferLength;
        }

        private static function hola_hls_get_state(): String
        {
            return _state;
        }

        private static function hola_hls_get_type(): String
        {
            return _hls.type;
        }

        private static function hola_hls_load_fragment(level: Number, frag: Number, url: String): Object
        {
            if (HSettings.gets('mode')!='hola_adaptive')
                return 0;
            return _hls.loadFragment(level, frag, url);
        }

        private static function hola_hls_flush_stream(): void
        {
            if (_hls.stream.decodedFrames === 0)
                return;
            _silence = true;
            _hls.stream.close();
            _hls.stream.play();
            _hls.stream.pause();
            _silence = false;
        }

        private static function hola_hls_abort_fragment(ldr_id: String): void
        {
            if (HSettings.gets('mode')!='hola_adaptive')
                return;
            _hls.abortFragment(ldr_id);
        }

        private static function hola_hls_load_level(level: Number): void
        {
            if (HSettings.gets('mode')!='hola_adaptive')
                return;
            if (!_hls.isStartLevelSet())
                _hls.startLevel = level;
            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, level));
        }

        private static function level_to_object(l: Level): Object
        {
            var fragments: Array = [];
            for (var i: int = 0; i<l.fragments.length; i++)
            {
                var fragment: Fragment = l.fragments[i];
                fragments.push({url: fragment.url,
                    duration: fragment.duration, seqnum: fragment.seqnum});
            }
            return {url: l.url, bitrate: l.bitrate, fragments: fragments,
                index: l.index, width: l.width, height: l.height, audio: l.audio};
        }

        private static function hola_hls_get_levels(): Object
        {
            var levels: Vector.<Object> = new Vector.<Object>(_hls.levels.length);
            for (var i: int = 0; i<_hls.levels.length; i++)
            {
                var l: Level = _hls.levels[i];
                // no fragments returned, use get_segment_info for fragm.info
                levels[i] = Object({url: l.url, bitrate: l.bitrate,
                    index: l.index, fragments: []});
            }
            return levels;
        }

        private static function hola_hls_get_current_fragment(): String
        {
            return _currentFrag;
        }

        private static function hola_hls_get_levels_async(): void
        {
            setTimeout(function(): void
            {
                var levels: Array = [];
                for (var i: int = 0; i<_hls.levels.length; i++)
                    levels.push(level_to_object(_hls.levels[i]));
                JSAPI.postMessage('flashls.hlsAsyncMessage', {type: 'get_levels', msg: levels});
            }, 0);
        }

        private static function hola_hls_get_segment_info(url: String): Object
        {
            for (var i: int = 0; i<_hls.levels.length; i++)
            {
                var l: Level = _hls.levels[i];
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

        private static function hola_hls_get_bitrate(): Number
        {
            return _hls.loadLevel<_hls.levels.length ? _hls.levels[_hls.loadLevel].bitrate : 0;
        }

        private static function hola_hls_get_level(): String
        {
            return _hls.loadLevel<_hls.levels.length ? _hls.levels[_hls.loadLevel].url : undefined;
        }

        private static function hola_setBandwidth(bandwidth: Number): void
        {
            _bandwidth = bandwidth;
        }
    }
}
