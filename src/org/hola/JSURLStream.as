/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.hola {
    import flash.events.*;
    import flash.external.ExternalInterface;
    import flash.net.URLRequest;
    import flash.net.URLStream;
    import flash.net.URLRequestHeader;
    import flash.net.URLRequestMethod;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    import flash.utils.Timer;
    import org.hola.ZErr;
    import org.hola.Base64;
    import org.hola.WorkerUtils;
    import org.hola.HEvent;
    import org.hola.HSettings;

    public dynamic class JSURLStream extends URLStream {
        private static var js_api_inited : Boolean = false;
        private static var req_count : Number = 0;
        private static var reqs : Object = {};
        private var _connected : Boolean;
        private var _resource : ByteArray = new ByteArray();
        private var _curr_data : Object;
        private var _hola_managed : Boolean = false;
        private var _req_id : String;
        private var _self_load : Boolean = false;
        private var _events : Object;
        private var _size : Number;

        public function JSURLStream(){
            _hola_managed = HSettings.enabled && ExternalInterface.available;
            addEventListener(Event.OPEN, onopen);
            super();
            if (!_hola_managed || js_api_inited)
                return;
            // Connect calls to JS.
            ZErr.log('JSURLStream init api');
            ExternalInterface.marshallExceptions = true;
            ExternalInterface.addCallback('hola_onFragmentData',
                hola_onFragmentData);
            js_api_inited = true;
        }

        protected function _trigger(cb : String, data : Object) : void {
            if (!_hola_managed && !_self_load)
            {
                // XXX arik: need ZErr.throw
                ZErr.log('invalid trigger');
                throw new Error('invalid trigger');
            }
            ExternalInterface.call('window.hola_'+cb,
                {objectID: ExternalInterface.objectID, data: data});
        }

        override public function get connected() : Boolean {
            if (!_hola_managed)
                return super.connected;
            return _connected;
        }

        override public function get bytesAvailable() : uint {
            if (!_hola_managed)
                return super.bytesAvailable;
            return _resource.bytesAvailable;
        }

        override public function readByte() : int {
            if (!_hola_managed)
                return super.readByte();
            return _resource.readByte();
        }

        override public function readUnsignedShort() : uint {
            if (!_hola_managed)
                return super.readUnsignedShort();
            return _resource.readUnsignedShort();
        }

        override public function readBytes(bytes : ByteArray,
            offset : uint = 0, length : uint = 0) : void
        {
            if (!_hola_managed)
                return super.readBytes(bytes, offset, length);
            _resource.readBytes(bytes, offset, length);
        }

        override public function close() : void {
            if (_hola_managed || _self_load)
            {
                if (reqs[_req_id])
                    _trigger('abortFragment', {req_id: _req_id});
                WorkerUtils.removeEventListener(HEvent.WORKER_MESSAGE, onmsg);
            }
            if (super.connected)
                super.close();
            _connected = false;
        }

        override public function load(request : URLRequest) : void {
            // XXX arik: cleanup previous if hola mode changed
            _hola_managed = HSettings.enabled && ExternalInterface.available;
            req_count++;
            _req_id = 'req'+req_count;
            if (!_hola_managed)
                return super.load(request);
            WorkerUtils.addEventListener(HEvent.WORKER_MESSAGE, onmsg);
            reqs[_req_id] = this;
            _resource = new ByteArray();
            _trigger('requestFragment', {url: request.url, req_id: _req_id});
            this.dispatchEvent(new Event(Event.OPEN));
        }

        private function onopen(e : Event) : void { _connected = true; }

        private function onerror(e : ErrorEvent) : void {
            _delete();
            if (!_events.error)
                return;
            _trigger('onRequestEvent', {req_id: _req_id, event: 'error',
                error: e.text, text: e.toString()});
        }

        private function onprogress(e : ProgressEvent) : void {
            _size = e.bytesTotal;
            if (!_events.progress)
                return;
            _trigger('onRequestEvent', {req_id: _req_id, event: 'progress',
                loaded: e.bytesLoaded, total: e.bytesTotal,
                text: e.toString()});
        }

        private function onstatus(e : HTTPStatusEvent) : void {
            if (!_events.status)
                return;
            // XXX bahaa: get redirected/responseURL/responseHeaders
            _trigger('onRequestEvent', {req_id: _req_id, event: 'status',
                status: e.status, text: e.toString()});
        }

        private function oncomplete(e : Event) : void {
            _delete();
            if (!_events.complete)
                return;
            _trigger('onRequestEvent', {req_id: _req_id, event: 'complete',
                size: _size, text: e.toString()});
        }

        private function decode(str : String) : void {
            if (!str)
                return on_decoded_data(null);
            if (!HSettings.use_worker)
                return on_decoded_data(Base64.decode_str(str));
            var data : ByteArray = new ByteArray();
            data.shareable = true;
            data.writeUTFBytes(str);
            WorkerUtils.send({cmd: "b64.decode", id: _req_id});
            WorkerUtils.send(data);
        }

        private function onmsg(e : HEvent) : void {
            var msg : Object = e.data;
            if (!_req_id || _req_id!=msg.id || msg.cmd!="b64.decode")
                return;
            on_decoded_data(WorkerUtils.recv());
        }

        private function on_decoded_data(data : ByteArray) : void {
            if (data)
            {
                data.position = 0;
                if (_resource)
                {
                    var prev : uint = _resource.position;
                    data.readBytes(_resource, _resource.length);
                    _resource.position = prev;
                }
                else
                    _resource = data;
                // XXX arik: get finalLength from js
                var finalLength : uint = _resource.length;
                dispatchEvent(new ProgressEvent( ProgressEvent.PROGRESS, false,
                    false, _resource.length, finalLength));
            }
            // XXX arik: dispatch httpStatus/httpResponseStatus
            if (_curr_data.status)
                resourceLoadingSuccess();
        }

        private function self_load(o : Object) : void {
            _self_load = true;
            _hola_managed = false;
            _events = o.events||{};
            addEventListener(IOErrorEvent.IO_ERROR, onerror);
            addEventListener(SecurityErrorEvent.SECURITY_ERROR, onerror);
            addEventListener(ProgressEvent.PROGRESS, onprogress);
            addEventListener(HTTPStatusEvent.HTTP_STATUS, onstatus);
            addEventListener(Event.COMPLETE, oncomplete);
            var req : URLRequest = new URLRequest(o.url);
            req.method = o.method=="POST" ? URLRequestMethod.POST :
                URLRequestMethod.GET;
            // this doesn't seem to work. simply ignored
            var headers : Object = o.headers||{};
            for (var k : String in headers)
                req.requestHeaders.push(new URLRequestHeader(k, headers[k]));
            super.load(req);
        }

        private function on_fragment_data(o : Object) : void {
            _curr_data = o;
            if (o.self_load)
                return self_load(o);
            if (o.error)
                return resourceLoadingError();
            decode(o.data);
        }

        protected static function hola_onFragmentData(o : Object) : void{
            var stream : JSURLStream;
            try {
                if (!(stream = reqs[o.req_id]))
                    throw new Error('req_id not found '+o.req_id);
                stream.on_fragment_data(o);
            } catch(err : Error){
                ZErr.log('Error in hola_onFragmentData', ''+err,
                    ''+err.getStackTrace());
                if (stream)
                    stream.resourceLoadingError();
                throw err;
            }
        }

        private function _delete() : void {
            delete reqs[_req_id];
        }

        protected function resourceLoadingError() : void {
            _delete();
            dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR));
        }

        protected function resourceLoadingSuccess() : void {
            _delete();
            dispatchEvent(new Event(Event.COMPLETE));
        }
    }
}
