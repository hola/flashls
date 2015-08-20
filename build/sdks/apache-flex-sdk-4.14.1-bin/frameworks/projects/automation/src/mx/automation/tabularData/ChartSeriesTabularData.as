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

package mx.automation.tabularData
{ 
	
	import mx.automation.AutomationManager;
	import mx.automation.IAutomationTabularData;
	import mx.charts.chartClasses.Series;
	import mx.charts.series.items.AreaSeriesItem;
	import mx.charts.series.items.BarSeriesItem;
	import mx.charts.series.items.BubbleSeriesItem;
	import mx.charts.series.items.ColumnSeriesItem;
	import mx.charts.series.items.HLOCSeriesItem;
	import mx.charts.series.items.LineSeriesItem;
	import mx.charts.series.items.PieSeriesItem;
	import mx.charts.series.items.PlotSeriesItem;
	import mx.core.mx_internal;
	
	use namespace mx_internal;
	
	/**
	 *  @private
	 */
	public class ChartSeriesTabularData
		implements IAutomationTabularData
	{
		
		private var series:Object;
		
		/**
		 *  @private
		 */
		public function ChartSeriesTabularData(series:Object)
		{
			super();
			
			this.series = series ;
		}
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function get firstVisibleRow():int
		{
			return 0;
		}
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function get lastVisibleRow():int
		{
			return series.items.length-1;
		}
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function get numRows():int
		{
			return series.items.length;
		}
		
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function get numColumns():int
		{
			return 1;
		}
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function get columnNames():Array
		{
			return ["values"];
		}
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function getValues(start:uint = 0, end:uint = 0):Array
		{
			var _values:Array = [];
			if (end == 0)
				end = series.items.length;
			var i:int;
			var items:Array = series.items;
			for (i = start; i <= end; ++i)
			{
				var values:Array = getAutomationValueForData(items[i]);
				_values.push([ values.join("|") ]);
			}
			
			return _values;
		}
		
		/**
		 *  @inheritDoc
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 9
		 *  @playerversion AIR 1.1
		 *  @productversion Flex 3
		 */
		public function getAutomationValueForData(data:Object):Array
		{
			if (data is AreaSeriesItem)
				return [data.xNumber, data.yNumber];
			if (data is BarSeriesItem)
				return [data.xNumber, data.yNumber];
			if (data is BubbleSeriesItem)
				return [data.xNumber, data.yNumber, data.zNumber];
			if (data is ColumnSeriesItem)
				return [data.xNumber,data.yNumber];
			if (data is HLOCSeriesItem)
				return [data.openNumber, data.closeNumber, data.highNumber, data.lowNumber];
			if (data is LineSeriesItem)
				return [data.xNumber,data.yNumber];
			if (data is PieSeriesItem)
				return [data.number];
			if (data is PlotSeriesItem)
				return [data.xNumber, data.yNumber];
			
			return [];
		}
	}
}
