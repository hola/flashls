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

package spark.accessibility
{

import flash.accessibility.Accessibility;
import flash.events.Event;
import flash.events.FocusEvent;

import mx.accessibility.AccConst;
import mx.accessibility.AccImpl;
import mx.core.UIComponent;
import mx.core.mx_internal;
import mx.utils.StringUtil;

import spark.components.RichEditableText;

use namespace mx_internal;

/**
 *  RichEditableTextAccImpl is the accessibility implementation class
 *  for spark.components.RichEditableText.
 *
 *  <p>When a Spark RichEditableText is created,
 *  its <code>accessibilityImplementation</code> property
 *  is set to an instance of this class.
 *  The Flash Player then uses this class to allow MSAA clients
 *  such as screen readers to see and manipulate the RichEditableText.
 *  See the mx.accessibility.AccImpl and
 *  flash.accessibility.AccessibilityImplementation classes
 *  for background information about accessibility implementation
 *  classes and MSAA.</p>
 *
 *  <p><b>Children</b></p>
 *
 *  <p>A RichEditableText has no MSAA children.</p>
 *
 *  <p><b>Role</b></p>
 *
 *  <p>The MSAA Role of a RichEditableText is ROLE_SYSTEM_TEXT.</p>
 *
 *  <p><b>Name</b></p>
 *
 *  <p>The MSAA Name of a RichEditableText is, by default, the empty string.
 *  When wrapped in a FormItem element, the Name is the FormItem's label.
 *  To override this behavior,
 *  set the RichEditableText's <code>accessibilityName</code> property.</p>
 *
 *  <p>When the Name changes,
 *  a RichEditableText dispatches the MSAA event EVENT_OBJECT_NAMECHANGE.</p>
 *
 *  <p><b>Description</b></p>
 *
 *  <p>The MSAA Description of a RichEditableText is, by default,
 *  the empty string, but you can set the RichEditableText's
 *  <code>accessibilityDescription</code> property.</p>
 *
 *  <p><b>State</b></p>
 *
 *  <p>The MSAA State of a RichEditableText is a combination of:
 *  <ul>
 *    <li>STATE_SYSTEM_UNAVAILABLE (when enabled is false)</li>
 *    <li>STATE_SYSTEM_FOCUSABLE (when enabled is true)</li>
 *    <li>STATE_SYSTEM_FOCUSED
 *    (when enabled is true and the RichEditableText has focus)</li>
 *    <li>STATE_SYSTEM_PROTECTED (when displayAsPassword is true)</li>
 *    <li>STATE_SYSTEM_READONLY (when editable is false)</li>
 *  </ul></p>
 *
 *  <p>When the State changes,
 *  a RichEditableText dispatches the MSAA event EVENT_OBJECT_STATECHANGE.</p>
 *
 *  <p><b>Value</b></p>
 *
 *  <p>The MSAA Value of a RichEditableText is equal to
 *  its <code>text</code> property.</p>
 *
 *  <p>When the Value changes,
 *  a RichEditableText dispatches the MSAA event EVENT_OBJECT_VALUECHANGE.</p>
 *
 *  <p><b>Location</b></p>
 *
 *  <p>The MSAA Location of a RichEditableText is its bounding rectangle.</p>
 *
 *  <p><b>Default Action</b></p>
 *
 *  <p>A RichEditableText does not have an MSAA DefaultAction.</p>
 *
 *  <p><b>Focus</b></p>
 *
 *  <p>A RichEditableText accepts focus. 
 *  When it does so it dispatches the MSAA event EVENT_OBJECT_FOCUS.</p>
 *
 *  <p><b>Selection</b></p>
 *
 *  <p>A RichEditableText does not support selection in the MSAA sense,
 *  and text selection is not part of Microsoft's IAccessibility COM interface.
 *  But, in Player 10.1 and later, screen readers can determine
 *  the currently selected text range via the <code>GetSelection()</code> method
 *  in Adobe's ISimpleTextSelection COM interface, which calls the
 *  <code>selectionAnchorIndex</code> and <code>selectionActiveIndex</code>
 *  getters in this class.</p>
 *
 *  @langversion 3.0
 *  @playerversion Flash 10
 *  @playerversion AIR 1.5
 *  @productversion Flex 4
 */
public class RichEditableTextAccImpl extends AccImpl
{
    include "../core/Version.as";

    //--------------------------------------------------------------------------
    //
    //  Class methods
    //
    //--------------------------------------------------------------------------
    
    /**
     *  Enables accessibility in the RichEditableText class.
     *
     *  <p>This method is called by application startup code
     *  that is autogenerated by the MXML compiler.
     *  Afterwards, when instances of RichEditableText are initialized,
     *  their <code>accessibilityImplementation</code> property
     *  will be set to an instance of this class.</p>
     *
     *  @langversion 3.0
     *  @playerversion Flash 10
     *  @playerversion AIR 1.5
     *  @productversion Flex 4
     */
    public static function enableAccessibility():void
    {
        RichEditableText.createAccessibilityImplementation = 
            createAccessibilityImplementation;
    }

    /**
     *  @private
     *  Creates a RichEditableText's AccessibilityImplementation object.
     *  This method is called from UIComponent's
     *  initializeAccessibility() method.
     */
    mx_internal static function createAccessibilityImplementation(
        component:UIComponent):void
    {
        component.accessibilityImplementation =
            new RichEditableTextAccImpl(component);
    }

    //--------------------------------------------------------------------------
    //
    //  Constructor
    //
    //--------------------------------------------------------------------------

    /**
     *  Constructor.
     *
     *  @param master The UIComponent instance that this AccImpl instance
     *  is making accessible.
     *
     *  @langversion 3.0
     *  @playerversion Flash 10
     *  @playerversion AIR 1.5
     *  @productversion Flex 4
     */
    public function RichEditableTextAccImpl(master:UIComponent)
    {
        super(master);

        role = AccConst.ROLE_SYSTEM_TEXT;
    }

    //--------------------------------------------------------------------------
    //
    //  Overridden properties: AccImpl
    //
    //--------------------------------------------------------------------------

    //----------------------------------
    //  eventsToHandle
    //----------------------------------

    /**
     *  @private
     *  Array of events that we should listen for from the master component.
     */
    override protected function get eventsToHandle():Array
    {
        return super.eventsToHandle.concat([ Event.CHANGE ]);
    }

    //--------------------------------------------------------------------------
    //
    //  Properties: ISimpleTextSelection
    //
    //--------------------------------------------------------------------------

    //----------------------------------
    //  selectionActiveIndex
    //----------------------------------

    /**
     *  A character position, relative to the beginning of the
     *  <code>text</code> String of the RichEditableText,
	 *  specifying the end of the selection
     *  that moves when the selection is extended with the arrow keys.
     *
     *  <p>The active position may be either the start
     *  or the end of the selection.</p>
     *
     *  <p>For example, if you drag-select from position 12 to position 8,
     *  then <code>selectionAnchorPosition</code> will be 12
     *  and <code>selectionActivePosition</code> will be 8,
     *  and when you press Left-Arrow <code>selectionActivePosition</code>
     *  will become 7.</p>
     *
     *  <p>A value of -1 indicates "not set".</p>
	 *
	 *  <p>In Player 10.1 and later, and AIR 2.0 and later,
	 *  an AccessibilityImplementation can implement
	 *  <code>selectionAnchorIndex</code> and <code>selectionAnchorIndex</code>
	 *  in order to make an accessibility client aware of the text selection
	 *  in TLF text via Adobe's ISimpleTextSelection COM interface.</p>
     *
     *  @default -1
     *
	 *  @see spark.accessibility.RichEditableTextAccImpl#selectionAnchorIndex
     *  @see spark.components.RichEditableText#selectionActivePosition
     *  
     *  @langversion 3.0
     *  @playerversion Flash 10.1
     *  @playerversion AIR 2.0
     *  @productversion Flex 4
     */
	public function get selectionActiveIndex():int
	{
		return RichEditableText(master).selectionActivePosition;
	}

    //----------------------------------
    //  selectionAnchorIndex
    //----------------------------------

    /**
     *  A character position, relative to the beginning of the
     *  <code>text</code> String of the RichEditableText,
	 *  specifying the end of the selection
     *  that stays fixed when the selection is extended with the arrow keys.
     *
     *  <p>The anchor position may be either the start
     *  or the end of the selection.</p>
     *
     *  <p>For example, if you drag-select from position 12 to position 8,
     *  then <code>selectionAnchorPosition</code> will be 12
     *  and <code>selectionActivePosition</code> will be 8,
     *  and when you press Left-Arrow <code>selectionActivePosition</code>
     *  will become 7.</p>
     *
     *  <p>A value of -1 indicates "not set".</p>
	 *
	 *  <p>In Player 10.1 and later, and AIR 2.0 and later,
	 *  an AccessibilityImplementation can implement
	 *  <code>selectionAnchorIndex</code> and <code>selectionAnchorIndex</code>
	 *  in order to make an accessibility client aware of the text selection
	 *  in TLF text via Adobe's ISimpleTextSelection COM interface.</p>
     *
     *  @default -1
     *
	 *  @see spark.accessibility.RichEditableTextAccImpl#selectionActiveIndex
     *  @see spark.components.RichEditableText#selectionAnchorPosition
     *  
     *  @langversion 3.0
     *  @playerversion Flash 10.1
     *  @playerversion AIR 2.0
     *  @productversion Flex 4
     */
	public function get selectionAnchorIndex():int
	{
		return RichEditableText(master).selectionAnchorPosition;
	}

    //--------------------------------------------------------------------------
    //
    //  Overridden methods: AccessibilityImplementation
    //
    //--------------------------------------------------------------------------

    /**
     *  @private
     *  IAccessible method for returning the text value of the RichEditableText
     *
     *  @param childID uint
     *
     *  @return Value String
     */
    override public function get_accValue(childID:uint):String
    {
		var richEditableText:RichEditableText = RichEditableText(master);
		if (richEditableText.displayAsPassword)
		{
			return StringUtil.repeat("*", richEditableText.text.length);
		} 
		return richEditableText.text;
    }

    /**
     *  @private
     *  IAccessible method for returning the state of the RichEditableText.
     *  States are predefined for all the components in MSAA.
     *  Values are assigned to each state.
     *
     *  @param childID uint
     *
     *  @return State uint
     */
    override public function get_accState(childID:uint):uint
    {
        var accState:uint = getState(childID);
        if (!RichEditableText(master).editable)
            accState |= AccConst.STATE_SYSTEM_READONLY;
        if (RichEditableText(master).displayAsPassword)
            accState |= AccConst.STATE_SYSTEM_PROTECTED;
        return accState;
    }

    //--------------------------------------------------------------------------
    //
    //  Overridden event handlers: AccImpl
    //
    //--------------------------------------------------------------------------

    /**
     *  @private
     *  Override the generic event handler.
     *  All AccImpl must implement this
     *  to listen for events from its master component.
     */
    override protected function eventHandler(event:Event):void
    {
        // Let AccImpl class handle the events
        // that all accessible UIComponents understand.
        $eventHandler(event);

        switch (event.type)
        {
            case Event.CHANGE:
            {
                Accessibility.sendEvent(
					master, 0, AccConst.EVENT_OBJECT_VALUECHANGE, true);
                break;
            }
        }
    }

    /**
     *  @private
     *  method for returning the name of the RichEditableText
     *  should return the value
     *
     *  @param childID uint
     *
     *  @return Name String
     */
    override protected function getName(childID:uint):String
    {
        return "";
    }

}

}
