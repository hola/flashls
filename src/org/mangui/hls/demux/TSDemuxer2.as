/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.demux {
    import org.mangui.hls.flv.FLVTag;

    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;
    CONFIG::HAVE_WORKER {
    import org.hola.WorkerUtils;
    import flash.system.Worker;
    import flash.system.MessageChannel;
    }
    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.utils.Hex;
    }
    /** Representation of an MPEG transport stream. **/
    public class TSDemuxer2 extends EventDispatcher implements Demuxer {
        /** TS Packet size in byte. **/
        private static const PACKETSIZE : uint = 188;
        /** TS Sync byte. **/
        private static const SYNCBYTE : uint = 0x47;
        private static var id : uint = 0;
        private var _id : uint;
        /* callback functions for audio selection, and parsing progress/complete */
        private var _callback_audioselect : Function;
        private var _callback_progress : Function;
        private var _callback_complete : Function;
        private var _callback_videometadata : Function;
        CONFIG::HAVE_WORKER {
        private var _worker : Worker;
        private var _ochan : MessageChannel;
        private var _ichan : MessageChannel;
        }

        public static function probe(data : ByteArray) : Boolean {
            var pos : uint = data.position;
            var len : uint = Math.min(data.bytesAvailable, PACKETSIZE * 2);
            for (var i : int = 0; i < len; i++) {
                if (data.readByte() == SYNCBYTE) {
                    // ensure that at least two consecutive TS start offset are found
                    if (data.bytesAvailable > PACKETSIZE) {
                        data.position = pos + i + PACKETSIZE;
                        if (data.readByte() == SYNCBYTE) {
                            data.position = pos + i;
                            return true;
                        }
                        data.position = pos + i + 1;
                    }
                }
            }
            data.position = pos;
            return false;
        }

        /** Transmux the M2TS file into an FLV file. **/
        public function TSDemuxer2(displayObject : *,
            callback_audioselect : Function, callback_progress : Function,
            callback_complete : Function, callback_videometadata : Function)
        {
            CONFIG::HAVE_WORKER {
            _callback_audioselect = callback_audioselect;
            _callback_progress = callback_progress;
            _callback_complete = callback_complete;
            _callback_videometadata = callback_videometadata;
            _worker = WorkerUtils.worker;
            _id = TSDemuxer2.id++;
            _ochan = Worker.current.createMessageChannel(_worker);
            _ichan = _worker.createMessageChannel(Worker.current);
            _ichan.addEventListener(Event.CHANNEL_MESSAGE, onmsg);
            _worker.setSharedProperty("TSDemux_m2w_"+_id, _ochan);
            _worker.setSharedProperty("TSDemux_w2m_"+_id, _ichan);
            WorkerUtils.send({cmd: "TSDemux.init", id: _id});
            }
        };

        CONFIG::HAVE_WORKER
        private function onmsg(e : Event) : void {
            var msg : Object = _ichan.receive();
            switch (msg.cmd)
            {
            case "log":
                CONFIG::LOGGING {
                Log.info(msg.args);
                }
                break;
            case "complete": oncomplete(msg.args, _ichan.receive()); break;
            case "videometadata":
                _callback_videometadata(msg.args[0], msg.args[1]);
                break;
            }
        }

        private function oncomplete(o : Object, arr : ByteArray) : void {
            arr.position = 0;
            var tags : Vector.<FLVTag> = new Vector.<FLVTag>();
            while (arr.position<arr.length)
            {
                var keyframe : Boolean = arr.readBoolean();
                var pts : Number = arr.readFloat();
                var dts : Number = arr.readFloat();
                var type : int = arr.readInt();
                var length : int = arr.readInt();
                var data : ByteArray = new ByteArray();
                arr.readBytes(data, 0, length);
                var tag : FLVTag = new FLVTag(type, pts, dts, keyframe);
                tag.lock();
                tag.data = data;
                tags.push(tag);
            }
            _callback_complete(o, tags);
        }

        /** append new TS data */
        public function append(data : ByteArray) : void {
            CONFIG::HAVE_WORKER {
            _ochan.send({cmd: "append"});
            data.shareable = true; // XXX bahaa: verify safe to transfer
            _ochan.send(data);
            }
        }

        /** cancel demux operation */
        public function cancel() : void {
            CONFIG::HAVE_WORKER {
            _ochan.send({cmd: "cancel"});
            }
        }

        public function notifycomplete() : void {
            CONFIG::HAVE_WORKER {
            _ochan.send({cmd: "notifycomplete"});
            }
        }

        public function audio_expected() : Boolean {
            return false;
        }

        public function video_expected() : Boolean {
            return false;
        }

        public function close() : void {
            CONFIG::HAVE_WORKER {
            if (!_ochan)
                return;
            _ochan.send({cmd: "close"});
            _ichan.close();
            _ochan.close();
            _ichan = _ochan = null;
            }
        }
    }
}
