/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {

    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;
    import flash.utils.Timer;
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
    public class FragmentLoader {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** reference to auto level manager */
        private var _levelController : LevelController;
        /** reference to audio track controller */
        private var _audioTrackController : AudioTrackController;
        /** has manifest just being reloaded **/
        private var _manifestJustLoaded : Boolean;
        /** last loaded level. **/
        private var _levelLastLoaded : int;
        /** next level (-1 if not defined yet) **/
        private var _levelNext : int = -1;
        /** Reference to the manifest levels. **/
        private var _levels : Vector.<Level>;
        /** Util for loading the key. **/
        private var _keystreamloader : URLStream;
        /** key map **/
        private var _keymap : Object;
        /** Did the stream switch quality levels. **/
        private var _switchLevel : Boolean;
        /** Did a discontinuity occurs in the stream **/
        private var _hasDiscontinuity : Boolean;
        /** boolean to track whether PTS analysis is ongoing or not */
        private var _ptsAnalyzing : Boolean = false;
        /** Timer used to monitor/schedule fragment download. **/
        private var _timer : Timer;
        /** requested seek position **/
        private var _seekPosition : Number;
        /** first fragment loaded ? **/
        private var _fragmentFirstLoaded : Boolean;
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
        /** reference to previous/current fragment */
        private var _fragPrevious : Fragment;
        /* loading state variable */
        private var _loadingState : int;

	private var _loaders: Object;
	private var _pendingLoaders: Array = [];

	// XXX marka: fragSkipping is used only at main loop, that is disabled in hap mode, dont need to keep it in loaderInfo
        private var _fragSkipping : Boolean;
        private var _fragSkipCount : int;
        private static const LOADING_STOPPED : int = -1;
        private static const LOADING_IDLE : int = 0;
        private static const LOADING_IN_PROGRESS : int = 1;
        private static const LOADING_WAITING_LEVEL_UPDATE : int = 2;
        private static const LOADING_STALLED : int = 3;
        private static const LOADING_FRAGMENT_IO_ERROR : int = 4;
        private static const LOADING_KEY_IO_ERROR : int = 5;
        private static const LOADING_COMPLETED : int = 6;

        private function _getFirstLoader(): *
	{
	    for (var key: String in _loaders)
	        return _loaders[key];
	}

        /** Create the loader. **/
        public function FragmentLoader(hls : HLS, audioTrackController : AudioTrackController, levelController : LevelController, streamBuffer : StreamBuffer) : void {
            _hls = hls;
            _levelController = levelController;
            _audioTrackController = audioTrackController;
            _streamBuffer = streamBuffer;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADING_ABORTED, _levelLoadingAbortedHandler);
            _timer = new Timer(20, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkLoading);
            _loadingState = LOADING_STOPPED;
            _manifestJustLoaded = false;
            _keymap = new Object();
        };

        public function dispose() : void {
            stop();
            _timer.removeEventListener(TimerEvent.TIMER, _checkLoading);
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADING_ABORTED, _levelLoadingAbortedHandler);
            _loadingState = LOADING_STOPPED;
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

        /**  fragment loading Timer **/
        private function _checkLoading(e : Event) : void {
	    if (HSettings.gets('mode')=='hola_adaptive')
	    {
		_loadingState = LOADING_STOPPED;
		_timer.stop();
	        return;
            }
	    var ldr: FragLoaderInfo = _getFirstLoader();
            switch(_loadingState) {
                // nothing to load, stop fragment loader.
                case LOADING_STOPPED:
                    stop();
                    break;
                // nothing to load until level is retrieved
                case LOADING_WAITING_LEVEL_UPDATE:
                    break;
                // loading already in progress
                case LOADING_IN_PROGRESS:
                    /* only monitor fragment loading rate if in auto mode, AND
                       we are not loading the first segment AND
                       current level is not the lowest level */
                    if(_hls.autoLevel && !_manifestJustLoaded && ldr.frag.level) {
                        // monitor fragment load progress after half of expected fragment duration,to stabilize bitrate
                        var requestDelay : int = getTimer() - ldr.metrics.loading_request_time;
                        var fragDuration : Number = ldr.frag.duration;
                        if(requestDelay > 500*fragDuration) {
                            var loaded : int = ldr.frag.data.bytesLoaded;
                            var expected : int = fragDuration*_levels[ldr.frag.level].bitrate/8;
                            if(expected < loaded) {
                                expected = loaded;
                            }
                            var loadRate : int = loaded*1000/requestDelay; // byte/s
                            var fragLoadedDelay : Number =(expected-loaded)/loadRate;
                            var fragLevel0LoadedDelay : Number = fragDuration*_levels[0].bitrate/(8*loadRate); //bps/Bps
                            var bufferLen : Number = _hls.stream.bufferLength;
                            // CONFIG::LOGGING {
                            //     Log.info("bufferLen/fragDuration/fragLoadedDelay/fragLevel0LoadedDelay:" + bufferLen.toFixed(1) + "/" + fragDuration.toFixed(1) + "/" + fragLoadedDelay.toFixed(1) + "/" + fragLevel0LoadedDelay.toFixed(1));
                            // }
                            /* if we have less than 2 frag duration in buffer and if frag loaded delay is greater than buffer len
                              ... and also bigger than duration needed to load fragment at next level ...*/
                            if(bufferLen < 2*fragDuration && fragLoadedDelay > bufferLen && fragLoadedDelay > fragLevel0LoadedDelay) {
                                // try to abort fragment loading ...
                                // try to flush last fragment seamlessly
                                if(_streamBuffer.flushLastFragment(ldr.frag.level, ldr.frag.seqnum)) {
                                    CONFIG::LOGGING {
                                        Log.warn("_checkLoading : loading too slow, abort fragment loading");
                                        Log.warn("fragLoadedDelay/bufferLen/fragLevel0LoadedDelay:" + fragLoadedDelay.toFixed(1) + "/" + bufferLen.toFixed(1) + "/" + fragLevel0LoadedDelay.toFixed(1));
                                    }
                                    //abort fragment loading
                                    _stop_load();
                                    // fill loadMetrics to please LevelController that will adjust bw for next fragment
                                    // fill theoritical value, assuming bw will remain as it is
                                    ldr.metrics.size = expected;
                                    ldr.metrics.duration = 1000*fragDuration;
                                    ldr.metrics.loading_end_time = ldr.metrics.parsing_end_time = ldr.metrics.loading_request_time + 1000*expected/loadRate;
                                    _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOAD_EMERGENCY_ABORTED, ldr.metrics));
                                    _levelNext = _levelController.getnextlevel(ldr.frag.level, bufferLen);
                                    // ensure that we really switch down to avoid looping here.
                                    // ldr.frag.level is gt 0 in that case, no need to Math.max(0,_levelNext)
                                    _levelNext = Math.min(_levelNext, ldr.frag.level-1);
                                  // switch back to IDLE state to request new fragment at lowest level
                                  _loadingState = LOADING_IDLE;
                                }
                            }
                        }
                    }
                    break;
                // no loading in progress, try to load first/next fragment
                case LOADING_IDLE:
                    var level : int;
                    // check if first fragment after seek has been already loaded
                    if (_fragmentFirstLoaded == false) {
                        // select level for first fragment load
                        if(_levelNext != -1) {
                            level = _levelNext;
                        } else if (_hls.autoLevel) {
                            if (_manifestJustLoaded) {
                                level = _hls.startLevel;
                            } else {
                                if(_hls.stream.bufferLength) {
                                    // if buffer not empty, select level from heuristics
                                    level = _levelController.getnextlevel(_hls.loadLevel, _hls.stream.bufferLength);
                                } else {
                                    // if buffer empty, retrieve seek level
                                    level = _hls.seekLevel;
                                }
                            }
                        } else {
                            level = _hls.manualLevel;
                        }
                        if (level != _hls.loadLevel) {
                            _demux = null;
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, level));
                        }
                        _switchLevel = true;

                        // check if we received playlist for choosen level. if live playlist, ensure that new playlist has been refreshed
                        // to avoid loading outdated fragments
                        if ((_levels[level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _levelLastLoaded != level)) {
                            // playlist not yet received
                            CONFIG::LOGGING {
                                Log.debug("_checkLoading : playlist not received for level:" + level);
                            }
                            _loadingState = LOADING_WAITING_LEVEL_UPDATE;
                            _levelNext = level;
                        } else {
                            // just after seek, load first fragment
                            _loadingState = _loadfirstfragment(_seekPosition, level);
                        }

                        /* first fragment already loaded
                         * check if we need to load next fragment, do it only if buffer is NOT full
                         */
                    } else if (HLSSettings.maxBufferLength == 0 || _hls.stream.bufferLength < HLSSettings.maxBufferLength) {
                        // select level for next fragment load
                        if(_levelNext != -1) {
                            level = _levelNext;
                        } else if (_hls.autoLevel && _levels.length > 1 ) {
                            // select level from heuristics (current level / last fragment duration / buffer length)
                            level = _levelController.getnextlevel(_hls.loadLevel, _hls.stream.bufferLength);
                        } else if (_hls.autoLevel && _levels.length == 1 ) {
                            level = 0;
                        } else {
                            level = _hls.manualLevel;
                        }
                        // notify in case level switch occurs
                        if (level != _hls.loadLevel) {
                            _switchLevel = true;
                            _demux = null;
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, level));
                        }
                        // check if we received playlist for choosen level. if live playlist, ensure that new playlist has been refreshed
                        if ((_levels[level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _levelLastLoaded != level)) {
                            // playlist not yet received
                            CONFIG::LOGGING {
                                Log.debug("_checkLoading : playlist not received for level:" + level);
                            }
                            _loadingState = LOADING_WAITING_LEVEL_UPDATE;
                            _levelNext = level;
                        } else {
                            _loadingState = _loadnextfragment(level, _fragPrevious);
                        }
                    }
                    break;
                case LOADING_STALLED:
                    /* next consecutive fragment not found:
                    it could happen on live playlist :
                    - if bandwidth available is lower than lowest quality needed bandwidth
                    - after long pause
                    */
                    CONFIG::LOGGING {
                        Log.warn("loading stalled:stop fragment loading");
                    }
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LIVE_LOADING_STALLED));
                    stop();
                    break;
                // if key loading failed
                case  LOADING_KEY_IO_ERROR:
                    // compare current date and next retry date.
                    if (getTimer() >= _keyLoadErrorDate) {
                        /* try to reload the key ...
                        calling _loadfragment will also reload key */
                        _loadfragment(ldr.frag);
                        _loadingState = LOADING_IN_PROGRESS;
                    }
                    break;
                // if fragment loading failed
                case LOADING_FRAGMENT_IO_ERROR:
                    // compare current date and next retry date.
                    if (getTimer() >= ldr.loadErrorDate) {
                        /* try to reload fragment ... */
                        _loadfragment(ldr.frag);
                        _loadingState = LOADING_IN_PROGRESS;
                    }
                    break;
                case LOADING_COMPLETED:
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LAST_VOD_FRAGMENT_LOADED));
                    // stop fragment loader, as no other fragments can be loaded
                    stop();
                    break;
                default:
                    CONFIG::LOGGING {
                        Log.error("invalid loading state:" + _loadingState);
                    }
                    break;
            }
        }

        public function seek(position : Number) : void {
            CONFIG::LOGGING {
                Log.debug("FragmentLoader:seek(" + position.toFixed(2) + ")");
            }
            // reset IO Error when seeking
            _keyRetryCount = 0;
            _keyRetryTimeout = 1000;
	    for each (var ldr: FragLoaderInfo in _loaders)
	    {
	       ldr.retryTimeout = 1000;
	       ldr.retryCount = 0;
	    }
            _loadingState = LOADING_IDLE;
            _seekPosition = position;
            _fragmentFirstLoaded = false;
            _fragPrevious = null;
            _fragSkipping = false;
            _fragSkipCount = 0;
            _levelNext = -1;
            _timer.start();
        }

        public function seekFromLastFrag(lastFrag : Fragment) : void {
            CONFIG::LOGGING {
                Log.info("FragmentLoader:seekFromLastFrag(level:" + lastFrag.level + ",SN:" + lastFrag.seqnum + ",PTS:" + lastFrag.data.pts_start +")");
            }
            // reset IO Error when seeking
            _keyRetryCount = 0;
            _keyRetryTimeout = 1000;
	    for each (var ldr: FragLoaderInfo in _loaders)
	    {
	       ldr.retryTimeout = 1000;
	       ldr.retryCount = 0;
	    }
            _loadingState = LOADING_IDLE;
            _fragmentFirstLoaded = true;
            _fragSkipping = false;
            _fragSkipCount = 0;
            _levelNext = -1;
            _fragPrevious = lastFrag;
            _timer.start();
        }

        /** key load completed. **/
        private function _keyLoadCompleteHandler(event : Event) : void {
            if (_loadingState == LOADING_IDLE)
                return;
            CONFIG::LOGGING {
                Log.debug("key loading completed");
            }
            var hlsError : HLSError;
	    var decrypt_url: String = _pendingLoaders.length ? _pendingLoaders[0].frag.decrypt_url : '';
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
    		for (var i: Number = 0, len: Number = _pendingLoaders.length; i < len; i++)
		{
		    var ldr: FragLoaderInfo = _pendingLoaders[i];
                    try {
		        CONFIG::LOGGING {
                            Log.debug("loading fragment:" + ldr.frag.url);
                        }
			ldr.frag.data.bytes = null;
			_hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADING, ldr.frag.url));
		        ldr.loader.load(new URLRequest(ldr.frag.url));
			_loaders[ldr.loader.req_id] = ldr;
                    } catch (error : Error) {
                        hlsError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, ldr.frag.url, error.message);
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                    }
		}
		_pendingLoaders = [];
            } else {
                hlsError = new HLSError(HLSError.KEY_PARSING_ERROR, decrypt_url, "invalid key size: received " + _keystreamloader.bytesAvailable + " / expected 16 bytes");
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
                _loadingState = LOADING_KEY_IO_ERROR;
                _keyLoadErrorDate = getTimer() + _keyRetryTimeout;
                CONFIG::LOGGING {
                    Log.warn("retry key load in " + _keyRetryTimeout + " ms, count=" + _keyRetryCount);
                }
                /* exponential increase of retry timeout, capped to keyLoadMaxRetryTimeout */
                _keyRetryCount++;
                _keyRetryTimeout = Math.min(HLSSettings.keyLoadMaxRetryTimeout, 2 * _keyRetryTimeout);
            } else {
                var hlsError : HLSError = new HLSError(HLSError.KEY_LOADING_ERROR, _pendingLoaders.length ? _pendingLoaders[0].frag.decrypt_url : 'unknown', "I/O Error :" + message);
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
                _loadingState = LOADING_IDLE;
                // dispatch event to force redundant level loading
                _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, ldr.frag.level));
            } else if(_hls.autoLevel && ldr.frag.level) {
                // auto level and not on level 0, try to switch down for next fragment, and cap level to avoid coming back on this one
                _levelNext = ldr.frag.level-1;
                if(_hls.autoLevelCapping == -1) {
                    _hls.autoLevelCapping = _levelNext;
                } else {
                    _hls.autoLevelCapping = Math.min(_levelNext,_hls.autoLevelCapping);
                }
                // switch back to IDLE state to request new fragment at lowest level
                _loadingState = LOADING_IDLE;
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
                _fragPrevious = ldr.frag;
                _fragSkipping = true;
                _fragSkipCount++;
                CONFIG::LOGGING {
                    Log.debug("fragments skipped / max: " + _fragSkipCount + "/" + HLSSettings.maxSkippedFragments );
                }
                // set fragment first loaded to be true to ensure that we can skip first fragment as well
                _fragmentFirstLoaded = true;
                _loadingState = LOADING_IDLE;
            } else {
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
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
                _loadingState = LOADING_FRAGMENT_IO_ERROR;
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
                    _loadingState = LOADING_IDLE;
                    // dispatch event to force redundant level loading
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, ldr.frag.level));
                } else if(_hls.autoLevel && ldr.frag.level) {
                    // auto level and not on level 0, try to switch down for next fragment, and cap level to avoid coming back on this one
                    _levelNext = ldr.frag.level-1;
                    if(_hls.autoLevelCapping == -1) {
                        _hls.autoLevelCapping = _levelNext;
                    } else {
                        _hls.autoLevelCapping = Math.min(_levelNext,_hls.autoLevelCapping);
                    }
                    // switch back to IDLE state to request new fragment at lowest level
                    _loadingState = LOADING_IDLE;
                } else if(HLSSettings.fragmentLoadSkipAfterMaxRetry == true && _fragSkipCount < HLSSettings.maxSkippedFragments || HLSSettings.maxSkippedFragments < 0) {
                    /* check if loaded fragment is not the last one of a live playlist.
                        if it is the case, don't skip to next, as there is no next fragment :-)
                    */
                    if(_hls.type == HLSTypes.LIVE && ldr.frag.seqnum == level.end_seqnum) {
                        _loadingState = LOADING_FRAGMENT_IO_ERROR;
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
                        _fragPrevious = ldr.frag;
                        _fragSkipping = true;
                        _fragSkipCount++;
                        CONFIG::LOGGING {
                            Log.debug("fragments skipped / max: " + _fragSkipCount + "/" + HLSSettings.maxSkippedFragments );
                        }
                        // set fragment first loaded to be true to ensure that we can skip first fragment as well
                        _fragmentFirstLoaded = true;
                        _loadingState = LOADING_IDLE;
                    }
                } else {
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                }
            }
        }

        private function _fragLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
	    _loaders[event.target.req_id].loadStatus = event.status;
        }

        private function _fragLoadProgressHandler(event : ProgressEvent) : void {
	    var ldr: FragLoaderInfo = _loaders[event.target.req_id];
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
	    var ldr: FragLoaderInfo = _loaders[event.target.req_id];
	    ExternalInterface.call('console.log', 'XXX frag loaded: [level '+ldr.frag.level+'] frag '+ldr.frag.seqnum);
            var fragData : FragmentData = ldr.frag.data;
            if (fragData.bytes == null) {
                CONFIG::LOGGING {
                    Log.warn("fragment size is null, invalid it and load next one");
                }
                _levels[_hls.loadLevel].updateFragment(ldr.frag.seqnum, false);
                _loadingState = LOADING_IDLE;
                return;
            }
            CONFIG::LOGGING {
                Log.debug("loading completed");
            }
            _fragSkipping = false;
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
            if (_loadingState == LOADING_IDLE)
                return;
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
	    ExternalInterface.call('console.log', 'XXX frag completed: [level '+ldr.frag.level+'] frag '+ldr.frag.seqnum);
        }

        /** stop loading fragment **/
        public function stop() : void {
            _stop_load();
            _timer.stop();
            _loadingState = LOADING_STOPPED;
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
	    var ldr: FragLoaderInfo = _loaders[event.target.req_id];
            if (event is SecurityErrorEvent) {
                var txt : String = "Cannot load fragment: crossdomain access denied:" + event.text;
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_CROSSDOMAIN_ERROR, ldr.frag.url, txt);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            } else {
	        var loadStatus: Number = ldr.loadStatus;
                if (loadStatus == 200) {
                    _fragHandleParsingError("HTTP 2OO but IO error, treat as parsing error", ldr);
                } else {
                    _fraghandleIOError("HTTP status:" + loadStatus + ",msg:" + event.text, ldr);
                }
            }
        };

        private function _loadfirstfragment(position : Number, level : int) : int {
            CONFIG::LOGGING {
                Log.debug("loadfirstfragment(" + position + ")");
            }
            var frag : Fragment = _levels[level].getFragmentBeforePosition(position);
            _hasDiscontinuity = true;
            CONFIG::LOGGING {
                Log.debug("Loading       " + frag.seqnum + " of [" + (_levels[level].start_seqnum) + "," + (_levels[level].end_seqnum) + "],level " + level);
            }
            _loadfragment(frag);
            return LOADING_IN_PROGRESS;
        }

        /** Load a fragment **/
        private function _loadnextfragment(level : int, frag_previous : Fragment) : int {
            CONFIG::LOGGING {
                Log.debug("loadnextfragment()");
            }
            var new_seqnum : Number;
            var last_seqnum : Number = -1;
            var levelObj : Level = _levels[level];
            var log_prefix : String;
            var frag : Fragment;

            if (_switchLevel == false || frag_previous.continuity == -1) {
                last_seqnum = frag_previous.seqnum;
            } else {
                // level switch
                // trust program-time : if program-time defined in previous loaded fragment, try to find seqnum matching program-time in new level.
                if (frag_previous.program_date) {
                    last_seqnum = levelObj.getSeqNumNearestProgramDate(frag_previous.program_date);
                    CONFIG::LOGGING {
                        Log.debug("loadnextfragment : getSeqNumNearestProgramDate(level,date,cc:" + level + "," + frag_previous.program_date + ")=" + last_seqnum);
                    }
                }
                if (last_seqnum == -1) {
                    // if we are here, it means that no program date info is available in the playlist. try to get last seqnum position from PTS + continuity counter
                    // last_pts is an approximation of last injected PTS of previous fragment
                    var last_pts : Number = frag_previous.data.pts_start_computed+1000*frag_previous.duration;
                    last_seqnum = levelObj.getSeqNumNearestPTS(last_pts, frag_previous.continuity);
                    CONFIG::LOGGING {
                        Log.debug("loadnextfragment : getSeqNumNearestPTS(level,pts,cc:" + level + "," + last_pts + "," + frag_previous.continuity + ")=" + last_seqnum);
                    }
                    last_seqnum--;
                    if (last_seqnum == Number.POSITIVE_INFINITY) {
                        /* requested PTS above max PTS of this level:
                         * this case could happen when loading is completed
                         * or when switching level at the edge of live playlist,
                         * in case playlist of new level is outdated
                         */
                        if (_hls.type == HLSTypes.VOD) {
                            // if VOD playlist, loading is completed
                            return LOADING_COMPLETED;
                        } else {
                            // if live playlist, loading is pending on manifest update
                            return LOADING_WAITING_LEVEL_UPDATE;
                        }
                    } else if (last_seqnum < -1) {
                        // if we are here, it means that we have no PTS info for this continuity index, we need to do some PTS probing to find the right seqnum
                        /* we need to perform PTS analysis on fragments from same continuity range
                        get first fragment from playlist matching with criteria and load pts */
                        last_seqnum = levelObj.getFirstSeqNumfromContinuity(frag_previous.continuity);
                        CONFIG::LOGGING {
                            Log.debug("loadnextfragment : getFirstSeqNumfromContinuity(level,cc:" + level + "," + frag_previous.continuity + ")=" + last_seqnum);
                        }
                        if (last_seqnum == Number.NEGATIVE_INFINITY) {
                            // playlist not yet received
                            return LOADING_WAITING_LEVEL_UPDATE;
                        }
                        /* when probing PTS, take previous sequence number as reference if possible */
                        new_seqnum = Math.min(frag_previous.seqnum + 1, levelObj.getLastSeqNumfromContinuity(frag_previous.continuity));
                        new_seqnum = Math.max(new_seqnum, levelObj.getFirstSeqNumfromContinuity(frag_previous.continuity));
                        _ptsAnalyzing = true;
                        log_prefix = "analyzing PTS ";
                    } else {
                        // last seqnum found on new level, reset PTS analysis flag
                        _ptsAnalyzing = false;
                    }
                }
            }

            if (_ptsAnalyzing == false) {
                if (last_seqnum == levelObj.end_seqnum) {
                    // if last segment of level already loaded, return
                    if (_hls.type == HLSTypes.VOD) {
                        // if VOD playlist, loading is completed
                        return LOADING_COMPLETED;
                    } else {
                        // if live playlist, loading is pending on manifest update
                        return LOADING_WAITING_LEVEL_UPDATE;
                    }
                } else {
                    // if previous segment is not the last one, increment it to get new seqnum
                    new_seqnum = last_seqnum + 1;
                    if (new_seqnum < levelObj.start_seqnum) {
                        // loading stalled ! report to caller
                        return LOADING_STALLED;
                    }
                    frag = levelObj.getFragmentfromSeqNum(new_seqnum);
                    if (frag == null) {
                        CONFIG::LOGGING {
                            Log.warn("error trying to load " + new_seqnum + " of [" + (levelObj.start_seqnum) + "," + (levelObj.end_seqnum) + "],level " + level);
                        }
                        return LOADING_WAITING_LEVEL_UPDATE;
                    }
                    // check whether there is a discontinuity between last segment and new segment
                    _hasDiscontinuity = ((frag.continuity != frag_previous.continuity) || _fragSkipping);
                    ;
                    log_prefix = "Loading       ";
                }
            }
            frag = levelObj.getFragmentfromSeqNum(new_seqnum);
            CONFIG::LOGGING {
                Log.debug(log_prefix + new_seqnum + " of [" + (levelObj.start_seqnum) + "," + (levelObj.end_seqnum) + "],level " + level);
            }
            _loadfragment(frag);
            return LOADING_IN_PROGRESS;
        };

	public function abortFragment(req_id: Number): void
	{
	    ExternalInterface.call('console.log', 'XXX frag abort, req_id = '+req_id);
	    _stop_load();
	}

        public function loadFragment(level: Number, frag: Number, url: String): Object
	{
  	    var levelObj: Level = _levels[level];
	    var f: Fragment = levelObj.getFragmentfromSeqNum(frag);
            var newFrag: Fragment = new Fragment(url, f.duration, f.level, f.seqnum, f.start_time, f.continuity, f.program_date,
	        f.decrypt_url, f.decrypt_iv, f.byterange_start_offset, f.byterange_end_offset, f.tag_list);
	    var req_id: String = _loadfragment(newFrag);
	    ExternalInterface.call('console.log', 'XXX frag request created: [level '+f.level+'] frag '+f.seqnum+', req_id = '+req_id);
	    return {id: req_id};
	}

        private function _loadfragment(frag : Fragment) : * {
            ExternalInterface.call('console.log', 'XXX FLASH - loadFragment()!');
	    var is_hap: Boolean = HSettings.gets('mode')=='hola_adaptive';
	    var ldr: FragLoaderInfo;
            // postpone URLStream init before loading first fragment
            if (is_hap || !(ldr = _getFirstLoader())) {
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
            }
	    if (!_keystreamloader)
	    {
                _keystreamloader = (new urlStreamClass()) as URLStream;
                _keystreamloader.addEventListener(IOErrorEvent.IO_ERROR, _keyLoadErrorHandler);
                _keystreamloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _keyLoadErrorHandler);
                _keystreamloader.addEventListener(HTTPStatusEvent.HTTP_STATUS, _keyLoadHTTPStatusHandler);
                _keystreamloader.addEventListener(Event.COMPLETE, _keyLoadCompleteHandler);
	    }
            if (_hasDiscontinuity || _switchLevel) {
                _demux = null;
            }
            ldr.metrics = new HLSLoadMetrics(HLSLoaderTypes.FRAGMENT_MAIN);
            ldr.metrics.level = frag.level;
            ldr.metrics.id = frag.seqnum;
            ldr.metrics.loading_request_time = getTimer();
            ldr.frag = frag;
            frag.data.auto_level = _hls.autoLevel;
            if (frag.decrypt_url != null) {
                if (_keymap[frag.decrypt_url] == undefined) {
                    // load key
                    CONFIG::LOGGING {
                        Log.debug("loading key:" + frag.decrypt_url);
                    }
		    ExternalInterface.call('console.log', 'XXX _loadfragment: load key '+frag.decrypt_url);
		    _pendingLoaders.push(ldr);
                    _keystreamloader.load(new URLRequest(frag.decrypt_url));
                    return;
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
		var req_id: String = ldr.loader.req_id;
		if (!is_hap)
		    _loaders = {};
		_loaders[req_id] = ldr;
		return req_id;
            } catch (error : Error) {
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _levels = event.levels;
            _manifestJustLoaded = true;
        };

        /** Store the manifest data. **/
        private function _levelLoadedHandler(event : HLSEvent) : void {
            _levelLastLoaded = event.loadMetrics.level;
            if (_loadingState == LOADING_WAITING_LEVEL_UPDATE && _levelLastLoaded == _hls.loadLevel) {
                _loadingState = LOADING_IDLE;
            }
            // speed up loading of new fragment
            _timer.start();
        };

        /** Store the manifest data. **/
        private function _levelLoadingAbortedHandler(event : HLSEvent) : void {
            _levelNext = event.level-1;
            CONFIG::LOGGING {
                Log.warn("FragmentLoader:_levelLoadingAbortedHandler:switch down to:" + _levelNext);
            }
            _loadingState = LOADING_IDLE;
            // speed up loading of new playlist/fragment
            _timer.start();
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

            /* try to do progressive buffering here.
             * only do it in case :
             *      first fragment is already loaded
             *      or if first fragment is not loaded, we can do it if
             *          startLevel is already defined (startLevel is already set or
             *          startFromLevel/startFromBitrate not set to -1
             *          or we only have one quality level
             *      in the other cases, flashls will first download one fragment at level 0 to measure dl bw, used to assess start level ...)
             */
            if (( !_manifestJustLoaded ||
                (_levelController.isStartLevelSet() ||
                 HLSSettings.startFromLevel !== -1 ||
                 HLSSettings.startFromBitrate !== -1 ||
                 _levels.length == 1))) {
                /* if audio expected, PTS analysis is done on audio
                 * if audio not expected, PTS analysis is done on video
                 * the check below ensures that we can compute min/max PTS
                 */
                if ((_demux.audioExpected && fragData.audio_found) || (!_demux.audioExpected && fragData.video_found)) {
                    if (_ptsAnalyzing == true) {
                        var levelObj : Level = _levels[_hls.loadLevel];
                        _ptsAnalyzing = false;
                        levelObj.updateFragment(ldr.frag.seqnum, true, fragData.pts_min, fragData.pts_min + ldr.frag.duration * 1000);
                        /* in case we are probing PTS, retrieve PTS info and synchronize playlist PTS / sequence number */
                        CONFIG::LOGGING {
                            Log.debug("analyzed PTS " + ldr.frag.seqnum + " of [" + (levelObj.start_seqnum) + "," + (levelObj.end_seqnum) + "],level " + _hls.loadLevel + " m PTS:" + fragData.pts_min);
                        }
                        /* check if fragment loaded for PTS analysis is the next one
                        if this is the expected one, then continue
                        if not, then cancel current fragment loading, next call to loadnextfragment() will load the right seqnum
                         */
                        var next_pts:Number;
                        var next_seqnum:Number;
                        
                        // Resolves intermittent issue that causes the player to crash due to missing previous fragment data while seeking
                        if (_fragPrevious && _fragPrevious.data) {
                            next_pts = _fragPrevious.data.pts_start_computed + 1000*_fragPrevious.duration;
                            next_seqnum = levelObj.getSeqNumNearestPTS(next_pts, ldr.frag.continuity);
                        } else {
                            CONFIG::LOGGING {
                                Log.debug("Previous fragment data not found while analyzing PTS!");
                            }
                        }
                        
                        CONFIG::LOGGING {
                            Log.debug("analyzed PTS : getSeqNumNearestPTS(level,pts,cc:" + _hls.loadLevel + "," + next_pts + "," + ldr.frag.continuity + ")=" + next_seqnum);
                        }
                        // CONFIG::LOGGING {
                        // Log.info("seq/next:"+ _seqnum+"/"+ next_seqnum);
                        // }
                        if (next_seqnum !== ldr.frag.seqnum) {
                            // stick to same level after PTS analysis
                            _levelNext = _hls.loadLevel;
                            CONFIG::LOGGING {
                                Log.debug("PTS analysis done on " + ldr.frag.seqnum + ", matching seqnum is " + next_seqnum + " of [" + (levelObj.start_seqnum) + "," + (levelObj.end_seqnum) + "],cancel loading and get new one");
                            }
                            // cancel loading
                            _stop_load();
                            // clean-up tags
                            fragData.flushTags();
                            // tell that new fragment could be loaded
                            _loadingState = LOADING_IDLE;
                            return;
                        }
                    }
                    if (fragData.metadata_tag_injected == false) {
                        fragData.tags.unshift(ldr.frag.getMetadataTag());
                        if (_hasDiscontinuity) {
                            fragData.tags.unshift(new FLVTag(FLVTag.DISCONTINUITY, fragData.dts_min, fragData.dts_min, false));
                        }
                        fragData.metadata_tag_injected = true;
                    }
                    // provide tags to StreamBuffer
                    _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, ldr.frag.level, ldr.frag.seqnum, fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, ldr.frag.continuity, ldr.frag.start_time + fragData.tag_pts_start_offset / 1000);
                    ldr.metrics.parsing_end_time = getTimer();
                    ldr.metrics.size = fragData.bytesLoaded;
                    ldr.metrics.duration = fragData.tag_pts_end_offset;
                    ldr.metrics.id2 = fragData.tags.length;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, ldr.metrics));
                    fragData.shiftTags();
                    _hasDiscontinuity = false;
                }
            }
        }

        /** triggered when demux has completed fragment parsing **/
        private function _fragParsingCompleteHandler(ldr: FragLoaderInfo) : void {
            if (_loadingState == LOADING_IDLE)
                return;
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

            if (_manifestJustLoaded) {
                _manifestJustLoaded = false;
                if (HLSSettings.startFromLevel === -1 && HLSSettings.startFromBitrate === -1 && _levels.length > 1 && !_levelController.isStartLevelSet()) {
                    // check if we can directly switch to a better bitrate, in case download bandwidth is enough
                    var bestlevel : int = _levelController.getAutoStartBestLevel(ldr.metrics.bandwidth,ldr.metrics.processing_duration, 1000*ldr.frag.duration);
                    if (bestlevel > fragLevelIdx) {
                        CONFIG::LOGGING {
                            Log.info("enough download bandwidth, adjust start level from 0 to " + bestlevel);
                        }
                        // dispatch event for tracking purpose
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, ldr.metrics));
                        // let's directly jump to the accurate level to improve quality at player start
                        _levelNext = bestlevel;
                        _loadingState = LOADING_IDLE;
                        _switchLevel = true;
                        _demux = null;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, fragLevelIdx));
                        // speed up loading of new playlist
                        _timer.start();
                        return;
                    }
                }
            }

            try {
                _switchLevel = false;
                _levelNext = -1;
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
                            if (_hasDiscontinuity) {
                                fragData.tags.unshift(new FLVTag(FLVTag.DISCONTINUITY, fragData.dts_min, fragData.dts_min, false));
                            }
                            fragData.metadata_tag_injected = true;
                        }
                        _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, ldr.frag.level, ldr.frag.seqnum, fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, ldr.frag.continuity, ldr.frag.start_time + fragData.tag_pts_start_offset / 1000);
                        ldr.metrics.duration = fragData.pts_max + fragData.tag_duration - fragData.pts_min;
                        ldr.metrics.id2 = fragData.tags.length;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, ldr.metrics));
                        fragData.shiftTags();
                        _hasDiscontinuity = false;
                    }
                } else {
                    ldr.metrics.duration = ldr.frag.duration * 1000;
                }
                _loadingState = LOADING_IDLE;
                _ptsAnalyzing = false;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, ldr.metrics));
                _fragmentFirstLoaded = true;
                _fragPrevious = ldr.frag;
            } catch (error : Error) {
                hlsError = new HLSError(HLSError.OTHER_ERROR, ldr.frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            // speed up loading of new fragment
            _timer.start();
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
    public var prevFrag: Fragment;
    public var metrics: HLSLoadMetrics;

    public function get id(): String
    {
        return loader.req_id;
    }
}
