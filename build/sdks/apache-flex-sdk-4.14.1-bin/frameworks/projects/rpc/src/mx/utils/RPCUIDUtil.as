////////////////////////////////////////////////////////////////////////////////
//
//  Licensed to the Apache Software Foundation (ASF) under one or more
//  contributor license agreements.  See the NOTICE file distributed with
//  this work for additional information regarding copyright ownership.
//  The ASF licenses this file to You under the Apache License, Version 2.0
//  (the "License"); you may not use this file except in compliance with
//  the License.  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////

package mx.utils
{

import flash.utils.ByteArray;

/**
 *  The RPCUIDUtil class is a copy of UIDUtil without some functions that
 *  cause dependency problems when RPC messages are put in a bootstrap loader.
 *  
 *  @langversion 3.0
 *  @playerversion Flash 9
 *  @playerversion AIR 1.1
 *  @productversion Flex 3
 */
public class RPCUIDUtil
{
    include "../core/Version.as";

    //--------------------------------------------------------------------------
    //
    //  Class constants
    //
    //--------------------------------------------------------------------------

    /**
     *  @private
     *  Char codes for 0123456789ABCDEF
     */
	private static const ALPHA_CHAR_CODES:Array = [48, 49, 50, 51, 52, 53, 54, 
		55, 56, 57, 65, 66, 67, 68, 69, 70];

    private static const DASH:int = 45;       // dash ascii
    private static const UIDBuffer:ByteArray = new ByteArray();       // static ByteArray used for UID generation to save memory allocation cost

    //--------------------------------------------------------------------------
    //
    //  Class methods
    //
    //--------------------------------------------------------------------------

    /**
     *  Generates a UID (unique identifier) based on ActionScript's
     *  pseudo-random number generator and the current time.
     *
     *  <p>The UID has the form
     *  <code>"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"</code>
     *  where X is a hexadecimal digit (0-9, A-F).</p>
     *
     *  <p>This UID will not be truly globally unique; but it is the best
     *  we can do without player support for UID generation.</p>
     *
     *  @return The newly-generated UID.
     *  
     *  @langversion 3.0
     *  @playerversion Flash 9
     *  @playerversion AIR 1.1
     *  @productversion Flex 3
     */
    public static function createUID():String
    {
        UIDBuffer.position = 0;

        var i:int;
        var j:int;

        for (i = 0; i < 8; i++)
        {
            UIDBuffer.writeByte(ALPHA_CHAR_CODES[int(Math.random() * 16)]);
        }

        for (i = 0; i < 3; i++)
        {
            UIDBuffer.writeByte(DASH);
            for (j = 0; j < 4; j++)
            {
                UIDBuffer.writeByte(ALPHA_CHAR_CODES[int(Math.random() * 16)]);
            }
        }

        UIDBuffer.writeByte(DASH);

        var time:uint = new Date().getTime(); // extract last 8 digits
        var timeString:String = time.toString(16).toUpperCase();
        // 0xFFFFFFFF milliseconds ~= 3 days, so timeString may have between 1 and 8 digits, hence we need to pad with 0s to 8 digits
        for (i = 8; i > timeString.length; i--)
            UIDBuffer.writeByte(48);
        UIDBuffer.writeUTFBytes(timeString);

        for (i = 0; i < 4; i++)
        {
            UIDBuffer.writeByte(ALPHA_CHAR_CODES[int(Math.random() * 16)]);
        }

        return UIDBuffer.toString();
    }

    /**
     * Converts a 128-bit UID encoded as a ByteArray to a String representation.
     * The format matches that generated by createUID. If a suitable ByteArray
     * is not provided, null is returned.
     * 
     * @param ba ByteArray 16 bytes in length representing a 128-bit UID.
     * 
     * @return String representation of the UID, or null if an invalid
     * ByteArray is provided.
     *  
     *  @langversion 3.0
     *  @playerversion Flash 9
     *  @playerversion AIR 1.1
     *  @productversion Flex 3
     */
    public static function fromByteArray(ba:ByteArray):String
    {
        if (ba != null && ba.length >= 16 && ba.bytesAvailable >= 16)
        {
            UIDBuffer.position = 0;
            var index:uint = 0;
            for (var i:uint = 0; i < 16; i++)
            {
                if (i == 4 || i == 6 || i == 8 || i == 10)
                    UIDBuffer.writeByte(DASH); // Hyphen char code

                var b:int = ba.readByte();
                UIDBuffer.writeByte(ALPHA_CHAR_CODES[(b & 0xF0) >>> 4]);
                UIDBuffer.writeByte(ALPHA_CHAR_CODES[(b & 0x0F)]);
            }
            return UIDBuffer.toString();
        }

        return null;
    }

    /**
     * A utility method to check whether a String value represents a 
     * correctly formatted UID value. UID values are expected to be 
     * in the format generated by createUID(), implying that only
     * capitalized A-F characters in addition to 0-9 digits are
     * supported.
     * 
     * @param uid The value to test whether it is formatted as a UID.
     * 
     * @return Returns true if the value is formatted as a UID.
     *  
     *  @langversion 3.0
     *  @playerversion Flash 9
     *  @playerversion AIR 1.1
     *  @productversion Flex 3
     */
    public static function isUID(uid:String):Boolean
    {
        if (uid != null && uid.length == 36)
        {
            for (var i:uint = 0; i < 36; i++)
            {
                var c:Number = uid.charCodeAt(i);

                // Check for correctly placed hyphens
                if (i == 8 || i == 13 || i == 18 || i == 23)
                {
                    if (c != DASH)
                    {
                        return false;
                    }
                }
                // We allow capital alpha-numeric hex digits only
                else if (c < 48 || c > 70 || (c > 57 && c < 65))
                {
                    return false;
                }
            }

            return true;
        }

        return false;
    }

    /**
     * Converts a UID formatted String to a ByteArray. The UID must be in the
     * format generated by createUID, otherwise null is returned.
     * 
     * @param String representing a 128-bit UID
     * 
     * @return ByteArray 16 bytes in length representing the 128-bits of the
     * UID or null if the uid could not be converted.
     *  
     *  @langversion 3.0
     *  @playerversion Flash 9
     *  @playerversion AIR 1.1
     *  @productversion Flex 3
     */
    public static function toByteArray(uid:String):ByteArray
    {
        if (isUID(uid))
        {
            var result:ByteArray = new ByteArray();

            for (var i:uint = 0; i < uid.length; i++)
            {
                var c:String = uid.charAt(i);
                if (c == "-")
                    continue;
                var h1:uint = getDigit(c);
                i++;
                var h2:uint = getDigit(uid.charAt(i));
                result.writeByte(((h1 << 4) | h2) & 0xFF);
            }
            result.position = 0;
            return result;
        }

        return null;
    }


    /**
     * Returns the decimal representation of a hex digit.
     * @private
     */
    private static function getDigit(hex:String):uint
    {
        switch (hex) 
        {
            case "A": 
            case "a":           
                return 10;
            case "B":
            case "b":
                return 11;
            case "C":
            case "c":
                return 12;
            case "D":
            case "d":
                return 13;
            case "E":
            case "e":
                return 14;                
            case "F":
            case "f":
                return 15;
            default:
                return new uint(hex);
        }    
    }
}

}