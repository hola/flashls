package org.hola {
    import flash.events.*;
    import flash.net.URLStream;
    import flash.net.URLRequest;
    import flash.utils.setTimeout;
    import flash.utils.clearTimeout;
    import flash.external.ExternalInterface;
    import org.hola.ZExternalInterface;

    public class FlashFetchBin {
        public static var inited:Boolean = false;
        public static var free_id:Number = 0;
        public static var req_list:Object = {};
        public static function init():Boolean{
            if (inited)
                return inited;
            if (!ZExternalInterface.avail())
                return false
            ExternalInterface.addCallback('hola_fetchBin', hola_fetchBin);
            ExternalInterface.addCallback('hola_fetchBinRemove',
                hola_fetchBinRemove);
            ExternalInterface.addCallback('hola_fetchBinAbort',
                hola_fetchBinAbort);
            inited = true;
            return inited;
        }
        public static function hola_fetchBin(o:Object):Object{
            var id:String = 'fetch_bin_'+free_id;
            free_id++;
            var url:String = o.url;
            var req:URLRequest = new URLRequest(url);
            var stream:URLStream = new URLStream();
            stream.load(req);
            req_list[id] = {id: id, stream: stream,
                jsurlstream_req_id: o.jsurlstream_req_id,
                direct_progress: o.direct_progress};
            stream.addEventListener(Event.OPEN, streamOpen);
            stream.addEventListener(ProgressEvent.PROGRESS, streamProgress);
            stream.addEventListener(HTTPStatusEvent.HTTP_STATUS,
                streamHttpStatus);
            stream.addEventListener(Event.COMPLETE, streamComplete);
            stream.addEventListener(IOErrorEvent.IO_ERROR, streamError);
            stream.addEventListener(SecurityErrorEvent.SECURITY_ERROR,
                streamError);
            return {id: id, url: url};
        }
        public static function hola_fetchBinRemove(id:String):void{
            var req:Object = req_list[id];
            if (!req)
                return;
            if (req.stream.connected)
                req.stream.close();
            if (req.timer)
                clearTimeout(req.timer);
            delete req_list[id];
        }
         public static function hola_fetchBinAbort(id:String):void{
            var req:Object = req_list[id];
            if (!req)
                return;
            if (req.stream.connected)
                req.stream.close();
        }
        public static function getReqFromStream(stream:Object):Object{
            // XXX arik/bahaa: implement without loop
            for (var n:String in req_list)
            {
                if (req_list[n].stream===stream)
                    return req_list[n];
            }
            return null;
        }
        // XXX arik/bahaa: mv to org.hola.util
        public static function jsPostMessage(id:String, data:Object):void{
            if (!ZExternalInterface.avail())
                return;
            ExternalInterface.call('window.postMessage',
                {id: id, ts: new Date().getTime(), data: data}, '*');
        }
        public static function streamOpen(e:Event):void{
            var req:Object = getReqFromStream(e.target);
            if (!req)
                return ZErr.log('req not found streamOpen');
            jsPostMessage('holaflash.streamOpen', {id: req.id});
        }
        public static function streamProgress(e:ProgressEvent):void{
            var req:Object = getReqFromStream(e.target);
            if (!req)
                return ZErr.log('req not found streamProgress');
            req.bytesTotal = e.bytesTotal;
            req.bytesLoaded = e.bytesLoaded;
            if (!req.prevJSProgress || req.bytesLoaded==req.bytesTotal ||
                req.bytesLoaded-req.prevJSProgress > (req.bytesTotal/5))
            {
                req.prevJSProgress = req.bytesLoaded;
                jsPostMessage('holaflash.streamProgress', {id: req.id,
                    bytesLoaded: e.bytesLoaded, bytesTotal: e.bytesTotal});
            }
            if (req.direct_progress)
            {
                JSURLStream.hola_onFragmentData({req_id: req.jsurlstream_req_id,
                    fetchBinReqId: req.id});
            }
        }
        public static function streamHttpStatus(e:HTTPStatusEvent):void{
            var req:Object = getReqFromStream(e.target);
            if (!req)
                return ZErr.log('req not found streamHttpStatus');
            jsPostMessage('holaflash.streamHttpStatus', {id: req.id,
                status: e.status});
        }
        public static function streamComplete(e:Event):void{
            var req:Object = getReqFromStream(e.target);
            if (!req)
                return ZErr.log('req not found streamComplete');
            jsPostMessage('holaflash.streamComplete', {id: req.id,
                bytesTotal: req.bytesTotal});
        }
        public static function streamError(e:ErrorEvent):void{
            var req:Object = getReqFromStream(e.target);
            if (!req)
                return ZErr.log('req not found streamError');
            jsPostMessage('holaflash.streamError', {id: req.id});
            hola_fetchBinRemove(req.id);
        }
        public static function consumeDataTimeout(id:String,
            cb:Function, ms:Number, ctx:Object):void{
            var req:Object = req_list[id];
            if (!req)
                throw new Error('consumeDataTimeout failed find req '+id);
            if (req.timer)
                clearTimeout(req.timer);
            req.timer = setTimeout(cb, ms, ctx);
        }
    }
}