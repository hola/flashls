/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.TimerEvent;
    import flash.external.ExternalInterface;
    import flash.net.URLRequest;
    import flash.net.URLLoader;

    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    // Playlist Loader
    public dynamic class JSURLLoader extends URLLoader {
        private var _resource : String = new String();
        /* callback names */
        private var _callbackLoaded : String;
        private var _callbackFailure : String;
        private static var _instanceCount : int = 0;

        public function JSURLLoader() {
            super();
            // Connect calls to JS.
            if (ExternalInterface.available) {
                CONFIG::LOGGING {
                    Log.debug("add callback resourceLoaded, id:" + _instanceCount);
                }
                _callbackLoaded = "textLoaded" + _instanceCount;
                _callbackFailure = "textLoadingError" + _instanceCount;
                // dynamically register callbacks
                this[_callbackLoaded] = function(res): void { resourceLoaded(res)};
                this[_callbackFailure] = function() : void { resourceLoadingError()};
                ExternalInterface.addCallback(_callbackLoaded, this[_callbackLoaded]);
                ExternalInterface.addCallback(_callbackFailure, this[_callbackFailure]);
                _instanceCount++;
            }
        }

        override public function close() : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("JSLoaderPlaylist.onRequestAbort",ExternalInterface.objectID);
            } else {
                super.close();
            }
        }

        override public function load(request : URLRequest) : void {
            CONFIG::LOGGING {
            Log.debug("JSURLLoader.load:" + request.url);
            }
            bytesLoaded = bytesTotal = 0;
            data = null;
            if (ExternalInterface.available) {
                ExternalInterface.call("JSLoaderPlaylist.onRequestResource",ExternalInterface.objectID, request.url,_callbackLoaded,_callbackFailure);
                this.dispatchEvent(new Event(Event.OPEN));
            } else {
                super.load(request);
            }
        }

        protected function resourceLoaded(resource : String) : void {
            CONFIG::LOGGING {
              Log.debug("resourceLoaded");
            }
            data = resource;
            bytesLoaded = bytesTotal = resource.length;
            this.dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, bytesLoaded, bytesTotal));
            this.dispatchEvent(new Event(Event.COMPLETE));
        }

        protected function resourceLoadingError() : void {
            CONFIG::LOGGING {
                Log.debug("resourceLoadingError");
            }
            this.dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR));
        }
    }
}
