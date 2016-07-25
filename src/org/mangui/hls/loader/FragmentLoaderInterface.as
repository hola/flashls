/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {

    import org.mangui.hls.model.Fragment;

    public interface FragmentLoaderInterface
    {
        function dispose() : void;
        function get audioExpected() : Boolean;
        function get videoExpected() : Boolean;
        function seek(position : Number) : void;
        function seekFromLastFrag(lastFrag : Fragment) : void;
        function stop() : void;
    }
}
