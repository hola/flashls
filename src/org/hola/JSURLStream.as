/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.hola {
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.external.ExternalInterface;
    import flash.net.URLRequest;
    import flash.net.URLStream;
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

        public function JSURLStream(){
            _hola_managed = HSettings.enabled;
            addEventListener(Event.OPEN, onOpen);
            ExternalInterface.marshallExceptions = true;
            super();
            // Connect calls to JS.
            if (ExternalInterface.available && !js_api_inited){
                ZErr.log('JSURLStream init api');
                js_api_inited = true;
                ExternalInterface.addCallback('hola_onFragmentData',
                    hola_onFragmentData);
            }
        }

        protected function _trigger(cb:String, data:Object) : void {
            if (!ExternalInterface.available) {
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
            if (_hola_managed)
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
            _hola_managed = HSettings.enabled;
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

        private function onOpen(event : Event) : void { _connected = true; }

        private function decode(str : String) : void {
            var data : ByteArray;
            if (!HSettings.use_worker)
            {
                if (str)
                    data = Base64.decode_str(str);
                return on_decoded_data(data);
            }
            data = new ByteArray();
            data.shareable = true;
            data.writeUTFBytes(str);
            WorkerUtils.send({cmd: "b64.decode", id: _req_id});
            WorkerUtils.send(data);
        }

        private function onmsg(e : HEvent) : void {
            var msg : Object = e.data;
            if (!_req_id || _req_id!=msg.id || msg.cmd!="b64.decode")
                return;
            var data : ByteArray = WorkerUtils.recv();
            on_decoded_data(data);
        }

        private function on_decoded_data(data : ByteArray) : void {
            if (data)
            {
                data.position = 0;
                if (_resource)
                {
                    var prev:uint = _resource.position;
                    data.readBytes(_resource, _resource.length);
                    _resource.position = prev;
                }
                else
                    _resource = data;
                // XXX arik: get finalLength from js
                var finalLength:uint = _resource.length;
                dispatchEvent(new ProgressEvent( ProgressEvent.PROGRESS, false,
                    false, _resource.length, finalLength));
            }
            // XXX arik: dispatch httpStatus/httpResponseStatus
            if (_curr_data.status)
                resourceLoadingSuccess();
        }

        private function on_fragment_data(o : Object) : void {
            _curr_data = o;
            if (o.error)
                return resourceLoadingError();
            decode(o.data);
        }

        protected static function hola_onFragmentData(o:Object):void{
            var stream:JSURLStream;
            try {
                if (!(stream = reqs[o.req_id]))
                    throw new Error('req_id not found '+o.req_id);
                stream.on_fragment_data(o);
            } catch(err:Error){
                ZErr.log('Error in hola_onFragmentData', ''+err,
                    ''+err.getStackTrace());
                if (stream)
                    stream.resourceLoadingError();
                throw err;
            }
        }

        protected function resourceLoadingError() : void {
            delete reqs[_req_id];
            dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR));
        }

        protected function resourceLoadingSuccess() : void {
            delete reqs[_req_id];
            dispatchEvent(new Event(Event.COMPLETE));
        }
    }
}
