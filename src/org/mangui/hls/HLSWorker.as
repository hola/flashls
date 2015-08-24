package org.mangui.hls {
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.system.Worker;
    import flash.system.MessageChannel;
    import org.mangui.hls.demux.TSDemuxerWorker;
    import org.hola.Base64;

    public class HLSWorker extends Sprite {
        private var _ichan : MessageChannel;
	private var _ochan : MessageChannel;

        public function HLSWorker() {
            _ochan = Worker.current.getSharedProperty("w2m");
            _ichan = Worker.current.getSharedProperty("m2w");
            _ichan.addEventListener(Event.CHANNEL_MESSAGE, onmsg);
        };

        private function onmsg(e : Event) : void {
            var msg : * = _ichan.receive();
            switch (msg.cmd)
            {
            case "TSDemux.init": new TSDemuxerWorker(msg.id); break;
            case "b64.decode":
                var arr : ByteArray = _ichan.receive();
                arr = Base64.decode(arr);
                _ochan.send({cmd: "b64.decode", id: msg.id});
                _ochan.send(arr);
                break;
            }
        };
    }
}
