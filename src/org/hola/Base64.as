package org.hola
{
   import flash.utils.ByteArray;
   
   public class Base64 extends Object
   {
      
      private static const _decodeChars:Vector.<int> = InitDecodeChar();
      
      public function Base64()
      {
         super();
      }
      
      public static function decode(param1:String) : ByteArray
      {
         var _loc2_:* = 0;
         var _loc3_:* = 0;
         var _loc4_:* = 0;
         var _loc5_:* = 0;
         var _loc6_:* = 0;
         var _loc7_:int = param1.length;
         var _loc8_:ByteArray = new ByteArray();
         _loc8_.writeUTFBytes(param1);
         var _loc9_:* = 0;
         while(_loc6_ < _loc7_)
         {
            _loc2_ = _decodeChars[int(_loc8_[_loc6_++])];
            if(_loc2_ == -1)
            {
               break;
            }
            _loc3_ = _decodeChars[int(_loc8_[_loc6_++])];
            if(_loc3_ == -1)
            {
               break;
            }
            _loc8_[int(_loc9_++)] = _loc2_ << 2 | (_loc3_ & 48) >> 4;
            _loc4_ = _loc8_[int(_loc6_++)];
            if(_loc4_ == 61)
            {
               _loc8_.length = _loc9_;
               return _loc8_;
            }
            _loc4_ = _decodeChars[int(_loc4_)];
            if(_loc4_ == -1)
            {
               break;
            }
            _loc8_[int(_loc9_++)] = (_loc3_ & 15) << 4 | (_loc4_ & 60) >> 2;
            _loc5_ = _loc8_[int(_loc6_++)];
            if(_loc5_ == 61)
            {
               _loc8_.length = _loc9_;
               return _loc8_;
            }
            _loc5_ = _decodeChars[int(_loc5_)];
            if(_loc5_ == -1)
            {
               break;
            }
            _loc8_[int(_loc9_++)] = (_loc4_ & 3) << 6 | _loc5_;
         }
         _loc8_.length = _loc9_;
         return _loc8_;
      }
      
      public static function InitDecodeChar() : Vector.<int>
      {
         var _loc1_:Vector.<int> = new <int>[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,-1,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,-1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
         return _loc1_;
      }
   }
}
