package org.hola
{
    import flash.external.ExternalInterface;
    import org.hola.ZExternalInterface;
    public class ZErr
    {
        public static function log(msg:String, ...rest:Array):void{
            if (!ZExternalInterface.avail())
                return;
            ExternalInterface.call.apply(ExternalInterface,
                ['console.log', msg].concat(rest))
        }

        public static function time(label : String) : void {
            CONFIG::LOGGING {
            if (ZExternalInterface.avail())
                ExternalInterface.call("console.time", label);
            }
        }

        public static function timeEnd(label : String) : void {
            CONFIG::LOGGING {
            if (ZExternalInterface.avail())
                ExternalInterface.call("console.timeEnd", label);
            }
        }
    }
}