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

package spark.components.gridClasses
{
 
import spark.components.Grid;

/**
 *  This interface provides a method that dynamically created visual
 *  elements can use to configure themselves before they're displayed.
 *  It's called as needed when a factory generated visual element
 *  is created or reused.  It is not intended to be called directly.
 * 
 *  <p>This is an optional interface for all of the factory-generated
 *  visual elements except itemRenderers: <code>caretIndicator</code>,
 *  <code>hoverIndicator</code>, <code>editorIndicator</code>,
 *  <code>selectionIndicator</code>, <code>columnSeparator</code>,
 *  <code>rowSeparator</code>,
 *  <code>alternatingRowColorsBackground</code> (see DataGrid),
 *  <code>sortIndicator</code> (see GridColumnHeaderGroup).  It's
 *  typically used to configure generated visual elements with
 *  DataGrid's style values.  For example, to use the value of the
 *  DataGrid's "symbolColor" style for the caret's fill color,
 *  one would define the <code>prepareGridVisualElement()</code>
 *  method like this:</p> 
 * 
 *  <p>
 *  <pre>
 *  public function prepareGridVisualElement(grid:Grid, rowIndex:int, columnIndex:int):void
 *  {
 *      caretStroke.color = grid.dataGrid.getStyle("caretColor");
 *  }
 *  </pre>
 *  </p>        
 * 
 *  <p>The <code>rowIndex</code> and <code>columnIndex</code> parameters specify the 
 *  the cell the visual element will occupy.  If <code>columnIndex</code> = -1 then the visual element
 *  occupies a Grid row. If <code>rowIndex</code> = -1 then the visual element occupies
 *  a Grid column.</p>
 * 
 *  <p>There are many more examples like this in DataGridSkin.mxml.  Note that custom 
 *  DataGrid skin visual elements can choose not to implement this interface if the 
 *  the added flexibility isn't needed.</p>
 * 
 *  @langversion 3.0
 *  @playerversion Flash 10
 *  @playerversion AIR 2.0
 *  @productversion Flex 4.5 
 */
public interface IGridVisualElement
{
    /** 
     *  This method is called before a visual element of the Grid is rendered to give the 
     *  element a chance to configure itself.  The method's parameters specify what 
     *  cell, or row (if columnIndex = -1), or column (if rowIndex = -1) the visual
     *  element will occupy.
     * 
     *  <p>If the visual element is generated by a factory valued
     *  DataGrid skin part, like selectionIndicator or hoverIndicator,
     *  then <code>grid.dataGrid</code> will be the DataGrid for which
     *  grid is a skin part.</p>
     * 
     *  @param grid The Grid associated with this visual element.
     *  @param rowIndex The row coordinate of the cell the visual element will occupy, or -1
     *  @param columnIndex The column coordinate of the cell the visual element will occupy, or -1
     * 
     *  @langversion 3.0
     *  @playerversion Flash 10
     *  @playerversion AIR 2.0
     *  @productversion Flex 4.5  
     */
    function prepareGridVisualElement(grid:Grid, rowIndex:int, columnIndex:int):void; 
}
}