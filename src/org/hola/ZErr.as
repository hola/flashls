package org.hola
{
    import flash.external.ExternalInterface;
    public class ZErr
    {
        public static function log(msg:String, ...rest:Array):void{
            if (!ExternalInterface.available)
                return;
            ExternalInterface.call.apply(ExternalInterface,
                ['console.log', msg].concat(rest))
        }

        public static function time(label : String) : void {
            CONFIG::LOGGING {
            if (ExternalInterface.available)
                ExternalInterface.call("console.time", label);
            }
        }

        public static function timeEnd(label : String) : void {
            CONFIG::LOGGING {
            if (ExternalInterface.available)
                ExternalInterface.call("console.timeEnd", label);
            }
        }
    }
}
