/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {

    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;

    import org.hola.HSettings;

    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.controller.LevelController;
    import org.mangui.hls.demux.DemuxHelper;
    import org.mangui.hls.demux.Demuxer;
    import org.mangui.hls.demux.ID3Tag;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.model.AudioTrack;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.FragmentData;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.stream.StreamBuffer;
    import org.mangui.hls.utils.AES;

    import org.hola.JSURLStream;

    import flash.external.ExternalInterface;

    /** Class that fetches fragments. **/
    public class HolaFragmentLoader implements FragmentLoaderInterface {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** reference to auto level manager */
        private var _levelController : LevelController;
        /** reference to audio track controller */
        private var _audioTrackController : AudioTrackController;
        /** Reference to the manifest levels. **/
        private var _levels : Vector.<Level>;
        /** Util for loading the key. **/
        private var _keystreamloader : URLStream;
        /** key map **/
        private var _keymap : Object;
        /** requested seek position **/
        private var _seekPosition : Number;
        /* stream buffer instance **/
        private var _streamBuffer : StreamBuffer;
        /* key error/reload */
	// XXX marka: now we are supporting only one key request for one url, if fragment wants another key, it's unfortunately for him!
        private var _keyLoadErrorDate : Number;
        private var _keyRetryTimeout : Number;
        private var _keyRetryCount : int;
        private var _keyLoadStatus : int;

	private var _loaders: Object = {};
	private var _ldr_id: Number = 1;
	private var _schedulers: Object = {};

        private var _fragSkipCount : int;

        private function ldr_from_req(loader: JSURLStream): FragLoaderInfo
	{
	    return _loaders[loader.req_id];
	}

	private function sch_from_ldr(ldr: FragLoaderInfo): FragScheduler
	{
	    return _schedulers[ldr.frag.level + '/' + ldr.frag.seqnum];
	}

	private function free_ldr(ldr: FragLoaderInfo): void
	{
	    if (ldr.loader.connected)
	        ldr.loader.close();
	    if (_loaders[ldr.loader.req_id])
	        delete _loaders[ldr.loader.req_id];
	}

        /** Create the loader. **/
        public function HolaFragmentLoader(hls : HLS, audioTrackController : AudioTrackController, levelController : LevelController, streamBuffer : StreamBuffer) : void {
            _hls = hls;
            _levelController = levelController;
            _audioTrackController = audioTrackController;
            _streamBuffer = streamBuffer;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _keymap = new Object();
            _levels = hls.levels;
        };

        public function dispose() : void {
            stop();
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _keymap = new Object();
        }

        private function get_current_scheduler(): *
	{
	    var ret: FragScheduler, min: Number;
	    for (var idx: String in _schedulers)
	    {
	        ret = _schedulers[idx];
	        min = +idx.split('/')[1];
		break;
	    }
	    for (idx in _schedulers)
	    {
	        var sn: Number = +idx.split('/')[1];
		if (sn < min)
		{
		    min = sn;
		    ret = _schedulers[idx];
		}
	    }
	    return ret;
	}

        public function get audioExpected() : Boolean {
	    var scheduler: FragScheduler = get_current_scheduler();
	    return scheduler ? scheduler.audioExpected : true;
        }

        public function get videoExpected() : Boolean {
	    var scheduler: FragScheduler = get_current_scheduler();
	    return scheduler ? scheduler.videoExpected : true;
        }

        public function seek(position : Number) : void {
            // reset IO Error when seeking
            _keyRetryCount = 0;
            _keyRetryTimeout = 1000;
	    for each (var ldr: FragLoaderInfo in _loaders)
	    {
	       ldr.retryTimeout = 1000;
	       ldr.retryCount = 0;
	    }
            _seekPosition = position;
            _fragSkipCount = 0;
        }

        public function seekFromLastFrag(lastFrag : Fragment) : void {
            // reset IO Error when seeking
            _keyRetryCount = 0;
            _keyRetryTimeout = 1000;
	    for each (var ldr: FragLoaderInfo in _loaders)
	    {
	       ldr.retryTimeout = 1000;
	       ldr.retryCount = 0;
	    }
            _fragSkipCount = 0;
        }

        /** key load completed. **/
        private function _keyLoadCompleteHandler(event : Event) : void {
            var hlsError : HLSError;
	    var pendingLoaders: Array = [], decrypt_url: String;
	    for (var ldr_id: String in _loaders)
	    {
	        var ldr: FragLoaderInfo = _loaders[ldr_id];
	        if (ldr.pending)
		{
		    pendingLoaders.push(ldr_id);
		    decrypt_url = ldr.frag.decrypt_url;
		}
	    }
            // Collect key data
            if ( _keystreamloader.bytesAvailable == 16 ) {
                // load complete, reset retry counter
                _keyRetryCount = 0;
                _keyRetryTimeout = 1000;
                var keyData : ByteArray = new ByteArray();
                _keystreamloader.readBytes(keyData, 0, 0);
		if (decrypt_url)
                    _keymap[decrypt_url] = keyData;
                // now load fragment
    		for each (ldr_id in pendingLoaders)
		{
		    ldr = _loaders[ldr_id];
		    ldr.pending = false;
                    try {
			ldr.frag.data.bytes = null;
			_hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADING, ldr.frag.url));
		        ldr.loader.load(new URLRequest(ldr.frag.url));
			ExternalInterface.call('console.log', 'XXX frag requested: [level '+ldr.frag.level+'] frag '+ldr.frag.seqnum);
			ldr.loader.req_id = ldr_id;
                    } catch (error : Error) {
                        hlsError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, ldr.frag.url, error.message);
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                    }
		}
            } else {
                hlsError = new HLSError(HLSError.KEY_PARSING_ERROR, decrypt_url||'unknown', "invalid key size: received " + _keystreamloader.bytesAvailable + " / expected 16 bytes");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        };

        private function _keyLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
            _keyLoadStatus = event.status;
        }

        private function _keyhandleIOError(message : String) : void {
            if (HLSSettings.keyLoadMaxRetry == -1 || _keyRetryCount < HLSSettings.keyLoadMaxRetry) {
                _keyLoadErrorDate = getTimer() + _keyRetryTimeout;
                /* exponential increase of retry timeout, capped to keyLoadMaxRetryTimeout */
                _keyRetryCount++;
                _keyRetryTimeout = Math.min(HLSSettings.keyLoadMaxRetryTimeout, 2 * _keyRetryTimeout);
            } else {
	        var decrypt_url: String;
	        for each (var ldr: FragLoaderInfo in _loaders)
		{
		    if (ldr.pending)
		    {
		        decrypt_url = ldr.frag.decrypt_url;
			break;
		    }
		}
                var hlsError : HLSError = new HLSError(HLSError.KEY_LOADING_ERROR, decrypt_url || 'unknown', "I/O Error :" + message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /* in case of parsing error,
            first, try to flush any tags that might have been injected in the NetStream
            then switch to redundant stream if any
            OR level switch down and cap level if in auto mode
            OR skip fragment if allowed to
            if not allowed to, report PARSING error
        */
        private function _handleParsingError(message : String, ldrs: Array, fragData: FragmentData) : void {
	    var frag: Fragment = ldrs[0].frag;
            var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_PARSING_ERROR, frag.url, "Parsing Error :" + message);
            var level : Level = _levels[frag.level];
            // flush any tags that might have been injected for this fragment
            _streamBuffer.flushLastFragment(frag.level, frag.seqnum);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.WARNING, hlsError));
            // if we have redundant streams left for that level, switch to it
            if(level.redundantStreamId < level.redundantStreamsNb)
	    {
                level.redundantStreamId++;
		for each (var ldr: FragLoaderInfo in ldrs)
		{
                    ldr.retryCount = 0;
                    ldr.retryTimeout = 1000;
		}
                // dispatch event to force redundant level loading
                _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, frag.level));
            }
	    else if(HLSSettings.fragmentLoadSkipAfterMaxRetry == true && _fragSkipCount < HLSSettings.maxSkippedFragments  || HLSSettings.maxSkippedFragments < 0)
	    {
                var tags : Vector.<FLVTag> = tags = new Vector.<FLVTag>();
                tags.push(frag.getSkippedTag());
                // send skipped FLV tag to StreamBuffer
                _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, frag.level, frag.seqnum , tags, fragData.pts_start_computed, fragData.pts_start_computed + 1000*frag.duration, frag.continuity, frag.start_time);
		for each (ldr in ldrs)
		{
                    ldr.retryCount = 0;
                    ldr.retryTimeout = 1000;
		}
                _fragSkipCount++;
            } else
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
	    for each (ldr in ldrs)
	        free_ldr(ldr);
        }

        /* in case of IO error,
            retry loading fragment several times if allowed to
            then switch to redundant stream if any
            OR level switch down and cap level if in auto mode
            OR skip fragment if allowed to
            if not allowed to, report LOADING error
        */
        private function _fraghandleIOError(message : String, ldr: FragLoaderInfo) : void {
            var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, ldr.frag.url, "I/O Error while loading fragment:" + message);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.WARNING, hlsError));
            if (HLSSettings.fragmentLoadMaxRetry == -1 || ldr.retryCount < HLSSettings.fragmentLoadMaxRetry) {
                ldr.loadErrorDate = getTimer() + ldr.retryTimeout;
                /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                ldr.retryCount++;
                ldr.retryTimeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * ldr.retryTimeout);
            } else {
                var level : Level = _levels[ldr.frag.level];
                // if we have redundant streams left for that level, switch to it
                if(level.redundantStreamId < level.redundantStreamsNb) {
                    level.redundantStreamId++;
                    ldr.retryCount = 0;
                    ldr.retryTimeout = 1000;
                    // dispatch event to force redundant level loading
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, ldr.frag.level));
                } else if(HLSSettings.fragmentLoadSkipAfterMaxRetry == true && _fragSkipCount < HLSSettings.maxSkippedFragments || HLSSettings.maxSkippedFragments < 0) {
                    /* check if loaded fragment is not the last one of a live playlist.
                        if it is the case, don't skip to next, as there is no next fragment :-)
                    */
                    if(_hls.type == HLSTypes.LIVE && ldr.frag.seqnum == level.end_seqnum) {
                        ldr.loadErrorDate = getTimer() + ldr.retryTimeout;
                        /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                        ldr.retryCount++;
                        ldr.retryTimeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * ldr.retryTimeout);
                    } else {
                        var tags : Vector.<FLVTag> = tags = new Vector.<FLVTag>();
                        tags.push(ldr.frag.getSkippedTag());
                        // send skipped FLV tag to StreamBuffer
                        _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, ldr.frag.level, ldr.frag.seqnum, tags, ldr.frag.data.pts_start_computed, ldr.frag.data.pts_start_computed + 1000*ldr.frag.duration, ldr.frag.continuity, ldr.frag.start_time);
                        ldr.retryCount = 0;
                        ldr.retryTimeout = 1000;
                        _fragSkipCount++;
                    }
                } else {
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                }
            }
	    free_ldr(ldr);
        }

        private function _fragLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
	    ldr_from_req(event.target as JSURLStream).loadStatus = event.status;
        }

        private function _fragLoadProgressHandler(event : ProgressEvent) : void {
	    var ldr: FragLoaderInfo = ldr_from_req(event.target as JSURLStream);
            var fragData : FragmentData = ldr.frag.data;
            if (fragData.bytes == null) {
                fragData.bytes = new ByteArray();
                fragData.bytesLoaded = 0;
                fragData.flushTags();
                ldr.metrics.loading_begin_time = getTimer();

                // decrypt data if needed
                if (ldr.frag.decrypt_url != null) {
                    fragData.decryptAES = new AES(_hls.stage, _keymap[ldr.frag.decrypt_url], ldr.frag.decrypt_iv, _fragDecryptProgressHandler, _fragDecryptCompleteHandler, ldr);
                } else {
                    fragData.decryptAES = null;
                }
            }
            if (event.bytesLoaded > fragData.bytesLoaded && event.target.bytesAvailable > 0)
	    {  
	        // prevent EOF error race condition
                var data : ByteArray = new ByteArray();
                event.target.readBytes(data);
                fragData.bytesLoaded += data.length;
                if (fragData.decryptAES != null) {
                    fragData.decryptAES.append(data);
                } else {
                    _fragDecryptProgressHandler(data, ldr);
                }
            }
        }

        /** frag load completed. **/
        private function _fragLoadCompleteHandler(event : Event) : void {
	    var ldr: FragLoaderInfo = ldr_from_req(event.target as JSURLStream);
	    ExternalInterface.call('console.log', 'XXX frag loaded: [level '+ldr.frag.level+'] frag '+ldr.frag.seqnum);
            var fragData : FragmentData = ldr.frag.data;
            if (fragData.bytes == null) {
                _levels[_hls.loadLevel].updateFragment(ldr.frag.seqnum, false);
                return;
            }
            _fragSkipCount = 0;
            ldr.metrics.loading_end_time = getTimer();
            ldr.metrics.size = fragData.bytesLoaded;
            if (fragData.decryptAES) {
                fragData.decryptAES.notifycomplete();
            } else {
                _fragDecryptCompleteHandler(ldr);
            }
        }

        private function _fragDecryptProgressHandler(data : ByteArray, ldr: FragLoaderInfo) : void {
            if (ldr.metrics.parsing_begin_time == 0)
                ldr.metrics.parsing_begin_time = getTimer();
	    var fragData : FragmentData = ldr.frag.data;
            data.position = 0;
            var bytes : ByteArray = fragData.bytes;
            if (ldr.frag.byterange_start_offset != -1)
	    {
                bytes.position = bytes.length;
                bytes.writeBytes(data);
                // if we have retrieved all the data, disconnect loader and notify fragment complete
                if (bytes.length >= ldr.frag.byterange_end_offset) {
                    if (ldr.loader.connected) {
                        ldr.loader.close();
                        _fragLoadCompleteHandler(null);
                    }
                }
                /* dont do progressive parsing of segment with byte range option */
                return;
            }
	    var scheduler: FragScheduler = sch_from_ldr(ldr);
            if (!scheduler.is_demux_exists())
	    {
                /* probe file type */
                bytes.position = bytes.length;
                bytes.writeBytes(data);
                data = bytes;
		scheduler.create_demux(data);
            }
	    scheduler.append(data, ldr.loader.req_id);
        }

        private function _fragDecryptCompleteHandler(ldr: FragLoaderInfo) : void {
            var fragData : FragmentData = ldr.frag.data;
            if (fragData.decryptAES)
                fragData.decryptAES = null;
	    var scheduler: FragScheduler = sch_from_ldr(ldr);
            // deal with byte range here
            if (ldr.frag.byterange_start_offset != -1) {
                var bytes : ByteArray = new ByteArray();
                fragData.bytes.position = ldr.frag.byterange_start_offset;
                fragData.bytes.readBytes(bytes, 0, ldr.frag.byterange_end_offset - ldr.frag.byterange_start_offset);
		scheduler.create_demux(bytes);
		bytes.position = 0;
		scheduler.append(bytes, ldr.loader.req_id);
            }

            if (!scheduler.is_demux_exists()) {
                // invalid fragment
                _fraghandleIOError("invalid content received", ldr);
                fragData.bytes = null;
                return;
            }
            fragData.bytes = null;
	    scheduler.complete();
        }

        /** stop loading fragment **/
        public function stop() : void {
            _stop_load();
        }

        private function _stop_load() : void {
	    for each (var ldr: FragLoaderInfo in _loaders)
	    {
	        if (ldr.loader.connected)
	            ldr.loader.close();
	    }
            if (_keystreamloader && _keystreamloader.connected) {
                _keystreamloader.close();
            }
            for each (var sch: FragScheduler in _schedulers)
	        sch.stop();
	    for each (ldr in _loaders)
	    {
	        if (ldr.frag)
		{
                    var fragData : FragmentData = ldr.frag.data;
                    if (fragData.decryptAES) {
                        fragData.decryptAES.cancel();
                        fragData.decryptAES = null;
                    }
                    fragData.bytes = null;
		}
	    }
	    _loaders = {};
        }

        /** Catch IO and security errors. **/
        private function _keyLoadErrorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                txt = "Cannot load key: crossdomain access denied:" + event.text;
                code = HLSError.KEY_LOADING_CROSSDOMAIN_ERROR;
            } else {
                _keyhandleIOError("HTTP status:" + _keyLoadStatus + ",msg:" + event.text);
            }
        };

        /** Catch IO and security errors. **/
        private function _fragLoadErrorHandler(event : ErrorEvent) : void {
	    var ldr: FragLoaderInfo = ldr_from_req(event.target as JSURLStream);
            if (event is SecurityErrorEvent) {
                var txt : String = "Cannot load fragment: crossdomain access denied:" + event.text;
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_CROSSDOMAIN_ERROR, ldr.frag.url, txt);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
		free_ldr(ldr);
            } else {
	        var loadStatus: Number = ldr.loadStatus;
                if (loadStatus == 200) {
                    _handleParsingError("HTTP 2OO but IO error, treat as parsing error", [ldr], ldr.frag.data);
                } else {
                    _fraghandleIOError("HTTP status:" + loadStatus + ",msg:" + event.text, ldr);
                }
            }
        };

	public function abortFragment(ldr_id: String): void
	{
	    ExternalInterface.call('console.log', 'XXX frag abort, ldr_id = '+ldr_id);
	    _stop_load();
	}

        public function loadFragment(level: Number, frag: Number, url: String): Object
	{
  	    var levelObj: Level = _levels[level];
	    var f: Fragment = levelObj.getFragmentfromSeqNum(frag);
            var newFrag: Fragment = new Fragment(url, f.duration, f.level, f.seqnum, f.start_time, f.continuity, f.program_date,
	        f.decrypt_url, f.decrypt_iv, f.byterange_start_offset, f.byterange_end_offset, f.tag_list);
 	    ExternalInterface.call('console.log', 'XXX frag request created: [level '+f.level+'] frag '+f.seqnum);
	    return {id: _loadfragment(newFrag)};
	}

        private function _loadfragment(frag : Fragment) : * {
	    var ldr_id: String = 'hap'+(_ldr_id++);
	    var ldr: FragLoaderInfo;
            // postpone URLStream init before loading first fragment
            var urlStreamClass : Class = _hls.URLstream as Class;
            ldr = new FragLoaderInfo();
	    ldr.loader = new JSURLStream();
            ldr.loader.addEventListener(IOErrorEvent.IO_ERROR, _fragLoadErrorHandler);
            ldr.loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _fragLoadErrorHandler);
            ldr.loader.addEventListener(ProgressEvent.PROGRESS, _fragLoadProgressHandler);
            ldr.loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, _fragLoadHTTPStatusHandler);
            ldr.loader.addEventListener(Event.COMPLETE, _fragLoadCompleteHandler);
            ldr.retryTimeout = 1000;
	    ldr.retryCount = 0;
	    if (!_keystreamloader)
	    {
                _keystreamloader = (new urlStreamClass()) as URLStream;
                _keystreamloader.addEventListener(IOErrorEvent.IO_ERROR, _keyLoadErrorHandler);
                _keystreamloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _keyLoadErrorHandler);
                _keystreamloader.addEventListener(HTTPStatusEvent.HTTP_STATUS, _keyLoadHTTPStatusHandler);
                _keystreamloader.addEventListener(Event.COMPLETE, _keyLoadCompleteHandler);
	    }
            ldr.metrics = new HLSLoadMetrics(HLSLoaderTypes.FRAGMENT_MAIN);
            ldr.metrics.level = frag.level;
            ldr.metrics.id = frag.seqnum;
            ldr.metrics.loading_request_time = getTimer();
            ldr.frag = frag;
	    var scheduler: FragScheduler = _schedulers[frag.level+'/'+frag.seqnum];
	    if (!scheduler)
	    {
	        scheduler = _schedulers[frag.level+'/'+frag.seqnum] = new FragScheduler(_audioTrackController, _hls, _levels, _streamBuffer, _schedulerComplete, _schedulerError,
		    _handleParsingError);
    	    }
            scheduler.add_ldr(ldr, ldr_id);
            frag.data.auto_level = _hls.autoLevel;
            if (frag.decrypt_url != null) {
                if (_keymap[frag.decrypt_url] == undefined) {
                    // load key
		    ExternalInterface.call('console.log', 'XXX load key '+frag.decrypt_url);
		    ldr.pending = true;
		    _loaders[ldr_id] = ldr;
                    _keystreamloader.load(new URLRequest(frag.decrypt_url));
                    return ldr_id;
                }
            }
            try {
                frag.data.bytes = null;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADING, frag.url));
		ExternalInterface.call('console.log', 'XXX frag requested: [level '+frag.level+'] frag '+frag.seqnum);
                ldr.loader.load(new URLRequest(frag.url));
		ldr.loader.req_id = ldr_id;
		_loaders[ldr_id] = ldr;
		return ldr_id;
            } catch (error : Error) {
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _levels = event.levels;
        }

	private function _schedulerComplete(_ldrs: Array): void
	{
	    _fragSkipCount = 0;
	    for each (var ldr: FragLoaderInfo in _ldrs)
	        free_ldr(ldr);
	}

        private function _schedulerError(): void
	{
	    _stop_load();
	}
    }
}

import org.mangui.hls.model.Level;
import org.mangui.hls.model.Fragment;
import org.mangui.hls.model.AudioTrack;
import org.mangui.hls.model.FragmentData;
import org.mangui.hls.event.HLSError;
import org.mangui.hls.event.HLSEvent;
import org.mangui.hls.event.HLSLoadMetrics;
import org.mangui.hls.demux.DemuxHelper;
import org.mangui.hls.demux.Demuxer;
import org.mangui.hls.demux.ID3Tag;
import org.mangui.hls.HLS;
import org.mangui.hls.flv.FLVTag;
import org.mangui.hls.stream.StreamBuffer;
import org.mangui.hls.constant.HLSLoaderTypes;
import org.mangui.hls.controller.AudioTrackController;

import org.hola.JSURLStream;

import flash.utils.ByteArray;
import flash.utils.getTimer;
import flash.external.ExternalInterface;

class FragLoaderInfo
{
    public var loader: JSURLStream;
    public var loadErrorDate: Number;
    public var loadStatus: int;
    public var retryCount: int;
    public var retryTimeout: Number;
    public var frag: Fragment;
    public var metrics: HLSLoadMetrics;

    public var pending: Boolean = false;
}

class FragScheduler
{
    private var _demux: Demuxer;
    private var _ldrs: Array = [];
    private var _offsets: Object = {};
    private var _demux_offset: Number = 0;

    private var _fragData: FragmentData;

    private var _audioTrackController: AudioTrackController;
    private var _oncomplete: Function;
    private var _onerror: Function;
    private var _hls: HLS;
    private var _levels: Vector.<Level>;
    private var _streamBuffer: StreamBuffer;
    private var _handleParsingError: Function;

    public function FragScheduler(audioTrackController: AudioTrackController, hls: HLS, levels: Vector.<Level>, streamBuffer: StreamBuffer, oncomplete: Function, onerror: Function,
        handleParsingError: Function)
    {
        _audioTrackController = audioTrackController;
	_hls = hls;
	_oncomplete = oncomplete;
	_onerror = onerror;
	_levels = levels;
	_streamBuffer = streamBuffer;
	_handleParsingError = handleParsingError;
    }

    public function stop(): void
    {
        _demux.cancel();
    }

    public function add_ldr(ldr: FragLoaderInfo, ldr_id: String): void
    {
        _ldrs.push(ldr);
	_offsets[ldr_id] = 0;
    }

    public function is_demux_exists(): Boolean
    {
        return !!_demux;
    }

    public function create_demux(probe: ByteArray): void
    {
        _demux = DemuxHelper.probe(probe, _levels[_ldrs[0].frag.level], _demuxAudioSelectionHandler, _demuxProgressHandler, _demuxCompleteHandler, _demuxErrorHandler, _demuxVideoMetadataHandler, _demuxID3TagHandler, false);
	_demux_offset = 0;
	_fragData = new FragmentData();
    }

    private function _demuxErrorHandler(error : String) : void
    {
        // abort any load in progress
        if (_onerror != null)
	    _onerror();
        // then try to overcome parsing error
        _handleParsingError(error, _ldrs, _fragData);
    }

    /** triggered when demux has completed fragment parsing **/
    private function _demuxCompleteHandler() : void
    {
        var frag: Fragment = _ldrs[0].frag;
        var metrics: HLSLoadMetrics = new HLSLoadMetrics(HLSLoaderTypes.FRAGMENT_MAIN);
        metrics.level = frag.level;
        metrics.id = frag.seqnum;
        var hlsError : HLSError;
        if ((_demux.audioExpected && !_fragData.audio_found) && (_demux.videoExpected && !_fragData.video_found)) {
            // handle it like a parsing error
            _handleParsingError("error parsing fragment, no tag found", _ldrs, _fragData);
            return;
        }
        // Calculate bandwidth
	metrics.loading_request_time = getTimer();
	for each (var ldr: FragLoaderInfo in _ldrs)
	{
	    if (ldr.metrics.loading_request_time < metrics.loading_request_time)
	        metrics.loading_request_time = ldr.metrics.loading_request_time;
	}
        metrics.parsing_end_time = getTimer();
        try {
            var fragLevel : Level = _levels[frag.level];
            if (_fragData.audio_found || _fragData.video_found)
	    {
                fragLevel.updateFragment(frag.seqnum, true, _fragData.pts_min, _fragData.pts_max + _fragData.tag_duration);
                // set pts_start here, it might not be updated directly in updateFragment() if this loaded fragment has been removed from a live playlist
                _fragData.pts_start = _fragData.pts_min;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, fragLevel.duration));
                if (_fragData.tags.length)
		{
                    if (_fragData.metadata_tag_injected == false)
		    {
                        _fragData.tags.unshift(frag.getMetadataTag());
                        _fragData.metadata_tag_injected = true;
                    }
                    _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, frag.level, frag.seqnum, _fragData.tags, _fragData.tag_pts_min, _fragData.tag_pts_max + _fragData.tag_duration, frag.continuity, frag.start_time + _fragData.tag_pts_start_offset / 1000);
                    metrics.duration = _fragData.pts_max + _fragData.tag_duration - _fragData.pts_min;
                    metrics.id2 = _fragData.tags.length;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, metrics));
                    _fragData.shiftTags();
                }
            } else
                metrics.duration = frag.duration * 1000;
            _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, metrics));
        } catch (error : Error) {
            hlsError = new HLSError(HLSError.OTHER_ERROR, frag.url, error.message);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
        }
        ExternalInterface.call('console.log', 'XXX frag completed: [level '+frag.level+'] frag '+frag.seqnum);
	if (_oncomplete != null)
	    _oncomplete(_ldrs);
    }

    /** triggered by demux, it should return the audio track to be parsed */
    private function _demuxAudioSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack
    {
        return _audioTrackController.audioTrackSelectionHandler(audioTrackList);
    }

    private function _demuxID3TagHandler(id3_tags : Vector.<ID3Tag>) : void
    {
        _fragData.id3_tags = id3_tags;
    }

    /** triggered when demux has retrieved some tags from fragment **/
    private function _demuxProgressHandler(tags : Vector.<FLVTag>) : void
    {
        _fragData.appendTags(tags);
    }

    /** triggered by demux, it should return video width/height */
    private function _demuxVideoMetadataHandler(width : uint, height : uint) : void
    {
        if (_fragData.video_width == 0)
	{
            _fragData.video_width = width;
            _fragData.video_height = height;
        }
    }

    public function append(data: ByteArray, ldr_id: String): void
    {
        if (!_demux)
	    return;
	var old_offset: Number = _offsets[ldr_id];
        var ldr_offset: Number = (_offsets[ldr_id] += data.length);
        if (ldr_offset > _demux_offset)
	{
	    if (ldr_offset - _demux_offset == data.length)
                _demux.append(data);
	    else
	    {
	        var ba: ByteArray = new ByteArray();
		ba.writeBytes(data, _demux_offset - old_offset, ldr_offset - _demux_offset);
		_demux.append(ba);
	    }
	    _demux_offset = ldr_offset;
	}
    }

    public function complete(): void
    {
       _demux.notifycomplete();
    }

    public function get audioExpected() : Boolean
    {
        return _demux ? _demux.audioExpected : true;
    }

    public function get videoExpected() : Boolean
    {
        return _demux ? _demux.videoExpected : true;
    }
}

