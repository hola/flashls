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

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
        import org.mangui.hls.utils.Hex;
    }

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
        /* demux instance */
        private var _demux : Demuxer;
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

        private var _fragSkipCount : int;

        private function ldr_from_req(loader: JSURLStream): FragLoaderInfo
	{
	    return _loaders[loader.req_id];
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

        public function get audioExpected() : Boolean {
            if (_demux) {
                return _demux.audioExpected;
            } else {
                // always return true in case demux is not yet initialized
                return true;
            }
        }

        public function get videoExpected() : Boolean {
            if (_demux) {
                return _demux.videoExpected;
            } else {
                // always return true in case demux is not yet initialized
                return true;
            }
        }

        public function seek(position : Number) : void {
            CONFIG::LOGGING {
                Log.debug("HolaFragmentLoader:seek(" + position.toFixed(2) + ")");
            }
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
            CONFIG::LOGGING {
                Log.info("HolaFragmentLoader:seekFromLastFrag(level:" + lastFrag.level + ",SN:" + lastFrag.seqnum + ",PTS:" + lastFrag.data.pts_start +")");
            }
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
            CONFIG::LOGGING {
                Log.debug("key loading completed");
            }
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
		        CONFIG::LOGGING {
                            Log.debug("loading fragment:" + ldr.frag.url);
                        }
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
            CONFIG::LOGGING {
                Log.error("I/O Error while loading key:" + message);
            }
            if (HLSSettings.keyLoadMaxRetry == -1 || _keyRetryCount < HLSSettings.keyLoadMaxRetry) {
                _keyLoadErrorDate = getTimer() + _keyRetryTimeout;
                CONFIG::LOGGING {
                    Log.warn("retry key load in " + _keyRetryTimeout + " ms, count=" + _keyRetryCount);
                }
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
        private function _fragHandleParsingError(message : String, ldr: FragLoaderInfo) : void {
            var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_PARSING_ERROR, ldr.frag.url, "Parsing Error :" + message);
            var level : Level = _levels[ldr.frag.level];
            CONFIG::LOGGING {
                Log.warn(hlsError.msg);
            }
            // flush any tags that might have been injected for this fragment
            _streamBuffer.flushLastFragment(ldr.frag.level, ldr.frag.seqnum);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.WARNING, hlsError));
            // if we have redundant streams left for that level, switch to it
            if(level.redundantStreamId < level.redundantStreamsNb) {
                CONFIG::LOGGING {
                    Log.warn("parsing error, switch to redundant stream");
                }
                level.redundantStreamId++;
                ldr.retryCount = 0;
                ldr.retryTimeout = 1000;
                // dispatch event to force redundant level loading
                _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, ldr.frag.level));
            } else if(HLSSettings.fragmentLoadSkipAfterMaxRetry == true && _fragSkipCount < HLSSettings.maxSkippedFragments  || HLSSettings.maxSkippedFragments < 0) {
                CONFIG::LOGGING {
                    Log.warn("error parsing fragment, skip it and load next one");
                }
                var tags : Vector.<FLVTag> = tags = new Vector.<FLVTag>();
                tags.push(ldr.frag.getSkippedTag());
                // send skipped FLV tag to StreamBuffer
                _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, ldr.frag.level, ldr.frag.seqnum , tags, ldr.frag.data.pts_start_computed, ldr.frag.data.pts_start_computed + 1000*ldr.frag.duration, ldr.frag.continuity, ldr.frag.start_time);
                ldr.retryCount = 0;
                ldr.retryTimeout = 1000;
                _fragSkipCount++;
                CONFIG::LOGGING {
                    Log.debug("fragments skipped / max: " + _fragSkipCount + "/" + HLSSettings.maxSkippedFragments );
                }
            } else {
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
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
            CONFIG::LOGGING {
                Log.warn(hlsError.msg);
            }
            if (HLSSettings.fragmentLoadMaxRetry == -1 || ldr.retryCount < HLSSettings.fragmentLoadMaxRetry) {
                ldr.loadErrorDate = getTimer() + ldr.retryTimeout;
                CONFIG::LOGGING {
                    Log.warn("retry fragment load in " + ldr.retryTimeout + " ms, count=" + ldr.retryCount);
                }
                /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                ldr.retryCount++;
                ldr.retryTimeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * ldr.retryTimeout);
            } else {
                var level : Level = _levels[ldr.frag.level];
                // if we have redundant streams left for that level, switch to it
                if(level.redundantStreamId < level.redundantStreamsNb) {
                    CONFIG::LOGGING {
                        Log.warn("max load retry reached, switch to redundant stream");
                    }
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
                        CONFIG::LOGGING {
                            Log.warn("max load retry reached on last fragment of live playlist, retrying loading this one...");
                        }
                        /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                        ldr.retryCount++;
                        ldr.retryTimeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * ldr.retryTimeout);
                    } else {
                        CONFIG::LOGGING {
                            Log.warn("max fragment load retry reached, skip fragment and load next one.");
                        }
                        var tags : Vector.<FLVTag> = tags = new Vector.<FLVTag>();
                        tags.push(ldr.frag.getSkippedTag());
                        // send skipped FLV tag to StreamBuffer
                        _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, ldr.frag.level, ldr.frag.seqnum, tags, ldr.frag.data.pts_start_computed, ldr.frag.data.pts_start_computed + 1000*ldr.frag.duration, ldr.frag.continuity, ldr.frag.start_time);
                        ldr.retryCount = 0;
                        ldr.retryTimeout = 1000;
                        _fragSkipCount++;
                        CONFIG::LOGGING {
                            Log.debug("fragments skipped / max: " + _fragSkipCount + "/" + HLSSettings.maxSkippedFragments );
                        }
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
                    ldr.metrics.decryption_begin_time = getTimer();
                    fragData.decryptAES = new AES(_hls.stage, _keymap[ldr.frag.decrypt_url], ldr.frag.decrypt_iv, _fragDecryptProgressHandler, _fragDecryptCompleteHandler, ldr);
                    CONFIG::LOGGING {
                        Log.debug("init AES context");
                    }
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
                // CONFIG::LOGGING {
                // Log.debug2("bytesLoaded/bytesTotal:" + event.bytesLoaded + "/" + event.bytesTotal);
                // }
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
                CONFIG::LOGGING {
                    Log.warn("fragment size is null, invalid it and load next one");
                }
                _levels[_hls.loadLevel].updateFragment(ldr.frag.seqnum, false);
                return;
            }
            CONFIG::LOGGING {
                Log.debug("loading completed");
            }
            _fragSkipCount = 0;
            ldr.metrics.loading_end_time = getTimer();
            ldr.metrics.size = fragData.bytesLoaded;

            var _loading_duration : uint = ldr.metrics.loading_end_time - ldr.metrics.loading_request_time;
            CONFIG::LOGGING {
                Log.debug("Loading       duration/RTT/length/speed:" + _loading_duration + "/" + (ldr.metrics.loading_begin_time - ldr.metrics.loading_request_time) + "/" + ldr.metrics.size + "/" + Math.round((8000 * ldr.metrics.size / _loading_duration) / 1024) + " kb/s");
            }
            if (fragData.decryptAES) {
                fragData.decryptAES.notifycomplete();
            } else {
                _fragDecryptCompleteHandler(ldr);
            }
        }

        private function _fragDecryptProgressHandler(data : ByteArray, ldr: FragLoaderInfo) : void {
            data.position = 0;
            var fragData : FragmentData = ldr.frag.data;
            if (ldr.metrics.parsing_begin_time == 0) {
                ldr.metrics.parsing_begin_time = getTimer();
            }
            var bytes : ByteArray = fragData.bytes;
            if (ldr.frag.byterange_start_offset != -1) {
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
            if (_demux == null) {
                /* probe file type */
                bytes.position = bytes.length;
                bytes.writeBytes(data);
                data = bytes;
                _demux = DemuxHelper.probe(data, _levels[_hls.loadLevel], _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, _fragParsingErrorHandler, _fragParsingVideoMetadataHandler, _fragParsingID3TagHandler, false, ldr);
            }
            if (_demux) {
                _demux.append(data);
            }
        }

        private function _fragDecryptCompleteHandler(ldr: FragLoaderInfo) : void {
            var fragData : FragmentData = ldr.frag.data;

            if (fragData.decryptAES) {
                ldr.metrics.decryption_end_time = getTimer();
                var decrypt_duration : Number = ldr.metrics.decryption_end_time - ldr.metrics.decryption_begin_time;
                CONFIG::LOGGING {
                    Log.debug("Decrypted     duration/length/speed:" + decrypt_duration + "/" + fragData.bytesLoaded + "/" + Math.round((8000 * fragData.bytesLoaded / decrypt_duration) / 1024) + " kb/s");
                }
                fragData.decryptAES = null;
            }

            // deal with byte range here
            if (ldr.frag.byterange_start_offset != -1) {
                CONFIG::LOGGING {
                    Log.debug("trim byte range, start/end offset:" + ldr.frag.byterange_start_offset + "/" + ldr.frag.byterange_end_offset);
                }
                var bytes : ByteArray = new ByteArray();
                fragData.bytes.position = ldr.frag.byterange_start_offset;
                fragData.bytes.readBytes(bytes, 0, ldr.frag.byterange_end_offset - ldr.frag.byterange_start_offset);
                _demux = DemuxHelper.probe(bytes, _levels[_hls.loadLevel], _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, _fragParsingErrorHandler, _fragParsingVideoMetadataHandler, _fragParsingID3TagHandler, false, ldr);
                if (_demux) {
                    bytes.position = 0;
                    _demux.append(bytes);
                }
            }

            if (_demux == null) {
                CONFIG::LOGGING {
                    Log.error("unknown fragment type");
                    if (HLSSettings.logDebug2) {
                        fragData.bytes.position = 0;
                        var bytes2 : ByteArray = new ByteArray();
                        fragData.bytes.readBytes(bytes2, 0, 512);
                        Log.debug2("frag dump(512 bytes)");
                        Log.debug2(Hex.fromArray(bytes2));
                    }
                }
                // invalid fragment
                _fraghandleIOError("invalid content received", ldr);
                fragData.bytes = null;
                return;
            }
            fragData.bytes = null;
            _demux.notifycomplete();
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

            if (_demux) {
                _demux.cancel();
            }
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
                    _fragHandleParsingError("HTTP 2OO but IO error, treat as parsing error", ldr);
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
	    var ldr_id: String = _loadfragment(newFrag);
	    return {id: ldr_id};
	}

        private function _loadfragment(frag : Fragment) : * {
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
            frag.data.auto_level = _hls.autoLevel;
	    var ldr_id: String = 'hap'+(_ldr_id++);
            if (frag.decrypt_url != null) {
                if (_keymap[frag.decrypt_url] == undefined) {
                    // load key
                    CONFIG::LOGGING {
                        Log.debug("loading key:" + frag.decrypt_url);
                    }
		    ExternalInterface.call('console.log', 'XXX load key '+frag.decrypt_url);
		    ldr.pending = true;
		    _loaders[ldr_id] = ldr;
                    _keystreamloader.load(new URLRequest(frag.decrypt_url));
                    return ldr_id;
                }
            }
            try {
                frag.data.bytes = null;
                CONFIG::LOGGING {
                    Log.debug("loading fragment:" + frag.url);
                }
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
        };

        private function _fragParsingErrorHandler(error : String, ldr: FragLoaderInfo) : void {
            // abort any load in progress
            _stop_load();
            // then try to overcome parsing error
            _fragHandleParsingError(error, ldr);
        }

        private function _fragParsingID3TagHandler(id3_tags : Vector.<ID3Tag>, ldr: FragLoaderInfo) : void {
            ldr.frag.data.id3_tags = id3_tags;
        }

        /** triggered by demux, it should return the audio track to be parsed */
        private function _fragParsingAudioSelectionHandler(audioTrackList : Vector.<AudioTrack>, ldr: FragLoaderInfo) : AudioTrack {
            return _audioTrackController.audioTrackSelectionHandler(audioTrackList);
        }

        /** triggered by demux, it should return video width/height */
        private function _fragParsingVideoMetadataHandler(width : uint, height : uint, ldr: FragLoaderInfo) : void {
            var fragData : FragmentData = ldr.frag.data;
            if (fragData.video_width == 0) {
                CONFIG::LOGGING {
                    Log.debug("AVC: width/height:" + width + "/" + height);
                }
                fragData.video_width = width;
                fragData.video_height = height;
            }
        }

        /** triggered when demux has retrieved some tags from fragment **/
        private function _fragParsingProgressHandler(tags : Vector.<FLVTag>, ldr: FragLoaderInfo) : void {
            CONFIG::LOGGING {
                Log.debug2(tags.length + " tags extracted");
            }
            var fragData : FragmentData = ldr.frag.data;
            fragData.appendTags(tags);
        }

        /** triggered when demux has completed fragment parsing **/
        private function _fragParsingCompleteHandler(ldr: FragLoaderInfo) : void {
            var hlsError : HLSError;
            var fragData : FragmentData = ldr.frag.data;
            var fragLevelIdx : int = ldr.frag.level;
            if ((_demux.audioExpected && !fragData.audio_found) && (_demux.videoExpected && !fragData.video_found)) {
                // handle it like a parsing error
                _fragHandleParsingError("error parsing fragment, no tag found", ldr);
                return;
            }
            // parsing complete, reset retry and skip counters
            ldr.retryCount = 0;
            ldr.retryTimeout = 1000;
            _fragSkipCount = 0;
            CONFIG::LOGGING {
                if (fragData.audio_found) {
                    Log.debug("m/M audio PTS:" + fragData.pts_min_audio + "/" + fragData.pts_max_audio);
                }
                if (fragData.video_found) {
                    Log.debug("m/M video PTS:" + fragData.pts_min_video + "/" + fragData.pts_max_video);

                    if (!fragData.audio_found) {
                    } else {
                        Log.debug("Delta audio/video m/M PTS:" + (fragData.pts_min_video - fragData.pts_min_audio) + "/" + (fragData.pts_max_video - fragData.pts_max_audio));
                    }
                }
            }

            // Calculate bandwidth
            ldr.metrics.parsing_end_time = getTimer();
            CONFIG::LOGGING {
                Log.debug("Total Process duration/length/bw:" + ldr.metrics.processing_duration + "/" + ldr.metrics.size + "/" + Math.round(ldr.metrics.bandwidth / 1024) + " kb/s");
            }

            try {
                var fragLevel : Level = _levels[fragLevelIdx];
                CONFIG::LOGGING {
                    Log.debug("Loaded        " + ldr.frag.seqnum + " of [" + (fragLevel.start_seqnum) + "," + (fragLevel.end_seqnum) + "],level " + fragLevelIdx + " m/M PTS:" + fragData.pts_min + "/" + fragData.pts_max);
                }
                if (fragData.audio_found || fragData.video_found) {
                    fragLevel.updateFragment(ldr.frag.seqnum, true, fragData.pts_min, fragData.pts_max + fragData.tag_duration);
                    // set pts_start here, it might not be updated directly in updateFragment() if this loaded fragment has been removed from a live playlist
                    fragData.pts_start = fragData.pts_min;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, fragLevel.duration));
                    if (fragData.tags.length) {
                        if (fragData.metadata_tag_injected == false) {
                            fragData.tags.unshift(ldr.frag.getMetadataTag());
                            fragData.metadata_tag_injected = true;
                        }
                        _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, ldr.frag.level, ldr.frag.seqnum, fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, ldr.frag.continuity, ldr.frag.start_time + fragData.tag_pts_start_offset / 1000);
                        ldr.metrics.duration = fragData.pts_max + fragData.tag_duration - fragData.pts_min;
                        ldr.metrics.id2 = fragData.tags.length;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, ldr.metrics));
                        fragData.shiftTags();
                    }
                } else {
                    ldr.metrics.duration = ldr.frag.duration * 1000;
                }
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, ldr.metrics));
            } catch (error : Error) {
                hlsError = new HLSError(HLSError.OTHER_ERROR, ldr.frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
   	    ExternalInterface.call('console.log', 'XXX frag completed: [level '+ldr.frag.level+'] frag '+ldr.frag.seqnum);
	    free_ldr(ldr);
        }
    }
}

import org.mangui.hls.event.HLSLoadMetrics;
import org.mangui.hls.model.Fragment;
import org.hola.JSURLStream;

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
