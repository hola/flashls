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

package mx.accessibility
{

import flash.accessibility.Accessibility;
import flash.events.Event;
import mx.accessibility.AccConst;
import mx.collections.CursorBookmark;
import mx.collections.IViewCursor;
import mx.controls.ColorPicker;
import mx.controls.colorPickerClasses.SwatchPanel;
import mx.controls.ComboBase;
import mx.core.UIComponent;
import mx.core.mx_internal;
import mx.events.ColorPickerEvent;
import mx.events.DropdownEvent;
import mx.skins.halo.SwatchSkin;

use namespace mx_internal;
	
/**
 *  ColorPickerAccImpl is a subclass of AccessibilityImplementation
 *  which implements accessibility for the ColorPicker class.
 *  
 *  @langversion 3.0
 *  @playerversion Flash 9
 *  @playerversion AIR 1.1
 *  @productversion Flex 3
 */
public class ColorPickerAccImpl extends ComboBaseAccImpl
{
	include "../core/Version.as";

	//--------------------------------------------------------------------------
	//
	//  Class methods
	//
	//--------------------------------------------------------------------------

	/**
	 *  Enables accessibility in the ColorPicker class.
	 * 
	 *  <p>This method is called by application startup code
	 *  that is autogenerated by the MXML compiler.
	 *  Afterwards, when instances of ColorPicker are initialized,
	 *  their <code>accessibilityImplementation</code> property
	 *  will be set to an instance of this class.</p>
	 *  
	 *  @langversion 3.0
	 *  @playerversion Flash 9
	 *  @playerversion AIR 1.1
	 *  @productversion Flex 3
	 */
	public static function enableAccessibility():void
	{
		ColorPicker.createAccessibilityImplementation =
			createAccessibilityImplementation;
	}
	
	/**
	 *  @private
	 *  Creates a ColorPicker's AccessibilityImplementation object.
	 *  This method is called from UIComponent's
	 *  initializeAccessibility() method.
	 */
	mx_internal static function createAccessibilityImplementation(
								component:UIComponent):void
	{
		component.accessibilityImplementation =
			new ColorPickerAccImpl(component);
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
	 *  @playerversion Flash 9
	 *  @playerversion AIR 1.1
	 *  @productversion Flex 3
	 */
	
	public function ColorPickerAccImpl(master:UIComponent)
	{
		super(master);

		//role = AccConst.ROLE_SYSTEM_COMBOBOX;

		master.accessibilityProperties.description = "Color Picker";
		Accessibility.updateProperties();
	
		ColorPicker(master).addEventListener(DropdownEvent.OPEN, openHandler);
		ColorPicker(master).addEventListener(DropdownEvent.CLOSE, closeHandler);
	}
	
	private function openHandler(event:Event):void
	{
		ColorPicker(master).dropdown.addEventListener("change",  dropdown_changeHandler);
	}
	private function closeHandler(event:Event):void
	{
		ColorPicker(master).dropdown.removeEventListener("change",  dropdown_changeHandler);
	}
	
	private function dropdown_changeHandler(event:Event):void
	{
		master.dispatchEvent(new Event("childChange"));
	}
	
	//--------------------------------------------------------------------------
	//
	//  Overridden methods: AccImpl
	//
	//--------------------------------------------------------------------------

	/**
	 *  @private
	 *  method for returning the name of the ComboBase
	 *  For children items (i. e. ColorSwatch colors), it returns the digits if the hex
	 *  color. We add a space between each digit to force the screen reader to read it
	 *  as a series of text, not a number (e.g. #009900 is "zero, zero, nine, nine, zero, zero",
	 *  not "nine thousand, nine hundred".
	 *  
	 *  ComboBase should return the name specified in the AccessibilityProperties.
	 *
	 *  @param childID uint
	 *
	 *  @return Name String
	 */
	override protected function getName(childID:uint):String
	{
		if (childID == 0)
			return "";

		var colorPicker:ColorPicker = ColorPicker(master);

		var iterator:IViewCursor = colorPicker.collectionIterator;
		iterator.seek(CursorBookmark.FIRST, childID - 1);
		var item:Object = iterator.current;
		
		if (typeof(item) != "object")
		{
			var str:String = item.toString(16);
			var x:String =  formatColorString(str);
			return x;
		}
			
		return !item.label ? item.data : item.label;
	}
	
	/**
	 *  @private
	 *  IAccessible method for returning the state of the ListItem
	 *  (basically to remove 'not selected').
	 *  States are predefined for all the components in MSAA.
	 *  Values are assigned to each state.
	 *  Depending upon the listItem being Selected, Selectable,
	 *  Invisible, Offscreen, a value is returned.
	 *
	 *  @param childID uint
	 *
	 *  @return State uint
	 */
	override public function get_accState(childID:uint):uint
	{
		var accState:uint = getState(childID);
		
		if (childID > 0)
		{
			accState |= AccConst.STATE_SYSTEM_SELECTABLE;
		
			accState |= AccConst.STATE_SYSTEM_SELECTED | AccConst.STATE_SYSTEM_FOCUSED;
		}

		return accState;
	}

	/**
	 *  @private
	 *  Method to return the current val;ue of the component
	 *
	 *  @return string
	 */
	override public function get_accValue(childID:uint):String
	{
		if (ColorPicker(master).showingDropdown)
		{
			return ColorPicker(master).dropdown ? 
				ColorPicker(master).dropdown.textInput.text :
				null;
		}
		else
		{
			return ColorPicker(master).selectedColor.toString(16);
		}
	}
	
	/**
	 *  @private
	 *  Method to return an array of childIDs.
	 *
	 *  @return Array
	 */
	override public function getChildIDArray():Array
	{
		
		var n:int = ColorPicker(master).dropdown ?
					ColorPicker(master).dropdown.length :
					0;

		return createChildIDArray(n);
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
	 *	Array of events that we should listen for from the master component.
	 */
	override protected function get eventsToHandle():Array
	{
		return super.eventsToHandle.concat([ "childChange"]);
	}
	//--------------------------------------------------------------------------
	//
	//  Overridden event handlers: AccImpl
	//
	//--------------------------------------------------------------------------

	/**
	 *  @private
	 *  Override the generic event handler.
	 *  All AccImpl must implement this to listen for events
	 *  from its master component. 
	 */
	override protected function eventHandler(event:Event):void
	{
		// Let AccImpl class handle the events
		// that all accessible UIComponents understand.
		$eventHandler(event);
				
		switch (event.type)
		{
			case "childChange":
			{
				var index:int = ComboBase(master).selectedIndex;
				Accessibility.sendEvent(master, ColorPicker(master).dropdown.focusedIndex + 1, AccConst.EVENT_OBJECT_SELECTION);
				Accessibility.sendEvent(master, 0,
								AccConst.EVENT_OBJECT_VALUECHANGE, true);
				break;
			}

			case "valueCommit":
			{
				Accessibility.sendEvent(master, 0, AccConst.EVENT_OBJECT_VALUECHANGE);
				break;
			}
		}
	}
	
	/**
	 *  @private
	 *  formats string color to add a space between each digit (hexit?).
	 *  Makes screen readers read color properly.
	 */
	private function formatColorString(color:String):String
	{
		var str2:String = "";
		var n:int = color.length;
		for (var i:uint = 0; i < n; i++)
			str2 += color.charAt(i) + " ";
		return str2;
	}
}

}
