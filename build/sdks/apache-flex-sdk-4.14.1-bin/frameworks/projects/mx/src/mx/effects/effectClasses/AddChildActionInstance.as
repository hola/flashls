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

package mx.effects.effectClasses
{

import flash.display.DisplayObject;
import flash.display.DisplayObjectContainer;
import mx.core.mx_internal;

use namespace mx_internal;

/**
 *  The AddChildActionInstance class implements the instance class
 *  for the AddChildAction effect.
 *  Flex creates an instance of this class when it plays
 *  an AddChildAction effect; you do not create one yourself.
 *
 *  @see mx.effects.AddChildAction
 *  
 *  @langversion 3.0
 *  @playerversion Flash 9
 *  @playerversion AIR 1.1
 *  @productversion Flex 3
 */  
public class AddChildActionInstance extends ActionEffectInstance
{
    include "../../core/Version.as";

	//--------------------------------------------------------------------------
	//
	//  Constructor
	//
	//--------------------------------------------------------------------------

	/**
	 *  Constructor.
	 *
	 *  @param target The Object to animate with this effect.
	 *  
	 *  @langversion 3.0
	 *  @playerversion Flash 9
	 *  @playerversion AIR 1.1
	 *  @productversion Flex 3
	 */
	public function AddChildActionInstance(target:Object)
	{
		super(target);
	}
	
	//--------------------------------------------------------------------------
	//
	//  Properties
	//
	//--------------------------------------------------------------------------
	
	//----------------------------------
	//  index
	//----------------------------------
	
	/** 
	 *  The index of the child within the parent.
	 *  
	 *  @langversion 3.0
	 *  @playerversion Flash 9
	 *  @playerversion AIR 1.1
	 *  @productversion Flex 3
	 */
	public var index:int = -1;
	
	//----------------------------------
	//  relativeTo
	//----------------------------------
	
	/** 
	 *  The location where the child component is added.
	 *  
	 *  @langversion 3.0
	 *  @playerversion Flash 9
	 *  @playerversion AIR 1.1
	 *  @productversion Flex 3
	 */
	public var relativeTo:DisplayObjectContainer;
	
	//----------------------------------
	//  position
	//----------------------------------
	
	/** 
	 *  The position of the child component, relative to relativeTo, where it is added.
	 *  
	 *  @langversion 3.0
	 *  @playerversion Flash 9
	 *  @playerversion AIR 1.1
	 *  @productversion Flex 3
	 */
	public var position:String;
	
	//--------------------------------------------------------------------------
	//
	//  Overridden methods
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	override public function play():void
	{
		var targetDisplayObject:DisplayObject = DisplayObject(target);

		// Dispatch an effectStart event from the target.
		super.play();	
		
		if (!relativeTo && propertyChanges)
		{
			if (propertyChanges.start.parent == null &&
				propertyChanges.end.parent != null)
			{
				relativeTo = propertyChanges.end.parent;
				position = "index";
				index = propertyChanges.end.index;
			}
		}
		
		if (!playReversed)
		{
			// Set the style property
			if (target && targetDisplayObject.parent == null && relativeTo)
			{
				switch (position)
				{
					case "index":
					{
						if (index == -1)
							relativeTo.addChild(targetDisplayObject);
						else
							relativeTo.addChildAt(targetDisplayObject, 
												Math.min(index, relativeTo.numChildren));
						break;
					}
					
					case "before":
					{
						relativeTo.parent.addChildAt(targetDisplayObject,
							relativeTo.parent.getChildIndex(relativeTo));
						break;
					}

					case "after":
					{
						relativeTo.parent.addChildAt(targetDisplayObject,
							relativeTo.parent.getChildIndex(relativeTo) + 1);
						break;
					}
					
					case "firstChild":
					{
						relativeTo.addChildAt(targetDisplayObject, 0);
					}
					
					case "lastChild":
					{
						relativeTo.addChild(targetDisplayObject);
					}
				}
			}
		}
		else
		{
			if (target && relativeTo && targetDisplayObject.parent == relativeTo)
			{
				relativeTo.removeChild(targetDisplayObject);
			}
		}
		
		// We're done...
		finishRepeat();
	}
}	

}
