# -*- coding: utf-8 -*-
from jesse.services.file import store_logs
import jesse.helpers as jh
from jesse.modes import backtest_mode
from jesse.config import config
from jesse.services import charts
from jesse.services import report
from jesse.routes import router
from datetime import datetime, timedelta
from jesse.store import store
import jesse.services.metrics as stats
from jesse.enums import trade_types

cimport cython
import numpy as np
cimport numpy as np
np.import_array()

import pandas as pd
import numpy as np
import json 

from jesse.utils import numpy_candles_to_dataframe
from typing import Union
from jesse.services import report 

import codecs

from bottle import template
import os

# from jesse.strategies import Strategy



from enum import IntEnum
class CD(IntEnum):
    date = 0
    open = 1
    close = 2
    high = 3
    low = 4
    volume = 5
        
def pvsra(candles: np.ndarray, sequential: bool = False) -> Union[np.ndarray, pd.DataFrame]:
    df = numpy_candles_to_dataframe(candles)
    average_volume = df["volume"].rolling(10).mean()
    climax = df["volume"] * (df["high"] - df["low"])
    highest_climax_10 = climax.rolling(window=10).max()

    df["averageVolume"] = average_volume
    df["climax"] = climax
    df["highestClimax10"] = highest_climax_10
    df['climaxVolume'] = ((df['volume'] >= 2 * average_volume) | (climax >= highest_climax_10)).astype(int)
    df['risingVolume'] = ((df['volume'] >= 1.5 * average_volume) & (df['climaxVolume'] != 1)).astype(int)
    df['isBull'] = (df["close"] > df["open"]).astype(int)
    df['risingBullVolume'] = ((df["risingVolume"] == 1) & (df["isBull"] == 1)).astype(int)
    df['risingBearVolume'] = ((df["risingVolume"] == 1) & (df["isBull"] == 0)).astype(int)
    df['climaxBullVolume'] = ((df["climaxVolume"] == 1) & (df["isBull"] == 1)).astype(int)
    df['climaxBearVolume'] = ((df["climaxVolume"] == 1) & (df["isBull"] == 0)).astype(int)

    return df if sequential else df.iloc[-1]


def generateReport(new_name: str = None, new_path: str = None, customData={}, chartConfig={}, indicators={}):

    chartConfig={'isPvsra':True}
    cdef np.ndarray candles 
    strategy = router.routes[0].strategy 
    
    metrics = report.portfolio_metrics()
    metrics = {k: str(v) for k, v in metrics.items()}
    metrics_json = json.dumps(metrics,indent=4)
    metrics_json = f'const metrics_data = {metrics_json}';
    
    file_name = jh.get_session_id() if not new_name else new_name
    studyname = backtest_mode._get_study_name()
    
    if not config['env']['simulation']['preload_candles']:
        candles = store.candles.get_candles(router.routes[0].exchange, router.routes[0].symbol, router.routes[0].timeframe)
    else:
        candle_key = f'{router.routes[0].exchange}-{router.routes[0].symbol}-{router.routes[0].timeframe}'
        candles = store.candles.storage[candle_key].array[0:-1]

    indicator_key = f'{router.routes[0].exchange}-{router.routes[0].symbol}-{router.routes[0].timeframe}'
    slice_amount = strategy.slice_amount[indicator_key]
    candles = candles[slice_amount-1:]
    color_list = ['rgba(70, 172, 56, 0.6)','rgba(194, 27, 27, 0.6)','rgba(27, 179, 194, 0.6)','rgba(194, 115, 27, 0.6)',\
    'rgba(143, 27, 194, 0.6)','rgba(32, 27, 194, 0.6)']
    pane_counter = 0
    for index,indicator in enumerate(indicators):
        ind_dict = {}
        unpacked = indicator[indicator_key]
        if len(strategy.hp.keys()) == len(indicators):
            key_list = list(strategy.hp.keys())
            indicator_name = key_list[index]
        else:
            indicator_name = f'indicator{index+1}'
        if unpacked[0] < (candles[0][2] * 0.5) or unpacked[0] > (candles[0][2] * 1.5):
            #TODO: multiple panes not supported yet
            continue
            pane_counter += 1
            pane = pane_counter
        else:
            pane = 1 
            
        ind_dict = {"data":unpacked,"options":{"pane":pane, "color": color_list[index]}}
        customData[f'{indicator_name}'] = ind_dict
    
    
    if(config["app"]["trading_mode"] == 'backtest'):

        cstLineTpl = r"""

            chart.add{{type}}({{!options}}).setData(await getCustomData({{offset}}))

        """
        
        tpl = r"""
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{{title}}</title>
    <link
      rel="stylesheet"
      href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.3/css/all.min.css"
    />
    <link href="https://unpkg.com/tippy.js@6/dist/tippy.css" rel="stylesheet" />
    <style>
      #navi-button {
        width: 27px;
        height: 27px;
        position: absolute;
        display: none;
        padding: 7px;
        box-sizing: border-box;
        font-size: 10px;
        border-radius: 50%;
        text-align: center;
        z-index: 1000;
        color: #b2b5be;
        background: rgba(250, 250, 250, 0.95);
        box-shadow: 0 2px 5px 0 rgba(117, 134, 150, 0.45);
      }

      .utility-box {
        display: none;
        position: absolute;
        top: 40px; /* Adjusted this line. 40px accounts for the height of the button plus a margin */
        right: 10%; /* Adjusted this line to align with toggleUtilityBox */
        background-color: transparent;
        z-index: 1000; /* Make sure it's above other elements */
      }
      .utility-box button {
        display: block;
        margin: 5px 0;
      }

      #toggleUtilityBox {
        position: absolute;
        top: 10px;
        right: 10%;
        z-index: 3;
        background-color: rgba(
          100,
          100,
          100,
          0.7
        ); /* initial background color */
        padding: 8px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        transition: background-color 0.3s, transform 0.3s, box-shadow 0.3s; /* smooth transitions */
      }

      #toggleUtilityBox:hover {
        background-color: rgba(
          80,
          80,
          80,
          0.8
        ); /* slightly darker background on hover */
        box-shadow: 2px 2px 10px rgba(0, 0, 0, 0.3); /* subtle shadow */
        transform: scale(1.1); /* grow the icon a bit */
      }

      #toggleUtilityBox i {
        color: white; /* initial color of the cogwheel icon */
        font-size: 20px;
        transition: color 0.3s; /* smooth color transition */
      }

      #toggleUtilityBox:hover i {
        color: rgba(255, 255, 255, 0.9); /* slightly brighter icon on hover */
      }

      #toggleNightMode {
        background-color: rgba(100, 100, 100, 0.7);
        padding: 8px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        transition: background-color 0.3s, transform 0.3s, box-shadow 0.3s;
        margin-top: 13px; /* to give some space between this button and the utility button */
      }

      #toggleNightMode:hover {
        background-color: rgba(80, 80, 80, 0.8);
        box-shadow: 2px 2px 10px rgba(0, 0, 0, 0.3);
        transform: scale(1.1);
      }

      #toggleNightMode i {
        color: white;
        font-size: 20px;
        transition: color 0.3s;
      }

      #toggleNightMode:hover i {
        color: rgba(255, 255, 255, 0.9);
      }
      #resetScales {
        background-color: rgba(100, 100, 100, 0.7);
        padding: 8px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        transition: background-color 0.3s, transform 0.3s, box-shadow 0.3s;
        margin-top: 6px; /* adjust as needed */
      }

      #resetScales:hover {
        background-color: rgba(80, 80, 80, 0.8);
        box-shadow: 2px 2px 10px rgba(0, 0, 0, 0.3);
        transform: scale(1.1);
      }

      #resetScales i {
        color: white;
        font-size: 20px;
        transition: color 0.3s;
      }

      #resetScales:hover i {
        color: rgba(255, 255, 255, 0.9);
      }
      #resetButton {
        background-color: rgba(100, 100, 100, 0.7);
        padding: 8px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        transition: background-color 0.3s, transform 0.3s, box-shadow 0.3s;
        margin-top: 6px; /* adjust as needed */
      }

      #resetButton:hover {
        background-color: rgba(80, 80, 80, 0.8);
        box-shadow: 2px 2px 10px rgba(0, 0, 0, 0.3);
        transform: scale(1.1);
      }

      #resetButton i {
        color: white;
        font-size: 20px;
        transition: color 0.3s;
      }

      #resetButton:hover i {
        color: rgba(255, 255, 255, 0.9);
      }

      #toggleCandleColors {
        background-color: rgba(100, 100, 100, 0.7);
        padding: 8px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        transition: background-color 0.3s, transform 0.3s, box-shadow 0.3s;
        margin-top: 6px; /* adjust as needed */
      }

      #toggleCandleColors:hover {
        background-color: rgba(80, 80, 80, 0.8);
        box-shadow: 2px 2px 10px rgba(0, 0, 0, 0.3);
        transform: scale(1.1);
      }

      #toggleCandleColors i {
        color: white;
        font-size: 20px;
        transition: color 0.3s;
      }

      #toggleCandleColors:hover i {
        color: rgba(255, 255, 255, 0.9);
      }
    </style>
  </head>
  <body id="main-body" style="background-color: white">
    <button
      id="toggleUtilityBox"
      style="position: absolute; top: 10px; right: 10%; z-index: 3"
    >
      <i class="fas fa-cog"></i>
    </button>
    <div class="utility-box" id="utilityBox">
      <button id="toggleNightMode">
        <i class="fas fa-moon"></i>
      </button>
      <div id="resetScales">
        <svg width="20px" height="20px" viewBox="0 0 512 512" fill="#ffffff">
          <g id="SVGRepo_bgCarrier" stroke-width="0" />

          <g
            id="SVGRepo_tracerCarrier"
            stroke-linecap="round"
            stroke-linejoin="round"
          />

          <g id="SVGRepo_iconCarrier">
            <g
              id="Page-1"
              stroke="none"
              stroke-width="1"
              fill="none"
              fill-rule="evenodd"
            >
              <g
                id="Combined-Shape"
                fill="#ffffff"
                transform="translate(27.581722, 33.830111)"
              >
                <path
                  d="M100.418278,7.10542736e-15 L200.836556,100.418278 L170.666667,130.588167 L121.751,81.684 L121.751278,371.503223 L420.418278,371.503223 L420.418278,392.836556 L121.751278,392.836223 L121.751611,435.503223 L79.0849447,435.503223 L79.084278,392.836223 L36.418278,392.836556 L36.418278,371.503223 L79.084278,371.503223 L79.084,81.685 L30.1698893,130.588167 L7.10542736e-15,100.418278 L100.418278,7.10542736e-15 Z M364.598766,30.1698893 L364.599441,53.0058528 C375.002669,56.6829614 384.517019,62.2417388 392.733552,69.2732459 L412.530364,57.8432107 L442.159994,109.163235 L422.376075,120.586547 C423.349349,125.855024 423.858025,131.286386 423.858025,136.836556 C423.858025,142.386833 423.34933,147.818298 422.376019,153.086871 L442.159994,164.509877 L412.530364,215.829901 L392.733552,204.399866 C384.517019,211.431373 375.002669,216.990151 364.599441,220.667259 L364.598766,243.503223 L305.339506,243.503223 L305.338831,220.667259 C294.935988,216.990287 285.421958,211.431785 277.205634,204.400648 L257.407908,215.829901 L227.778278,164.509877 L247.562253,153.086871 C246.588942,147.818298 246.080247,142.386833 246.080247,136.836556 C246.080247,131.286035 246.588987,125.854336 247.562381,120.585546 L227.778278,109.163235 L257.407908,57.8432107 L277.20464,69.2733144 C285.421191,62.2417749 294.935569,56.6829733 305.338831,53.0058528 L305.339506,30.1698893 L364.598766,30.1698893 Z M334.969136,101.281 C315.332345,101.281 299.41358,117.199765 299.41358,136.836556 C299.41358,156.473347 315.332345,172.392112 334.969136,172.392112 C354.605927,172.392112 370.524691,156.473347 370.524691,136.836556 C370.524691,117.199765 354.605927,101.281 334.969136,101.281 Z"
                ></path>
              </g>
            </g>
          </g>
        </svg>
      </div>
      <button id="resetButton" title="Reset and Refresh">
        <i class="fas fa-redo"></i>
      </button>
      <button id="toggleCandleColors">
        <i class="fas fa-chart-bar"></i>
      </button>
    </div>
    <div id="tvchart"></div>
  </body>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jscolor/2.5.1/jscolor.js"></script>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://unpkg.com/@popperjs/core@2"></script>
  <script src="https://unpkg.com/tippy.js@6"></script>

  <script src="https://unpkg.com/lightweight-charts/dist/lightweight-charts.standalone.production.js"></script>
"""
        if(True):
          tpl += r"""
<script src="https://unpkg.com/lightweight-charts/dist/lightweight-charts.standalone.production.js"></script>
"""
        else:
          tpl += r"""
<script>
/* SEE: https://github.com/tradingview/lightweight-charts/pull/824 */
/*!
 * @license
 * TradingView Lightweight Charts v3.6.0-dev+202108221751
 * Copyright (c) 2020 TradingView, Inc.
 * Licensed under Apache License 2.0 https://www.apache.org/licenses/LICENSE-2.0
 */
!function(){"use strict";var t,i;function n(t,i){var n,h=((n={})[0]=[],n[1]=[t.lineWidth,t.lineWidth],n[2]=[2*t.lineWidth,2*t.lineWidth],n[3]=[6*t.lineWidth,6*t.lineWidth],n[4]=[t.lineWidth,4*t.lineWidth],n)[i];t.setLineDash(h)}function h(t,i,n,h){t.beginPath();var s=t.lineWidth%2?.5:0;t.moveTo(n,i+s),t.lineTo(h,i+s),t.stroke()}!function(t){t[t.Simple=0]="Simple",t[t.WithSteps=1]="WithSteps"}(t||(t={})),function(t){t[t.Solid=0]="Solid",t[t.Dotted=1]="Dotted",t[t.Dashed=2]="Dashed",t[t.LargeDashed=3]="LargeDashed",t[t.SparseDotted=4]="SparseDotted"}(i||(i={}));var s=function(t,i){return(s=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,i){t.__proto__=i}||function(t,i){for(var n in i)Object.prototype.hasOwnProperty.call(i,n)&&(t[n]=i[n])})(t,i)};function r(t,i){if("function"!=typeof i&&null!==i)throw new TypeError("Class extends value "+String(i)+" is not a constructor or null");function n(){this.constructor=t}s(t,i),t.prototype=null===i?Object.create(i):(n.prototype=i.prototype,new n)}var e=function(){return(e=Object.assign||function(t){for(var i,n=1,h=arguments.length;n<h;n++)for(var s in i=arguments[n])Object.prototype.hasOwnProperty.call(i,s)&&(t[s]=i[s]);return t}).apply(this,arguments)};function u(t,i){for(var n=0,h=i.length,s=t.length;n<h;n++,s++)t[s]=i[n];return t}function a(t,i){if(!t)throw new Error("Assertion failed"+(i?": "+i:""))}function o(t){if(void 0===t)throw new Error("Value is undefined");return t}function l(t){if(null===t)throw new Error("Value is null");return t}function f(t){return l(o(t))}function c(t){for(var i=[],n=1;n<arguments.length;n++)i[n-1]=arguments[n];for(var h=0,s=i;h<s.length;h++){var r=s[h];for(var e in r)void 0!==r[e]&&("object"!=typeof r[e]||void 0===t[e]?t[e]=r[e]:c(t[e],r[e]))}return t}function v(t){return"number"==typeof t&&isFinite(t)}function _(t){return"number"==typeof t&&t%1==0}function d(t){return"string"==typeof t}function w(t){return"boolean"==typeof t}function M(t){var i,n,h,s=t;if(!s||"object"!=typeof s)return s;for(n in i=Array.isArray(s)?[]:{},s)s.hasOwnProperty(n)&&(h=s[n],i[n]=h&&"object"==typeof h?M(h):h);return i}function b(t){return null!==t}function m(t){return null===t?void 0:t}var g=function(){function t(){this.t=[]}return t.prototype.i=function(t){this.t=t},t.prototype.h=function(t,i,n,h){this.t.forEach((function(s){t.save(),s.h(t,i,n,h),t.restore()}))},t}(),p=function(){function t(){}return t.prototype.h=function(t,i,n,h){t.save(),t.scale(i,i),this.u(t,n,h),t.restore()},t.prototype.o=function(t,i,n,h){t.save(),t.scale(i,i),this.l(t,n,h),t.restore()},t.prototype.l=function(t,i,n){},t}(),y=function(t){function i(){var i=null!==t&&t.apply(this,arguments)||this;return i.v=null,i}return r(i,t),i.prototype._=function(t){this.v=t},i.prototype.u=function(t){if(null!==this.v&&null!==this.v.M){var i=this.v.M,n=this.v,h=function(h){t.beginPath();for(var s=i.to-1;s>=i.from;--s){var r=n.m[s];t.moveTo(r.g,r.p),t.arc(r.g,r.p,h,0,2*Math.PI)}t.fill()};t.fillStyle=n.k,h(n.N+2),t.fillStyle=n.S,h(n.N)}},i}(p);var k={from:0,to:1},x=function(){function t(t,i){this.C=new g,this.D=[],this.T=[],this.L=new Map,this.B=t,this.A=i,this.C.i(this.D)}return t.prototype.V=function(t){var i=this,n=this.B.O();n.length!==this.D.length&&(this.T=n.map((function(){return{m:[{g:0,p:0,P:0,F:0}],S:"",k:i.B.I().layout.backgroundColor,N:0,M:null}})),this.D=this.T.map((function(t){var i=new y;return i._(t),i})),this.C.i(this.D)),this.L.clear()},t.prototype.W=function(t,i,n,h){var s=this.L.get(n);if(!s){s=this.R(n),this.L.set(n,s);var r=new g;return r.i(s),r}var e=new g;return e.i(s),e},t.prototype.R=function(t){var i=this,n=this.B.O().map((function(t,i){return[t,i]})).filter((function(i){return t.j().includes(i[0])})),h=this.A.U(),s=this.B.q();return n.map((function(t){var n=t[0],r=t[1],e=i.T[r],u=n.H(h);if(null!==u&&n.Y()){var a=l(n.K());e.S=u.$,e.k=u.X,e.N=u.N,e.m[0].F=u.F,e.m[0].p=n.J().Z(u.F,a.G),e.m[0].P=h,e.m[0].g=s.tt(h),e.M=k}else e.M=null;return i.D[r]}))},t}(),N=function(){function t(t){this.it=t}return t.prototype.h=function(t,i,s,r){if(null!==this.it){var e=this.it.nt.Y,u=this.it.ht.Y;if(e||u){t.save();var a=Math.round(this.it.g*i),o=Math.round(this.it.p*i),l=Math.ceil(this.it.st*i),f=Math.ceil(this.it.rt*i);t.lineCap="butt",e&&a>=0&&(t.lineWidth=Math.floor(this.it.nt.et*i),t.strokeStyle=this.it.nt.ut,t.fillStyle=this.it.nt.ut,n(t,this.it.nt.at),function(t,i,n,h){t.beginPath();var s=t.lineWidth%2?.5:0;t.moveTo(i+s,n),t.lineTo(i+s,h),t.stroke()}(t,a,0,f)),u&&o>=0&&(t.lineWidth=Math.floor(this.it.ht.et*i),t.strokeStyle=this.it.ht.ut,t.fillStyle=this.it.ht.ut,n(t,this.it.ht.at),h(t,o,0,l)),t.restore()}}},t}(),S=function(){function t(t){this.L=new Map,this.ot={nt:{et:1,at:0,ut:"",Y:!1},ht:{et:1,at:0,ut:"",Y:!1},st:0,rt:0,g:0,p:0},this.lt=new N(this.ot),this.ft=t}return t.prototype.V=function(){this.L.clear()},t.prototype.W=function(t,i,n){return this.R(n),this.lt},t.prototype.R=function(t){var i=this.ft.Y(),n=l(this.ft.vt()).ct().I().crosshair,h=this.ot;h.ht.Y=i&&this.ft._t(t),h.nt.Y=i&&this.ft.dt(),h.ht.et=n.horzLine.width,h.ht.at=n.horzLine.style,h.ht.ut=n.horzLine.color,h.nt.et=n.vertLine.width,h.nt.at=n.vertLine.style,h.nt.ut=n.vertLine.color,h.st=t.wt(),h.rt=t.Mt(),h.g=this.ft.bt(),h.p=this.ft.gt()},t}(),C={khaki:"#f0e68c",azure:"#f0ffff",aliceblue:"#f0f8ff",ghostwhite:"#f8f8ff",gold:"#ffd700",goldenrod:"#daa520",gainsboro:"#dcdcdc",gray:"#808080",green:"#008000",honeydew:"#f0fff0",floralwhite:"#fffaf0",lightblue:"#add8e6",lightcoral:"#f08080",lemonchiffon:"#fffacd",hotpink:"#ff69b4",lightyellow:"#ffffe0",greenyellow:"#adff2f",lightgoldenrodyellow:"#fafad2",limegreen:"#32cd32",linen:"#faf0e6",lightcyan:"#e0ffff",magenta:"#f0f",maroon:"#800000",olive:"#808000",orange:"#ffa500",oldlace:"#fdf5e6",mediumblue:"#0000cd",transparent:"#0000",lime:"#0f0",lightpink:"#ffb6c1",mistyrose:"#ffe4e1",moccasin:"#ffe4b5",midnightblue:"#191970",orchid:"#da70d6",mediumorchid:"#ba55d3",mediumturquoise:"#48d1cc",orangered:"#ff4500",royalblue:"#4169e1",powderblue:"#b0e0e6",red:"#f00",coral:"#ff7f50",turquoise:"#40e0d0",white:"#fff",whitesmoke:"#f5f5f5",wheat:"#f5deb3",teal:"#008080",steelblue:"#4682b4",bisque:"#ffe4c4",aquamarine:"#7fffd4",aqua:"#0ff",sienna:"#a0522d",silver:"#c0c0c0",springgreen:"#00ff7f",antiquewhite:"#faebd7",burlywood:"#deb887",brown:"#a52a2a",beige:"#f5f5dc",chocolate:"#d2691e",chartreuse:"#7fff00",cornflowerblue:"#6495ed",cornsilk:"#fff8dc",crimson:"#dc143c",cadetblue:"#5f9ea0",tomato:"#ff6347",fuchsia:"#f0f",blue:"#00f",salmon:"#fa8072",blanchedalmond:"#ffebcd",slateblue:"#6a5acd",slategray:"#708090",thistle:"#d8bfd8",tan:"#d2b48c",cyan:"#0ff",darkblue:"#00008b",darkcyan:"#008b8b",darkgoldenrod:"#b8860b",darkgray:"#a9a9a9",blueviolet:"#8a2be2",black:"#000",darkmagenta:"#8b008b",darkslateblue:"#483d8b",darkkhaki:"#bdb76b",darkorchid:"#9932cc",darkorange:"#ff8c00",darkgreen:"#006400",darkred:"#8b0000",dodgerblue:"#1e90ff",darkslategray:"#2f4f4f",dimgray:"#696969",deepskyblue:"#00bfff",firebrick:"#b22222",forestgreen:"#228b22",indigo:"#4b0082",ivory:"#fffff0",lavenderblush:"#fff0f5",feldspar:"#d19275",indianred:"#cd5c5c",lightgreen:"#90ee90",lightgrey:"#d3d3d3",lightskyblue:"#87cefa",lightslategray:"#789",lightslateblue:"#8470ff",snow:"#fffafa",lightseagreen:"#20b2aa",lightsalmon:"#ffa07a",darksalmon:"#e9967a",darkviolet:"#9400d3",mediumpurple:"#9370d8",mediumaquamarine:"#66cdaa",skyblue:"#87ceeb",lavender:"#e6e6fa",lightsteelblue:"#b0c4de",mediumvioletred:"#c71585",mintcream:"#f5fffa",navajowhite:"#ffdead",navy:"#000080",olivedrab:"#6b8e23",palevioletred:"#d87093",violetred:"#d02090",yellow:"#ff0",yellowgreen:"#9acd32",lawngreen:"#7cfc00",pink:"#ffc0cb",paleturquoise:"#afeeee",palegoldenrod:"#eee8aa",darkolivegreen:"#556b2f",darkseagreen:"#8fbc8f",darkturquoise:"#00ced1",peachpuff:"#ffdab9",deeppink:"#ff1493",violet:"#ee82ee",palegreen:"#98fb98",mediumseagreen:"#3cb371",peru:"#cd853f",saddlebrown:"#8b4513",sandybrown:"#f4a460",rosybrown:"#bc8f8f",purple:"#800080",seagreen:"#2e8b57",seashell:"#fff5ee",papayawhip:"#ffefd5",mediumslateblue:"#7b68ee",plum:"#dda0dd",mediumspringgreen:"#00fa9a"};function D(t){return t<0?0:t>255?255:Math.round(t)||0}var T=/^#([0-9a-f])([0-9a-f])([0-9a-f])([0-9a-f])?$/i,E=/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})?$/i,L=/^rgb\(\s*(-?\d{1,10})\s*,\s*(-?\d{1,10})\s*,\s*(-?\d{1,10})\s*\)$/,B=/^rgba\(\s*(-?\d{1,10})\s*,\s*(-?\d{1,10})\s*,\s*(-?\d{1,10})\s*,\s*(-?[\d]{0,10}(?:\.\d+)?)\s*\)$/;function A(t){var i,n=function(t){var i;if((t=t.toLowerCase())in C&&(t=C[t]),i=B.exec(t)||L.exec(t))return[D(parseInt(i[1],10)),D(parseInt(i[2],10)),D(parseInt(i[3],10))];if(i=E.exec(t))return[D(parseInt(i[1],16)),D(parseInt(i[2],16)),D(parseInt(i[3],16))];if(i=T.exec(t))return[D(17*parseInt(i[1],16)),D(17*parseInt(i[2],16)),D(17*parseInt(i[3],16))];throw new Error("Cannot parse color: "+t)}(t);return{yt:"rgb("+n[0]+", "+n[1]+", "+n[2]+")",kt:(i=n,.199*i[0]+.687*i[1]+.114*i[2]>160?"black":"white")}}function V(t,i,n,h,s,r){t.fillRect(i+r,n,h-2*r,r),t.fillRect(i+r,n+s-r,h-2*r,r),t.fillRect(i,n,r,s),t.fillRect(i+h-r,n,r,s)}function O(t,i,n){t.save(),t.scale(i,i),n(),t.restore()}function z(t,i,n,h,s,r){t.save(),t.globalCompositeOperation="copy",t.fillStyle=r,t.fillRect(i,n,h,s),t.restore()}var P,F=function(){function t(t,i){this._(t,i)}return t.prototype._=function(t,i){this.it=t,this.xt=i},t.prototype.h=function(t,i,n,h,s,r){if(this.it.Y){t.font=i.Nt;var e=this.it.St||!this.it.Ct?i.Dt:0,u=i.Tt,a=i.Et,o=i.Lt,l=i.Bt,f=i.At,c=this.it.Vt,v=Math.ceil(n.Ot(t,c)),_=i.zt,d=i.Pt+a+o,w=Math.ceil(.5*d),M=u+v+l+f+e,b=this.xt.Ft;this.xt.It&&(b=this.xt.It);var m,g,p=(b=Math.round(b))-w,y=p+d,k="right"===s,x=k?h:0,N=Math.ceil(h*r),S=x;if(t.fillStyle=this.xt.yt,t.lineWidth=1,t.lineCap="butt",c){k?(m=x-e,g=(S=x-M)+f):(S=x+M,m=x+e,g=x+u+e+l);var C=Math.max(1,Math.floor(r)),D=Math.max(1,Math.floor(u*r)),T=k?N:0,E=Math.round(p*r),L=Math.round(S*r),B=Math.round(b*r)-Math.floor(.5*r),A=B+C+(B-E),V=Math.round(m*r);t.save(),t.beginPath(),t.moveTo(T,E),t.lineTo(L,E),t.lineTo(L,A),t.lineTo(T,A),t.fill(),t.fillStyle=this.it.X,t.fillRect(k?N-D:0,E,D,A-E),this.it.St&&(t.fillStyle=this.xt.ut,t.fillRect(T,B,V-T,C)),t.textAlign="left",t.fillStyle=this.xt.ut,O(t,r,(function(){t.fillText(c,g,y-o-_)})),t.restore()}}},t.prototype.Mt=function(t,i){return this.it.Y?t.Pt+t.Et+t.Lt:0},t}(),I=function(){function t(t){this.Wt={Ft:0,ut:"#FFF",yt:"#000"},this.Rt={Vt:"",Y:!1,St:!0,Ct:!1,X:""},this.jt={Vt:"",Y:!1,St:!1,Ct:!0,X:""},this.Ut=!0,this.qt=new(t||F)(this.Rt,this.Wt),this.Ht=new(t||F)(this.jt,this.Wt)}return t.prototype.Vt=function(){return this.Rt.Vt},t.prototype.Ft=function(){return this.Yt(),this.Wt.Ft},t.prototype.V=function(){this.Ut=!0},t.prototype.Mt=function(t,i){return void 0===i&&(i=!1),Math.max(this.qt.Mt(t,i),this.Ht.Mt(t,i))},t.prototype.Kt=function(){return this.Wt.It||0},t.prototype.$t=function(t){this.Wt.It=t},t.prototype.Xt=function(){return this.Yt(),this.Rt.Y||this.jt.Y},t.prototype.Zt=function(){return this.Yt(),this.Rt.Y},t.prototype.W=function(t){return this.Yt(),this.Rt.St=this.Rt.St&&t.I().drawTicks,this.jt.St=this.jt.St&&t.I().drawTicks,this.qt._(this.Rt,this.Wt),this.Ht._(this.jt,this.Wt),this.qt},t.prototype.Jt=function(){return this.Yt(),this.qt._(this.Rt,this.Wt),this.Ht._(this.jt,this.Wt),this.Ht},t.prototype.Yt=function(){this.Ut&&(this.Rt.St=!0,this.jt.St=!1,this.Gt(this.Rt,this.jt,this.Wt))},t}(),W=function(t){function i(i,n,h){var s=t.call(this)||this;return s.ft=i,s.Qt=n,s.ti=h,s}return r(i,t),i.prototype.Gt=function(t,i,n){t.Y=!1;var h=this.ft.I().horzLine;if(h.labelVisible){var s=this.Qt.K();if(this.ft.Y()&&!this.Qt.ii()&&null!==s){var r=A(h.labelBackgroundColor);n.yt=r.yt,n.ut=r.kt;var e=this.ti(this.Qt);n.Ft=e.Ft,t.Vt=this.Qt.ni(e.F,s),t.Y=!0}}},i}(I),R=/[1-9]/g,j=function(){function t(){this.it=null}return t.prototype._=function(t){this.it=t},t.prototype.h=function(t,i,n){var h=this;if(null!==this.it&&!1!==this.it.Y&&0!==this.it.Vt.length){t.font=i.Nt;var s=Math.round(i.hi.Ot(t,this.it.Vt,R));if(!(s<=0)){t.save();var r=i.si,e=s+2*r,u=e/2,a=this.it.wt,o=this.it.Ft,f=Math.floor(o-u)+.5;f<0?(o+=Math.abs(0-f),f=Math.floor(o-u)+.5):f+e>a&&(o-=Math.abs(a-(f+e)),f=Math.floor(o-u)+.5);var c=f+e,v=0+i.Tt+i.Et+i.Pt+i.Lt;t.fillStyle=this.it.yt;var _=Math.round(f*n),d=Math.round(0*n),w=Math.round(c*n),M=Math.round(v*n);t.fillRect(_,d,w-_,M-d);var b=Math.round(this.it.Ft*n),m=d,g=Math.round((m+i.Tt+i.Dt)*n);t.fillStyle=this.it.ut;var p=Math.max(1,Math.floor(n)),y=Math.floor(.5*n);t.fillRect(b-y,m,p,g-m);var k=v-i.zt-i.Lt;t.textAlign="left",t.fillStyle=this.it.ut,O(t,n,(function(){t.fillText(l(h.it).Vt,f+r,k)})),t.restore()}}},t}(),U=function(){function t(t,i,n){this.Ut=!0,this.lt=new j,this.ot={Y:!1,yt:"#4c525e",ut:"white",Vt:"",wt:0,Ft:NaN},this.A=t,this.ri=i,this.ti=n}return t.prototype.V=function(){this.Ut=!0},t.prototype.W=function(){return this.Ut&&(this.R(),this.Ut=!1),this.lt._(this.ot),this.lt},t.prototype.R=function(){var t=this.ot;t.Y=!1;var i=this.A.I().vertLine;if(i.labelVisible){var n=this.ri.q();if(!n.ii()){var h=n.ei(this.A.U());t.wt=n.wt();var s=this.ti();if(s.P){t.Ft=s.Ft,t.Vt=n.ui(l(h)),t.Y=!0;var r=A(i.labelBackgroundColor);t.yt=r.yt,t.ut=r.kt}}}},t}(),q=function(){function t(){this.ai=null,this.oi=0}return t.prototype.li=function(){return this.oi},t.prototype.fi=function(t){this.oi=t},t.prototype.J=function(){return this.ai},t.prototype.ci=function(t){this.ai=t},t.prototype.vi=function(t,i){return[]},t.prototype._i=function(t){return[]},t.prototype.di=function(){return[]},t.prototype.Y=function(){return!0},t}();!function(t){t[t.Normal=0]="Normal",t[t.Magnet=1]="Magnet"}(P||(P={}));var H=function(t){function i(i,n){var h=t.call(this)||this;h.wi=null,h.Mi=NaN,h.bi=0,h.mi=!0,h.gi=new Map,h.pi=!1,h.yi=NaN,h.ki=NaN,h.xi=NaN,h.Ni=NaN,h.ri=i,h.Si=n,h.Ci=new x(i,h);var s,r;h.Di=(s=function(){return h.Mi},r=function(){return h.ki},function(t){var i=r(),n=s();if(t===l(h.wi).Ti())return{F:n,Ft:i};var e=l(t.K());return{F:t.Ei(i,e),Ft:i}});var e=function(t,i){return function(){return{P:h.ri.q().ei(t()),Ft:i()}}}((function(){return h.bi}),(function(){return h.bt()}));return h.Li=new U(h,i,e),h.Bi=new S(h),h}return r(i,t),i.prototype.I=function(){return this.Si},i.prototype.Ai=function(t,i){this.xi=t,this.Ni=i},i.prototype.Vi=function(){this.xi=NaN,this.Ni=NaN},i.prototype.Oi=function(){return this.xi},i.prototype.zi=function(){return this.Ni},i.prototype.Pi=function(t,i,n){this.pi||(this.pi=!0),this.mi=!0,this.Fi(t,i,n)},i.prototype.U=function(){return this.bi},i.prototype.bt=function(){return this.yi},i.prototype.gt=function(){return this.ki},i.prototype.Y=function(){return this.mi},i.prototype.Ii=function(){this.mi=!1,this.Wi(),this.Mi=NaN,this.yi=NaN,this.ki=NaN,this.wi=null,this.Vi()},i.prototype._i=function(t){return null!==this.wi?[this.Bi,this.Ci]:[]},i.prototype._t=function(t){return t===this.wi&&this.Si.horzLine.visible},i.prototype.dt=function(){return this.Si.vertLine.visible},i.prototype.vi=function(t,i){this.mi&&this.wi===t||this.gi.clear();var n=[];return this.wi===t&&n.push(this.Ri(this.gi,i,this.Di)),n},i.prototype.di=function(){return this.mi?[this.Li]:[]},i.prototype.vt=function(){return this.wi},i.prototype.ji=function(){this.Bi.V(),this.gi.forEach((function(t){return t.V()})),this.Li.V(),this.Ci.V()},i.prototype.Ui=function(t){return t&&!t.Ti().ii()?t.Ti():null},i.prototype.Fi=function(t,i,n){this.qi(t,i,n)&&this.ji()},i.prototype.qi=function(t,i,n){var h=this.yi,s=this.ki,r=this.Mi,e=this.bi,u=this.wi,a=this.Ui(n);this.bi=t,this.yi=isNaN(t)?NaN:this.ri.q().tt(t),this.wi=n;var o=null!==a?a.K():null;return null!==a&&null!==o?(this.Mi=i,this.ki=a.Z(i,o)):(this.Mi=NaN,this.ki=NaN),h!==this.yi||s!==this.ki||e!==this.bi||r!==this.Mi||u!==this.wi},i.prototype.Wi=function(){var t=this.ri.O().map((function(t){return t.Yi().Hi()})).filter(b),i=0===t.length?null:Math.max.apply(Math,t);this.bi=null!==i?i:NaN},i.prototype.Ri=function(t,i,n){var h=t.get(i);return void 0===h&&(h=new W(this,i,n),t.set(i,h)),h},i}(q),Y=".";function K(t,i){if(!v(t))return"n/a";if(!_(i))throw new TypeError("invalid length");if(i<0||i>16)throw new TypeError("invalid length");if(0===i)return t.toString();return("0000000000000000"+t.toString()).slice(-i)}var $=function(){function t(t,i){if(i||(i=1),v(t)&&_(t)||(t=100),t<0)throw new TypeError("invalid base");this.Qt=t,this.Ki=i,this.$i()}return t.prototype.format=function(t){var i=t<0?"−":"";return t=Math.abs(t),i+this.Xi(t)},t.prototype.$i=function(){if(this.Zi=0,this.Qt>0&&this.Ki>0)for(var t=this.Qt;t>1;)t/=10,this.Zi++},t.prototype.Xi=function(t){var i=this.Qt/this.Ki,n=Math.floor(t),h="",s=void 0!==this.Zi?this.Zi:NaN;if(i>1){var r=+(Math.round(t*i)-n*i).toFixed(this.Zi);r>=i&&(r-=i,n+=1),h=Y+K(+r.toFixed(this.Zi)*this.Ki,s)}else n=Math.round(n*i)/i,s>0&&(h=Y+K(0,s));return n.toFixed(0)+h},t}(),X=function(t){function i(i){return void 0===i&&(i=100),t.call(this,i)||this}return r(i,t),i.prototype.format=function(i){return t.prototype.format.call(this,i)+"%"},i}($),Z=function(){function t(){this.Ji=[]}return t.prototype.Gi=function(t,i,n){var h={Qi:t,tn:i,nn:!0===n};this.Ji.push(h)},t.prototype.hn=function(t){var i=this.Ji.findIndex((function(i){return t===i.Qi}));i>-1&&this.Ji.splice(i,1)},t.prototype.sn=function(t){this.Ji=this.Ji.filter((function(i){return i.tn===t}))},t.prototype.rn=function(t,i){var n=u([],this.Ji);this.Ji=this.Ji.filter((function(t){return!t.nn})),n.forEach((function(n){return n.Qi(t,i)}))},t.prototype.en=function(){return this.Ji.length>0},t.prototype.un=function(){this.Ji=[]},t}(),J=function(){function t(t,i){this.an=t,this.on=i}return t.prototype.ln=function(t){return null!==t&&(this.an===t.an&&this.on===t.on)},t.prototype.fn=function(){return new t(this.an,this.on)},t.prototype.cn=function(){return this.an},t.prototype.vn=function(){return this.on},t.prototype._n=function(){return this.on-this.an},t.prototype.ii=function(){return this.on===this.an||Number.isNaN(this.on)||Number.isNaN(this.an)},t.prototype.dn=function(i){return null===i?this:new t(Math.min(this.cn(),i.cn()),Math.max(this.vn(),i.vn()))},t.prototype.wn=function(t){if(v(t)&&0!==this.on-this.an){var i=.5*(this.on+this.an),n=this.on-i,h=this.an-i;n*=t,h*=t,this.on=i+n,this.an=i+h}},t.prototype.Mn=function(t){v(t)&&(this.on+=t,this.an+=t)},t.prototype.bn=function(){return{minValue:this.an,maxValue:this.on}},t.mn=function(i){return null===i?null:new t(i.minValue,i.maxValue)},t}();function G(t,i,n){return Math.min(Math.max(t,i),n)}function Q(t,i,n){return i-t<=n}function tt(t){return t<=0?NaN:Math.log(t)/Math.log(10)}function it(t){var i=Math.ceil(t);return i%2!=0?i-1:i}function nt(t){var i=Math.ceil(t);return i%2==0?i-1:i}function ht(t,i){var n=100*(t-i)/i;return i<0?-n:n}function st(t,i){var n=ht(t.cn(),i),h=ht(t.vn(),i);return new J(n,h)}function rt(t,i){var n=100*(t-i)/i+100;return i<0?-n:n}function et(t,i){var n=rt(t.cn(),i),h=rt(t.vn(),i);return new J(n,h)}function ut(t){var i=Math.abs(t);if(i<1e-8)return 0;var n=tt(i+1e-4)+4;return t<0?-n:n}function at(t){var i=Math.abs(t);if(i<1e-8)return 0;var n=Math.pow(10,i-4)-1e-4;return t<0?-n:n}function ot(t){if(null===t)return null;var i=ut(t.cn()),n=ut(t.vn());return new J(i,n)}var lt,ft=function(){function t(t,i){if(this.gn=t,this.pn=i,function(t){if(t<0)return!1;for(var i=t;i>1;i/=10)if(i%10!=0)return!1;return!0}(this.gn))this.yn=[2,2.5,2];else{this.yn=[];for(var n=this.gn;1!==n;){if(n%2==0)this.yn.push(2),n/=2;else{if(n%5!=0)throw new Error("unexpected base");this.yn.push(2,2.5),n/=5}if(this.yn.length>100)throw new Error("something wrong with base")}}}return t.prototype.kn=function(t,i,n){for(var h,s,r,e=0===this.gn?0:1/this.gn,u=1e-9,a=Math.pow(10,Math.max(0,Math.ceil(tt(t-i)))),o=0,l=this.pn[0];;){var f=Q(a,e,u)&&a>e+u,c=Q(a,n*l,u),v=Q(a,1,u);if(!(f&&c&&v))break;a/=l,l=this.pn[++o%this.pn.length]}if(a<=e+u&&(a=e),a=Math.max(1,a),this.yn.length>0&&(h=a,s=1,r=u,Math.abs(h-s)<r))for(o=0,l=this.yn[0];Q(a,n*l,u)&&a>e+u;)a/=l,l=this.yn[++o%this.yn.length];return a},t}(),ct=function(){function t(t,i,n,h){this.xn=[],this.Qt=t,this.gn=i,this.Nn=n,this.Sn=h}return t.prototype.kn=function(t,i){if(t<i)throw new Error("high < low");var n=this.Qt.Mt(),h=(t-i)*this.Cn()/n,s=new ft(this.gn,[2,2.5,2]),r=new ft(this.gn,[2,2,2.5]),e=new ft(this.gn,[2.5,2,2]),u=[];return u.push(s.kn(t,i,h),r.kn(t,i,h),e.kn(t,i,h)),function(t){if(t.length<1)throw Error("array is empty");for(var i=t[0],n=1;n<t.length;++n)t[n]<i&&(i=t[n]);return i}(u)},t.prototype.Dn=function(){var t=this.Qt,i=t.K();if(null!==i){var n=t.Mt(),h=this.Nn(n-1,i),s=this.Nn(0,i),r=this.Qt.I().entireTextOnly?this.Tn()/2:0,e=r,u=n-1-r,a=Math.max(h,s),o=Math.min(h,s);if(a!==o){for(var l=this.kn(a,o),f=a%l,c=a>=o?1:-1,v=null,_=0,d=a-(f+=f<0?l:0);d>o;d-=l){var w=this.Sn(d,i,!0);null!==v&&Math.abs(w-v)<this.Cn()||(w<e||w>u||(_<this.xn.length?(this.xn[_].En=w,this.xn[_].Ln=t.Bn(d)):this.xn.push({En:w,Ln:t.Bn(d)}),_++,v=w,t.An()&&(l=this.kn(d*c,o))))}this.xn.length=_}else this.xn=[]}else this.xn=[]},t.prototype.Vn=function(){return this.xn},t.prototype.Tn=function(){return this.Qt.Pt()},t.prototype.Cn=function(){return Math.ceil(2.5*this.Tn())},t}();function vt(t){return t.slice().sort((function(t,i){return l(t.li())-l(i.li())}))}!function(t){t[t.Normal=0]="Normal",t[t.Logarithmic=1]="Logarithmic",t[t.Percentage=2]="Percentage",t[t.IndexedTo100=3]="IndexedTo100"}(lt||(lt={}));var _t,dt=new X,wt=new $(100,1),Mt=function(){function t(t,i,n,h){this.On=0,this.zn=null,this.Pn=null,this.Fn=null,this.In={Wn:!1,Rn:null},this.jn=0,this.Un=0,this.qn=new Z,this.Hn=new Z,this.Yn=[],this.Kn=null,this.$n=null,this.Xn=null,this.Zn=null,this.Jn=wt,this.Gn=t,this.Si=i,this.Qn=n,this.th=h,this.ih=new ct(this,100,this.nh.bind(this),this.hh.bind(this))}return t.prototype.sh=function(){return this.Gn},t.prototype.I=function(){return this.Si},t.prototype.rh=function(t){if(c(this.Si,t),this.eh(),void 0!==t.mode&&this.uh({ah:t.mode}),void 0!==t.scaleMargins){var i=o(t.scaleMargins.top),n=o(t.scaleMargins.bottom);if(i<0||i>1)throw new Error("Invalid top margin - expect value between 0 and 1, given="+i);if(n<0||n>1||i+n>1)throw new Error("Invalid bottom margin - expect value between 0 and 1, given="+n);if(i+n>1)throw new Error("Invalid margins - sum of margins must be less than 1, given="+(i+n));this.oh(),this.$n=null}},t.prototype.lh=function(){return this.Si.autoScale},t.prototype.An=function(){return 1===this.Si.mode},t.prototype.fh=function(){return 2===this.Si.mode},t.prototype._h=function(){return 3===this.Si.mode},t.prototype.ah=function(){return{dh:this.Si.autoScale,wh:this.Si.invertScale,ah:this.Si.mode}},t.prototype.uh=function(t){var i=this.ah(),n=null;void 0!==t.dh&&(this.Si.autoScale=t.dh),void 0!==t.ah&&(this.Si.mode=t.ah,2!==t.ah&&3!==t.ah||(this.Si.autoScale=!0),this.In.Wn=!1),1===i.ah&&t.ah!==i.ah&&(!function(t){if(null===t)return!1;var i=at(t.cn()),n=at(t.vn());return isFinite(i)&&isFinite(n)}(this.Pn)?this.Si.autoScale=!0:null!==(n=function(t){if(null===t)return null;var i=at(t.cn()),n=at(t.vn());return new J(i,n)}(this.Pn))&&this.Mh(n)),1===t.ah&&t.ah!==i.ah&&null!==(n=ot(this.Pn))&&this.Mh(n);var h=i.ah!==this.Si.mode;h&&(2===i.ah||this.fh())&&this.eh(),h&&(3===i.ah||this._h())&&this.eh(),void 0!==t.wh&&i.wh!==t.wh&&(this.Si.invertScale=t.wh,this.bh()),this.Hn.rn(i,this.ah())},t.prototype.mh=function(){return this.Hn},t.prototype.Pt=function(){return this.Qn.fontSize},t.prototype.Mt=function(){return this.On},t.prototype.gh=function(t){this.On!==t&&(this.On=t,this.oh(),this.$n=null)},t.prototype.ph=function(){if(this.zn)return this.zn;var t=this.Mt()-this.yh()-this.kh();return this.zn=t,t},t.prototype.xh=function(){return this.Nh(),this.Pn},t.prototype.Mh=function(t,i){var n=this.Pn;(i||null===n&&null!==t||null!==n&&!n.ln(t))&&(this.$n=null,this.Pn=t)},t.prototype.ii=function(){return this.Nh(),0===this.On||!this.Pn||this.Pn.ii()},t.prototype.Sh=function(t){return this.wh()?t:this.Mt()-1-t},t.prototype.Z=function(t,i){return this.fh()?t=ht(t,i):this._h()&&(t=rt(t,i)),this.hh(t,i)},t.prototype.Ch=function(t,i,n){this.Nh();for(var h=this.kh(),s=l(this.xh()),r=s.cn(),e=s.vn(),u=this.ph()-1,a=this.wh(),o=u/(e-r),f=void 0===n?0:n.from,c=void 0===n?t.length:n.to,v=this.Dh(),_=f;_<c;_++){var d=t[_],w=d.F;if(!isNaN(w)){var M=w;null!==v&&(M=v(d.F,i));var b=h+o*(M-r),m=a?b:this.On-1-b;d.p=m}}},t.prototype.Th=function(t,i,n){this.Nh();for(var h=this.kh(),s=l(this.xh()),r=s.cn(),e=s.vn(),u=this.ph()-1,a=this.wh(),o=u/(e-r),f=void 0===n?0:n.from,c=void 0===n?t.length:n.to,v=this.Dh(),_=f;_<c;_++){var d=t[_],w=d.open,M=d.high,b=d.low,m=d.close;null!==v&&(w=v(d.open,i),M=v(d.high,i),b=v(d.low,i),m=v(d.close,i));var g=h+o*(w-r),p=a?g:this.On-1-g;d.Eh=p,g=h+o*(M-r),p=a?g:this.On-1-g,d.Lh=p,g=h+o*(b-r),p=a?g:this.On-1-g,d.Bh=p,g=h+o*(m-r),p=a?g:this.On-1-g,d.Ah=p}},t.prototype.Ei=function(t,i){var n=this.nh(t,i);return this.Vh(n,i)},t.prototype.Vh=function(t,i){var n=t;return this.fh()?n=function(t,i){return i<0&&(t=-t),t/100*i+i}(n,i):this._h()&&(n=function(t,i){return t-=100,i<0&&(t=-t),t/100*i+i}(n,i)),n},t.prototype.j=function(){return this.Yn},t.prototype.Oh=function(){if(this.Kn)return this.Kn;for(var t=[],i=0;i<this.Yn.length;i++){var n=this.Yn[i];null===n.li()&&n.fi(i+1),t.push(n)}return t=vt(t),this.Kn=t,this.Kn},t.prototype.zh=function(t){-1===this.Yn.indexOf(t)&&(this.Yn.push(t),this.eh(),this.Ph())},t.prototype.Fh=function(t){var i=this.Yn.indexOf(t);if(-1===i)throw new Error("source is not attached to scale");this.Yn.splice(i,1),0===this.Yn.length&&(this.uh({dh:!0}),this.Mh(null)),this.eh(),this.Ph()},t.prototype.K=function(){for(var t=null,i=0,n=this.Yn;i<n.length;i++){var h=n[i].K();null!==h&&((null===t||h.Ih<t.Ih)&&(t=h))}return null===t?null:t.G},t.prototype.wh=function(){return this.Si.invertScale},t.prototype.Vn=function(){return this.$n||(this.ih.Dn(),this.$n=this.ih.Vn(),this.qn.rn()),this.$n},t.prototype.Wh=function(){return this.qn},t.prototype.Rh=function(t){this.fh()||this._h()||null===this.Xn&&null===this.Fn&&(this.ii()||(this.Xn=this.On-t,this.Fn=l(this.xh()).fn()))},t.prototype.jh=function(t){if(!this.fh()&&!this._h()&&null!==this.Xn){this.uh({dh:!1}),(t=this.On-t)<0&&(t=0);var i=(this.Xn+.2*(this.On-1))/(t+.2*(this.On-1)),n=l(this.Fn).fn();i=Math.max(i,.1),n.wn(i),this.Mh(n)}},t.prototype.Uh=function(){this.fh()||this._h()||(this.Xn=null,this.Fn=null)},t.prototype.qh=function(t){this.lh()||null===this.Zn&&null===this.Fn&&(this.ii()||(this.Zn=t,this.Fn=l(this.xh()).fn()))},t.prototype.Hh=function(t){if(!this.lh()&&null!==this.Zn){var i=l(this.xh())._n()/(this.ph()-1),n=t-this.Zn;this.wh()&&(n*=-1);var h=n*i,s=l(this.Fn).fn();s.Mn(h),this.Mh(s,!0),this.$n=null}},t.prototype.Yh=function(){this.lh()||null!==this.Zn&&(this.Zn=null,this.Fn=null)},t.prototype.Kh=function(){return this.Jn||this.eh(),this.Jn},t.prototype.ni=function(t,i){switch(this.Si.mode){case 2:return this.Kh().format(ht(t,i));case 3:return this.Kh().format(rt(t,i));default:return this.$h(t)}},t.prototype.Bn=function(t){switch(this.Si.mode){case 2:case 3:return this.Kh().format(t);default:return this.$h(t)}},t.prototype.Xh=function(t){return this.$h(t,l(this.Zh()).Kh())},t.prototype.Jh=function(t,i){return t=ht(t,i),dt.format(t)},t.prototype.Gh=function(){return this.Yn},t.prototype.Qh=function(t){this.In={Rn:t,Wn:!1}},t.prototype.ji=function(){this.Yn.forEach((function(t){return t.ji()}))},t.prototype.eh=function(){this.$n=null;var t=this.Zh(),i=100;null!==t&&(i=Math.round(1/t.ts())),this.Jn=wt,this.fh()?(this.Jn=dt,i=100):this._h()?(this.Jn=new $(100,1),i=100):null!==t&&(this.Jn=t.Kh()),this.ih=new ct(this,i,this.nh.bind(this),this.hh.bind(this)),this.ih.Dn()},t.prototype.Ph=function(){this.Kn=null},t.prototype.Zh=function(){return this.Yn[0]||null},t.prototype.yh=function(){return this.wh()?this.Si.scaleMargins.bottom*this.Mt()+this.Un:this.Si.scaleMargins.top*this.Mt()+this.jn},t.prototype.kh=function(){return this.wh()?this.Si.scaleMargins.top*this.Mt()+this.jn:this.Si.scaleMargins.bottom*this.Mt()+this.Un},t.prototype.Nh=function(){this.In.Wn||(this.In.Wn=!0,this.ns())},t.prototype.oh=function(){this.zn=null},t.prototype.hh=function(t,i){if(this.Nh(),this.ii())return 0;t=this.An()&&t?ut(t):t;var n=l(this.xh()),h=this.kh()+(this.ph()-1)*(t-n.cn())/n._n();return this.Sh(h)},t.prototype.nh=function(t,i){if(this.Nh(),this.ii())return 0;var n=this.Sh(t),h=l(this.xh()),s=h.cn()+h._n()*((n-this.kh())/(this.ph()-1));return this.An()?at(s):s},t.prototype.bh=function(){this.$n=null,this.ih.Dn()},t.prototype.ns=function(){var t=this.In.Rn;if(null!==t){for(var i=null,n=0,h=0,s=0,r=this.Gh();s<r.length;s++){var e=r[s];if(e.Y()){var u=e.K();if(null!==u){var a=e.hs(t.ss(),t.rs()),o=a&&a.xh();if(null!==o){switch(this.Si.mode){case 1:o=ot(o);break;case 2:o=st(o,u.G);break;case 3:o=et(o,u.G)}if(i=null===i?o:i.dn(l(o)),null!==a){var f=a.es();null!==f&&(n=Math.max(n,f.above),h=Math.max(n,f.below))}}}}}if(n===this.jn&&h===this.Un||(this.jn=n,this.Un=h,this.$n=null,this.oh()),null!==i){if(i.cn()===i.vn()){var c=this.Zh(),v=5*(null===c||this.fh()||this._h()?1:c.ts());i=new J(i.cn()-v,i.vn()+v)}this.Mh(i)}else null===this.Pn&&this.Mh(new J(-.5,.5));this.In.Wn=!0}},t.prototype.Dh=function(){return this.fh()?ht:this._h()?rt:this.An()?ut:null},t.prototype.$h=function(t,i){return void 0===this.th.priceFormatter?(void 0===i&&(i=this.Kh()),i.format(t)):this.th.priceFormatter(t)},t}();function bt(t){void 0!==t.borderColor&&(t.borderUpColor=t.borderColor,t.borderDownColor=t.borderColor),void 0!==t.wickColor&&(t.wickUpColor=t.wickColor,t.wickDownColor=t.wickColor)}!function(t){t[t.LastBar=0]="LastBar",t[t.LastVisible=1]="LastVisible"}(_t||(_t={}));var mt=function(t){return t.getUTCFullYear()};function gt(t,i,n){return i.replace(/yyyy/g,function(t){return K(mt(t),4)}(t)).replace(/yy/g,function(t){return K(mt(t)%100,2)}(t)).replace(/MMMM/g,function(t,i){return new Date(t.getUTCFullYear(),t.getUTCMonth(),1).toLocaleString(i,{month:"long"})}(t,n)).replace(/MMM/g,function(t,i){return new Date(t.getUTCFullYear(),t.getUTCMonth(),1).toLocaleString(i,{month:"short"})}(t,n)).replace(/MM/g,function(t){return K(function(t){return t.getUTCMonth()+1}(t),2)}(t)).replace(/dd/g,function(t){return K(function(t){return t.getUTCDate()}(t),2)}(t))}var pt=function(){function t(t,i){void 0===t&&(t="yyyy-MM-dd"),void 0===i&&(i="default"),this.us=t,this.os=i}return t.prototype.ls=function(t){return gt(t,this.us,this.os)},t}(),yt=function(){function t(t){this.fs=t||"%h:%m:%s"}return t.prototype.ls=function(t){return this.fs.replace("%h",K(t.getUTCHours(),2)).replace("%m",K(t.getUTCMinutes(),2)).replace("%s",K(t.getUTCSeconds(),2))},t}(),kt={cs:"yyyy-MM-dd",vs:"%h:%m:%s",_s:" ",ds:"default"},xt=function(){function t(t){void 0===t&&(t={});var i=e(e({},kt),t);this.ws=new pt(i.cs,i.ds),this.Ms=new yt(i.vs),this.bs=i._s}return t.prototype.ls=function(t){return""+this.ws.ls(t)+this.bs+this.Ms.ls(t)},t}();var Nt=function(){function t(t,i){void 0===i&&(i=50),this.gs=0,this.ps=1,this.ys=1,this.ks=new Map,this.xs=new Map,this.Ns=t,this.Ss=i}return t.prototype.ls=function(t){var i=void 0===t.Cs?new Date(1e3*t.Ds).getTime():new Date(Date.UTC(t.Cs.year,t.Cs.month-1,t.Cs.day)).getTime(),n=this.ks.get(i);if(void 0!==n)return n.Ts;if(this.gs===this.Ss){var h=this.xs.get(this.ys);this.xs.delete(this.ys),this.ks.delete(o(h)),this.ys++,this.gs--}var s=this.Ns(t);return this.ks.set(i,{Ts:s,Es:this.ps}),this.xs.set(this.ps,i),this.gs++,this.ps++,s},t}(),St=function(){function t(t,i){a(t<=i,"right should be >= left"),this.Ls=t,this.Bs=i}return t.prototype.ss=function(){return this.Ls},t.prototype.rs=function(){return this.Bs},t.prototype.As=function(){return this.Bs-this.Ls+1},t.prototype.Vs=function(t){return this.Ls<=t&&t<=this.Bs},t.prototype.ln=function(t){return this.Ls===t.ss()&&this.Bs===t.rs()},t}();function Ct(t,i){return null===t||null===i?t===i:t.ln(i)}var Dt,Tt=function(){function t(){this.Os=new Map,this.ks=null}return t.prototype.zs=function(t){var i=this;this.ks=null,this.Os.clear(),t.forEach((function(t,n){var h=i.Os.get(t.Ps);void 0===h&&(h=[],i.Os.set(t.Ps,h)),h.push({Fs:n,P:t.P,Is:t.Ps})}))},t.prototype.Ws=function(t,i){var n=Math.ceil(i/t);return null!==this.ks&&this.ks.Rs===n||(this.ks={Vn:this.js(n),Rs:n}),this.ks.Vn},t.prototype.js=function(t){for(var i=[],n=0,h=Array.from(this.Os.keys()).sort((function(t,i){return i-t}));n<h.length;n++){var s=h[n];if(this.Os.get(s)){var r=i;i=[];for(var e=r.length,u=0,a=o(this.Os.get(s)),l=a.length,f=1/0,c=-1/0,v=0;v<l;v++){for(var _=a[v],d=_.Fs;u<e;){var w=r[u],M=w.Fs;if(!(M<d)){f=M;break}u++,i.push(w),c=M,f=1/0}f-d>=t&&d-c>=t&&(i.push(_),c=d)}for(;u<e;u++)i.push(r[u])}}return i},t}(),Et=function(){function t(t){this.Us=t}return t.prototype.qs=function(){return null===this.Us?null:new St(Math.floor(this.Us.ss()),Math.ceil(this.Us.rs()))},t.prototype.Hs=function(){return this.Us},t.Ys=function(){return new t(null)},t}();!function(t){t[t.Year=0]="Year",t[t.Month=1]="Month",t[t.DayOfMonth=2]="DayOfMonth",t[t.Time=3]="Time",t[t.TimeWithSeconds=4]="TimeWithSeconds"}(Dt||(Dt={}));var Lt=function(){function t(t,i,n){this.Ks=0,this.$s=null,this.Xs=[],this.Zn=null,this.Xn=null,this.Zs=new Tt,this.Js=new Map,this.Gs=Et.Ys(),this.Qs=!0,this.tr=new Z,this.ir=new Z,this.nr=new Z,this.hr=null,this.sr=null,this.rr=[],this.Si=i,this.th=n,this.er=i.rightOffset,this.ur=i.barSpacing,this.ri=t,this.ar()}return t.prototype.I=function(){return this.Si},t.prototype.lr=function(t){c(this.th,t),this.cr(),this.ar()},t.prototype.rh=function(t,i){var n;c(this.Si,t),this.Si.fixLeftEdge&&this.vr(),this.Si.fixRightEdge&&this._r(),void 0!==t.barSpacing&&this.ri.dr(t.barSpacing),void 0!==t.rightOffset&&this.ri.wr(t.rightOffset),void 0!==t.minBarSpacing&&this.ri.dr(null!==(n=t.barSpacing)&&void 0!==n?n:this.ur),this.cr(),this.ar(),this.nr.rn()},t.prototype.ei=function(t){var i;return(null===(i=this.Xs[t])||void 0===i?void 0:i.P)||null},t.prototype.Mr=function(t,i){if(this.Xs.length<1)return null;if(t.Ds>this.Xs[this.Xs.length-1].P.Ds)return i?this.Xs.length-1:null;for(var n=0;n<this.Xs.length;++n){if(t.Ds===this.Xs[n].P.Ds)return n;if(t.Ds<this.Xs[n].P.Ds)return i?n:null}return null},t.prototype.ii=function(){return 0===this.Ks||0===this.Xs.length},t.prototype.br=function(){return this.mr(),this.Gs.qs()},t.prototype.gr=function(){return this.mr(),this.Gs.Hs()},t.prototype.pr=function(){var t=this.br();if(null===t)return null;var i={from:t.ss(),to:t.rs()};return this.yr(i)},t.prototype.yr=function(t){var i=Math.round(t.from),n=Math.round(t.to),h=l(this.kr()),s=l(this.Nr());return{from:l(this.ei(Math.max(h,i))),to:l(this.ei(Math.min(s,n)))}},t.prototype.Sr=function(t){return{from:l(this.Mr(t.from,!0)),to:l(this.Mr(t.to,!0))}},t.prototype.Cr=function(){return this.Zs},t.prototype.wt=function(){return this.Ks},t.prototype.Dr=function(t){if(isFinite(t)&&!(t<=0)&&this.Ks!==t){if(this.Si.lockVisibleTimeRangeOnResize&&this.Ks){var i=this.ur*t/this.Ks;this.Tr(i)}if(this.Si.fixLeftEdge){var n=this.br();if(null!==n)if(n.ss()<=0){var h=this.Ks-t;this.er-=Math.round(h/this.ur)+1}}this.Ks=t,this.Qs=!0,this.Er(),this.Lr()}},t.prototype.tt=function(t){if(this.ii()||!_(t))return 0;var i=this.Br()+this.er-t;return this.Ks-(i+.5)*this.ur-1},t.prototype.Ar=function(t,i){for(var n=this.Br(),h=void 0===i?0:i.from,s=void 0===i?t.length:i.to,r=h;r<s;r++){var e=t[r].P,u=n+this.er-e,a=this.Ks-(u+.5)*this.ur-1;t[r].g=a}},t.prototype.Vr=function(t){return Math.ceil(this.Or(t))},t.prototype.wr=function(t){this.Qs=!0,this.er=t,this.Lr(),this.ri.zr(),this.ri.Pr()},t.prototype.Fr=function(){return this.ur},t.prototype.dr=function(t){this.Tr(t),this.Lr(),this.ri.zr(),this.ri.Pr()},t.prototype.Ir=function(){return this.er},t.prototype.Vn=function(){if(this.ii())return null;if(null!==this.sr)return this.sr;for(var t=this.ur,i=5*(this.ri.I().layout.fontSize+4),n=Math.round(i/t),h=l(this.br()),s=Math.max(h.ss(),h.ss()-n),r=Math.max(h.rs(),h.rs()-n),e=0,u=0,a=this.Zs.Ws(t,i);u<a.length;u++){var o=a[u];if(s<=o.Fs&&o.Fs<=r){var f=this.ei(o.Fs);if(null!==f){if(e<this.rr.length){var c=this.rr[e];c.En=this.tt(o.Fs),c.Ln=this.Wr(f,o.Is),c.Is=o.Is}else this.rr.push({En:this.tt(o.Fs),Ln:this.Wr(f,o.Is),Is:o.Is});e++}}}return this.rr.length=e,this.sr=this.rr,this.rr},t.prototype.Rr=function(){this.Qs=!0,this.dr(this.Si.barSpacing),this.wr(this.Si.rightOffset)},t.prototype.jr=function(t){this.Qs=!0,this.$s=t,this.Lr(),this.vr()},t.prototype.Ur=function(t,i){var n=this.Or(t),h=this.Fr(),s=h+i*(h/10);this.dr(s),this.Si.rightBarStaysOnScroll||this.wr(this.Ir()+(n-this.Or(t)))},t.prototype.Rh=function(t){this.Zn&&this.Yh(),null===this.Xn&&null===this.hr&&(this.ii()||(this.Xn=t,this.qr()))},t.prototype.jh=function(t){if(null!==this.hr){var i=G(this.Ks-t,0,this.Ks),n=G(this.Ks-l(this.Xn),0,this.Ks);0!==i&&0!==n&&this.dr(this.hr.Fr*i/n)}},t.prototype.Uh=function(){null!==this.Xn&&(this.Xn=null,this.Hr())},t.prototype.qh=function(t){null===this.Zn&&null===this.hr&&(this.ii()||(this.Zn=t,this.qr()))},t.prototype.Hh=function(t){if(null!==this.Zn){var i=(this.Zn-t)/this.Fr();this.er=l(this.hr).Ir+i,this.Qs=!0,this.Lr()}},t.prototype.Yh=function(){null!==this.Zn&&(this.Zn=null,this.Hr())},t.prototype.Yr=function(){this.Kr(this.Si.rightOffset)},t.prototype.Kr=function(t,i){var n=this;if(void 0===i&&(i=400),!isFinite(t))throw new RangeError("offset is required and must be finite number");if(!isFinite(i)||i<=0)throw new RangeError("animationDuration (optional) must be finite positive number");var h=this.er,s=Date.now(),r=function(){var e=(Date.now()-s)/i,u=e>=1,a=u?t:h+(t-h)*e;n.wr(a),u||setTimeout(r,20)};r()},t.prototype.V=function(t){this.Qs=!0,this.Xs=t,this.Zs.zs(t),this.Lr()},t.prototype.$r=function(){return this.tr},t.prototype.Xr=function(){return this.ir},t.prototype.Zr=function(){return this.nr},t.prototype.Br=function(){return this.$s||0},t.prototype.Jr=function(t){var i=t.As();this.Tr(this.Ks/i),this.er=t.rs()-this.Br(),this.Lr(),this.Qs=!0,this.ri.zr(),this.ri.Pr()},t.prototype.Gr=function(){var t=this.kr(),i=this.Nr();null!==t&&null!==i&&this.Jr(new St(t,i+this.Si.rightOffset))},t.prototype.Qr=function(t){var i=new St(t.from,t.to);this.Jr(i)},t.prototype.ui=function(t){return void 0!==this.th.timeFormatter?this.th.timeFormatter(t.Cs||t.Ds):this.te.ls(new Date(1e3*t.Ds))},t.prototype.kr=function(){return 0===this.Xs.length?null:0},t.prototype.Nr=function(){return 0===this.Xs.length?null:this.Xs.length-1},t.prototype.ie=function(t){return(this.Ks-1-t)/this.ur},t.prototype.Or=function(t){var i=this.ie(t),n=this.Br()+this.er-i;return Math.round(1e6*n)/1e6},t.prototype.Tr=function(t){var i=this.ur;this.ur=t,this.Er(),i!==this.ur&&(this.Qs=!0,this.ne())},t.prototype.mr=function(){if(this.Qs)if(this.Qs=!1,this.ii())this.he(Et.Ys());else{var t=this.Br(),i=this.Ks/this.ur,n=this.er+t,h=new St(n-i+1,n);this.he(new Et(h))}},t.prototype.Er=function(){var t=this.se();if(this.ur<t&&(this.ur=t,this.Qs=!0),0!==this.Ks){var i=.5*this.Ks;this.ur>i&&(this.ur=i,this.Qs=!0)}},t.prototype.se=function(){return this.Si.fixLeftEdge&&this.Si.fixRightEdge?this.Ks/this.Xs.length:this.Si.minBarSpacing},t.prototype.Lr=function(){var t=this.re();this.er>t&&(this.er=t,this.Qs=!0);var i=this.ee();null!==i&&this.er<i&&(this.er=i,this.Qs=!0)},t.prototype.ee=function(){var t=this.kr(),i=this.$s;return null===t||null===i?null:t-i-1+(this.Si.fixLeftEdge?this.Ks/this.ur:Math.min(2,this.Xs.length))},t.prototype.re=function(){return this.Si.fixRightEdge?0:this.Ks/this.ur-Math.min(2,this.Xs.length)},t.prototype.qr=function(){this.hr={Fr:this.Fr(),Ir:this.Ir()}},t.prototype.Hr=function(){this.hr=null},t.prototype.Wr=function(t,i){var n=this,h=this.Js.get(i);return void 0===h&&(h=new Nt((function(t){return n.ue(t,i)})),this.Js.set(i,h)),h.ls(t)},t.prototype.ue=function(t,i){var n,h,s=this.Si.timeVisible;return h=i<20&&s?this.Si.secondsVisible?4:3:i<40&&s?3:i<50||i<60?2:i<70?1:0,void 0!==this.Si.tickMarkFormatter?this.Si.tickMarkFormatter(null!==(n=t.Cs)&&void 0!==n?n:t.Ds,h,this.th.locale):function(t,i,n){var h={};switch(i){case 0:h.year="numeric";break;case 1:h.month="short";break;case 2:h.day="numeric";break;case 3:h.hour12=!1,h.hour="2-digit",h.minute="2-digit";break;case 4:h.hour12=!1,h.hour="2-digit",h.minute="2-digit",h.second="2-digit"}var s=void 0===t.Cs?new Date(1e3*t.Ds):new Date(Date.UTC(t.Cs.year,t.Cs.month-1,t.Cs.day));return new Date(s.getUTCFullYear(),s.getUTCMonth(),s.getUTCDate(),s.getUTCHours(),s.getUTCMinutes(),s.getUTCSeconds(),s.getUTCMilliseconds()).toLocaleString(n,h)}(t,h,this.th.locale)},t.prototype.he=function(t){var i=this.Gs;this.Gs=t,Ct(i.qs(),this.Gs.qs())||this.tr.rn(),Ct(i.Hs(),this.Gs.Hs())||this.ir.rn(),this.ne()},t.prototype.ne=function(){this.sr=null},t.prototype.cr=function(){this.ne(),this.Js.clear()},t.prototype.ar=function(){var t=this.th.dateFormat;this.Si.timeVisible?this.te=new xt({cs:t,vs:this.Si.secondsVisible?"%h:%m:%s":"%h:%m",_s:"   ",ds:this.th.locale}):this.te=new pt(t,this.th.locale)},t.prototype.vr=function(){if(this.Si.fixLeftEdge){var t=this.kr();if(null!==t){var i=l(this.br()).ss()-t;if(i<0){var n=this.er-i-1;this.wr(n)}this.Er()}}},t.prototype._r=function(){this.Lr(),this.Er()},t}();function Bt(t){return!v(t)&&!d(t)}function At(t){return v(t)}var Vt="'Trebuchet MS', Roboto, Ubuntu, sans-serif";function Ot(t,i,n){return void 0!==n?n+=" ":n="",void 0===i&&(i=Vt),""+n+t+"px "+i}var zt=function(){function t(t){this.ae={Tt:1,Dt:4,Pt:NaN,Nt:"",oe:"",ut:"",Lt:0,Bt:0,At:0,Et:0,zt:0},this.B=t}return t.prototype.I=function(){var t=this.ae,i=this.le(),n=this.fe();return t.Pt===i&&t.oe===n||(t.Pt=i,t.oe=n,t.Nt=Ot(i,n),t.Et=Math.floor(i/3.5),t.Lt=t.Et,t.Bt=Math.max(Math.ceil(i/2-t.Dt/2),0),t.At=Math.ceil(i/2+t.Dt/2),t.zt=Math.round(i/10)),t.ut=this.ce(),this.ae},t.prototype.ce=function(){return this.B.I().layout.textColor},t.prototype.le=function(){return this.B.I().layout.fontSize},t.prototype.fe=function(){return this.B.I().layout.fontFamily},t}();function Pt(t){return"left"===t||"right"===t}var Ft=function(){function t(t){this.ve=new Map,this._e=!1,this.de=[],this.we=t}return t.prototype.Me=function(t,i){var n=function(t,i){return void 0===t?i:{be:Math.max(t.be,i.be),dh:t.dh||i.dh}}(this.ve.get(t),i);this.ve.set(t,n)},t.prototype.me=function(){return this.we},t.prototype.ge=function(t){var i=this.ve.get(t);return void 0===i?{be:this.we}:{be:Math.max(this.we,i.be),dh:i.dh}},t.prototype.pe=function(){this.de=[{ye:0}]},t.prototype.ke=function(t){this.de=[{ye:1,G:t}]},t.prototype.xe=function(){this.de=[{ye:4}]},t.prototype.dr=function(t){this.de.push({ye:2,G:t})},t.prototype.wr=function(t){this.de.push({ye:3,G:t})},t.prototype.Ne=function(){return this.de},t.prototype.dn=function(t){var i=this;this._e=this._e||t._e,this.de=this.de.concat(t.de);for(var n=0,h=t.de;n<h.length;n++){var s=h[n];this.Se(s)}this.we=Math.max(this.we,t.we),t.ve.forEach((function(t,n){i.Me(n,t)}))},t.prototype.Se=function(t){switch(t.ye){case 0:this.pe();break;case 1:this.ke(t.G);break;case 2:this.dr(t.G);break;case 3:this.wr(t.G);break;case 4:this.xe()}},t}(),It=function(){function t(t){this.Ce=t}return t.prototype.format=function(t){var i="";return t<0&&(i="-",t=-t),t<995?i+this.De(t):t<999995?i+this.De(t/1e3)+"K":t<999999995?(t=1e3*Math.round(t/1e3),i+this.De(t/1e6)+"M"):(t=1e6*Math.round(t/1e6),i+this.De(t/1e9)+"B")},t.prototype.De=function(t){var i=Math.pow(10,this.Ce);return((t=Math.round(t*i)/i)>=1e-15&&t<1?t.toFixed(this.Ce).replace(/\.?0+$/,""):String(t)).replace(/(\.[1-9]*)0+$/,(function(t,i){return i}))},t}();function Wt(t,i,n,h){if(0!==i.length){var s=i[h.from].g,r=i[h.from].p;t.moveTo(s,r);for(var e=h.from+1;e<h.to;++e){var u=i[e];if(1===n){var a=i[e-1].p,o=u.g;t.lineTo(o,a)}t.lineTo(u.g,u.p)}}}var Rt=function(t){function i(){var i=null!==t&&t.apply(this,arguments)||this;return i.v=null,i}return r(i,t),i.prototype._=function(t){this.v=t},i.prototype.u=function(t){if(null!==this.v&&0!==this.v.m.length&&null!==this.v.M){if(t.lineCap="butt",t.lineJoin="round",t.strokeStyle=this.v.S,t.lineWidth=this.v.et,n(t,this.v.at),t.lineWidth=1,t.beginPath(),1===this.v.m.length){var i=this.v.m[0],h=this.v.Te/2;t.moveTo(i.g-h,this.v.Ee),t.lineTo(i.g-h,i.p),t.lineTo(i.g+h,i.p),t.lineTo(i.g+h,this.v.Ee)}else t.moveTo(this.v.m[this.v.M.from].g,this.v.Ee),t.lineTo(this.v.m[this.v.M.from].g,this.v.m[this.v.M.from].p),Wt(t,this.v.m,this.v.Le,this.v.M),this.v.M.to>this.v.M.from&&(t.lineTo(this.v.m[this.v.M.to-1].g,this.v.Ee),t.lineTo(this.v.m[this.v.M.from].g,this.v.Ee));t.closePath();var s=t.createLinearGradient(0,0,0,this.v.Ee);s.addColorStop(0,this.v.Be),s.addColorStop(1,this.v.Ae),t.fillStyle=s,t.fill()}},i}(p),jt=function(t){function i(){var i=null!==t&&t.apply(this,arguments)||this;return i.v=null,i}return r(i,t),i.prototype._=function(t){this.v=t},i.prototype.u=function(t){if(null!==this.v&&0!==this.v.m.length&&null!==this.v.M){if(t.lineCap="butt",t.lineWidth=this.v.et,n(t,this.v.at),t.strokeStyle=this.v.S,t.lineJoin="round",t.beginPath(),1===this.v.m.length){var i=this.v.m[0];t.moveTo(i.g-this.v.Te/2,i.p),t.lineTo(i.g+this.v.Te/2,i.p)}else Wt(t,this.v.m,this.v.Le,this.v.M);t.stroke()}},i}(p);function Ut(t,i,n,h,s){void 0===h&&(h=0),void 0===s&&(s=t.length);for(var r=s-h;0<r;){var e=r>>1,u=h+e;n(t[u],i)?(h=u+1,r-=e+1):r=e}return h}function qt(t,i,n,h,s){void 0===h&&(h=0),void 0===s&&(s=t.length);for(var r=s-h;0<r;){var e=r>>1,u=h+e;n(i,t[u])?r=e:(h=u+1,r-=e+1)}return h}function Ht(t,i){return t.P<i}function Yt(t,i){return t<i.P}function Kt(t,i,n){var h=i.ss(),s=i.rs(),r=Ut(t,h,Ht),e=qt(t,s,Yt);if(!n)return{from:r,to:e};var u=r,a=e;return r>0&&r<t.length&&t[r].P>=h&&(u=r-1),e>0&&e<t.length&&t[e-1].P<=s&&(a=e+1),{from:u,to:a}}var $t=function(){function t(t,i,n){this.Ve=!0,this.Oe=!0,this.ze=!0,this.Pe=[],this.Fe=null,this.Ie=t,this.We=i,this.Re=n}return t.prototype.V=function(t){this.Ve=!0,"data"===t&&(this.Oe=!0),"options"===t&&(this.ze=!0)},t.prototype.je=function(){this.Oe&&(this.Ue(),this.Oe=!1),this.Ve&&(this.qe(),this.Ve=!1),this.ze&&(this.He(),this.ze=!1)},t.prototype.Ye=function(){this.Fe=null},t.prototype.qe=function(){var t=this.Ie.J(),i=this.We.q();if(this.Ye(),!i.ii()&&!t.ii()){var n=i.br();if(null!==n&&0!==this.Ie.Yi().Ke()){var h=this.Ie.K();null!==h&&(this.Fe=Kt(this.Pe,n,this.Re),this.$e(t,i,h.G))}}},t}(),Xt=function(t){function i(i,n){return t.call(this,i,n,!0)||this}return r(i,t),i.prototype.$e=function(t,i,n){i.Ar(this.Pe,m(this.Fe)),t.Ch(this.Pe,n,m(this.Fe))},i.prototype.Xe=function(t,i){return{P:t,F:i,g:NaN,p:NaN}},i.prototype.He=function(){},i.prototype.Ue=function(){var t=this,i=this.Ie.Ze();this.Pe=this.Ie.Yi().Je().map((function(n){var h=n.G[3];return t.Ge(n.Fs,h,i)}))},i}($t),Zt=function(t){function i(i,n){var h=t.call(this,i,n)||this;return h.lt=new g,h.Qe=new Rt,h.tu=new jt,h.lt.i([h.Qe,h.tu]),h}return r(i,t),i.prototype.W=function(t,i){if(!this.Ie.Y())return null;var n=this.Ie.I();this.je();var h={Le:n.lineType,m:this.Pe,S:n.lineColor,at:n.lineStyle,et:n.lineWidth,Be:n.topColor,Ae:n.bottomColor,Ee:t,M:this.Fe,Te:this.We.q().Fr()};return this.Qe._(h),this.tu._(h),this.lt},i.prototype.Ge=function(t,i){return this.Xe(t,i)},i}(Xt);var Jt=function(){function t(){this.it=null,this.iu=0,this.nu=0}return t.prototype._=function(t){this.it=t},t.prototype.h=function(t,i,n,h){if(null!==this.it&&0!==this.it.Yi.length&&null!==this.it.M){if(this.iu=this.hu(i),this.iu>=2)Math.max(1,Math.floor(i))%2!=this.iu%2&&this.iu--;this.nu=this.it.su?Math.min(this.iu,Math.floor(i)):this.iu;for(var s=null,r=this.nu<=this.iu&&this.it.Fr>=Math.floor(1.5*i),e=this.it.M.from;e<this.it.M.to;++e){var u=this.it.Yi[e];s!==u.ut&&(t.fillStyle=u.ut,s=u.ut);var a=Math.floor(.5*this.nu),o=Math.round(u.g*i),l=o-a,f=this.nu,c=l+f-1,v=Math.min(u.Lh,u.Bh),_=Math.max(u.Lh,u.Bh),d=Math.round(v*i)-a,w=Math.round(_*i)+a,M=Math.max(w-d,this.nu);t.fillRect(l,d,f,M);var b=Math.ceil(1.5*this.iu);if(r){if(this.it.ru){var m=o-b,g=Math.max(d,Math.round(u.Eh*i)-a),p=g+f-1;p>d+M-1&&(g=(p=d+M-1)-f+1),t.fillRect(m,g,l-m,p-g+1)}var y=o+b,k=Math.max(d,Math.round(u.Ah*i)-a),x=k+f-1;x>d+M-1&&(k=(x=d+M-1)-f+1),t.fillRect(c+1,k,y-c,x-k+1)}}}},t.prototype.hu=function(t){var i=Math.floor(t);return Math.max(i,Math.floor(function(t,i){return Math.floor(.3*t*i)}(l(this.it).Fr,t)))},t}(),Gt=function(t){function i(i,n){return t.call(this,i,n,!1)||this}return r(i,t),i.prototype.$e=function(t,i,n){i.Ar(this.Pe,m(this.Fe)),t.Th(this.Pe,n,m(this.Fe))},i.prototype.eu=function(t,i,n){return{P:t,open:i.G[0],high:i.G[1],low:i.G[2],close:i.G[3],g:NaN,Eh:NaN,Lh:NaN,Bh:NaN,Ah:NaN}},i.prototype.Ue=function(){var t=this,i=this.Ie.Ze();this.Pe=this.Ie.Yi().Je().map((function(n){return t.Ge(n.Fs,n,i)}))},i}($t),Qt=function(t){function i(){var i=null!==t&&t.apply(this,arguments)||this;return i.lt=new Jt,i}return r(i,t),i.prototype.W=function(t,i){if(!this.Ie.Y())return null;var n=this.Ie.I();this.je();var h={Yi:this.Pe,Fr:this.We.q().Fr(),ru:n.openVisible,su:n.thinBars,M:this.Fe};return this.lt._(h),this.lt},i.prototype.He=function(){var t=this;this.Pe.forEach((function(i){i.ut=t.Ie.Ze().au(i.P).uu}))},i.prototype.Ge=function(t,i,n){return e(e({},this.eu(t,i,n)),{ut:n.au(t).uu})},i}(Gt),ti=function(){function t(){this.it=null,this.iu=0}return t.prototype._=function(t){this.it=t},t.prototype.h=function(t,i,n,h){if(null!==this.it&&0!==this.it.Yi.length&&null!==this.it.M){if(this.iu=function(t,i){if(t>=2.5&&t<=4)return Math.floor(3*i);var n=1-.2*Math.atan(Math.max(4,t)-4)/(.5*Math.PI),h=Math.floor(t*n*i),s=Math.floor(t*i),r=Math.min(h,s);return Math.max(Math.floor(i),r)}(this.it.Fr,i),this.iu>=2)Math.floor(i)%2!=this.iu%2&&this.iu--;var s=this.it.Yi;this.it.ou&&this.lu(t,s,this.it.M,i),this.it.fu&&this.cu(t,s,this.it.M,this.it.Fr,i);var r=this.vu(i);(!this.it.fu||this.iu>2*r)&&this._u(t,s,this.it.M,i)}},t.prototype.lu=function(t,i,n,h){if(null!==this.it){var s="",r=Math.min(Math.floor(h),Math.floor(this.it.Fr*h));r=Math.max(Math.floor(h),Math.min(r,this.iu));for(var e=Math.floor(.5*r),u=null,a=n.from;a<n.to;a++){var o=i[a];o.du!==s&&(t.fillStyle=o.du,s=o.du);var l=Math.round(Math.min(o.Eh,o.Ah)*h),f=Math.round(Math.max(o.Eh,o.Ah)*h),c=Math.round(o.Lh*h),v=Math.round(o.Bh*h),_=Math.round(h*o.g)-e,d=_+r-1;null!==u&&(_=Math.max(u+1,_),_=Math.min(_,d));var w=d-_+1;t.fillRect(_,c,w,l-c),t.fillRect(_,f+1,w,v-f),u=d}}},t.prototype.vu=function(t){var i=Math.floor(1*t);this.iu<=2*i&&(i=Math.floor(.5*(this.iu-1)));var n=Math.max(Math.floor(t),i);return this.iu<=2*n?Math.max(Math.floor(t),Math.floor(1*t)):n},t.prototype.cu=function(t,i,n,h,s){if(null!==this.it)for(var r="",e=this.vu(s),u=null,a=n.from;a<n.to;a++){var o=i[a];o.X!==r&&(t.fillStyle=o.X,r=o.X);var l=Math.round(o.g*s)-Math.floor(.5*this.iu),f=l+this.iu-1,c=Math.round(Math.min(o.Eh,o.Ah)*s),v=Math.round(Math.max(o.Eh,o.Ah)*s);if(null!==u&&(l=Math.max(u+1,l),l=Math.min(l,f)),this.it.Fr*s>2*e)V(t,l,c,f-l+1,v-c+1,e);else{var _=f-l+1;t.fillRect(l,c,_,v-c+1)}u=f}},t.prototype._u=function(t,i,n,h){if(null!==this.it)for(var s="",r=this.vu(h),e=n.from;e<n.to;e++){var u=i[e],a=Math.round(Math.min(u.Eh,u.Ah)*h),o=Math.round(Math.max(u.Eh,u.Ah)*h),l=Math.round(u.g*h)-Math.floor(.5*this.iu),f=l+this.iu-1;if(u.ut!==s){var c=u.ut;t.fillStyle=c,s=c}this.it.fu&&(l+=r,a+=r,f-=r,o-=r),a>o||t.fillRect(l,a,f-l+1,o-a+1)}},t}(),ii=function(t){function i(){var i=null!==t&&t.apply(this,arguments)||this;return i.lt=new ti,i}return r(i,t),i.prototype.W=function(t,i){if(!this.Ie.Y())return null;var n=this.Ie.I();this.je();var h={Yi:this.Pe,Fr:this.We.q().Fr(),ou:n.wickVisible,fu:n.borderVisible,M:this.Fe};return this.lt._(h),this.lt},i.prototype.He=function(){var t=this;this.Pe.forEach((function(i){var n=t.Ie.Ze().au(i.P);i.ut=n.uu,i.du=n.wu,i.X=n.Mu}))},i.prototype.Ge=function(t,i,n){var h=n.au(t);return e(e({},this.eu(t,i,n)),{ut:h.uu,du:h.wu,X:h.Mu})},i}(Gt),ni=function(){function t(){this.it=null,this.bu=[]}return t.prototype._=function(t){this.it=t,this.bu=[]},t.prototype.h=function(t,i,n,h){if(null!==this.it&&0!==this.it.m.length&&null!==this.it.M){this.bu.length||this.mu(i);for(var s=Math.max(1,Math.floor(i)),r=Math.round(this.it.gu*i)-Math.floor(s/2),e=r+s,u=this.it.M.from;u<this.it.M.to;u++){var a=this.it.m[u],o=this.bu[u-this.it.M.from],l=Math.round(a.p*i);t.fillStyle=a.ut;var f=void 0,c=void 0;l<=r?(f=l,c=e):(f=r,c=l-Math.floor(s/2)+s),t.fillRect(o.ss,f,o.rs-o.ss+1,c-f)}}},t.prototype.mu=function(t){if(null!==this.it&&0!==this.it.m.length&&null!==this.it.M){var i=Math.ceil(this.it.Fr*t)<=1?0:Math.max(1,Math.floor(t)),n=Math.round(this.it.Fr*t)-i;this.bu=new Array(this.it.M.to-this.it.M.from);for(var h=this.it.M.from;h<this.it.M.to;h++){var s,r=this.it.m[h],e=Math.round(r.g*t),u=void 0,a=void 0;if(n%2)u=e-(s=(n-1)/2),a=e+s;else u=e-(s=n/2),a=e+s-1;this.bu[h-this.it.M.from]={ss:u,rs:a,pu:e,yu:r.g*t,P:r.P}}for(h=this.it.M.from+1;h<this.it.M.to;h++){var o=this.bu[h-this.it.M.from],l=this.bu[h-this.it.M.from-1];o.P===l.P+1&&(o.ss-l.rs!==i+1&&(l.pu>l.yu?l.rs=o.ss-i-1:o.ss=l.rs+i+1))}var f=Math.ceil(this.it.Fr*t);for(h=this.it.M.from;h<this.it.M.to;h++){(o=this.bu[h-this.it.M.from]).rs<o.ss&&(o.rs=o.ss);var c=o.rs-o.ss+1;f=Math.min(c,f)}if(i>0&&f<4)for(h=this.it.M.from;h<this.it.M.to;h++){(c=(o=this.bu[h-this.it.M.from]).rs-o.ss+1)>f&&(o.pu>o.yu?o.rs-=1:o.ss+=1)}}else this.bu=[]},t}();function hi(t){return{m:[],Fr:t,gu:NaN,M:null}}function si(t,i,n){return{P:t,F:i,g:NaN,p:NaN,ut:n}}var ri=function(t){function i(i,n){var h=t.call(this,i,n,!1)||this;return h.C=new g,h.ku=hi(0),h.lt=new ni,h}return r(i,t),i.prototype.W=function(t,i){return this.Ie.Y()?(this.je(),this.C):null},i.prototype.Ue=function(){var t=this.We.q().Fr();this.ku=hi(t);for(var i=0,n=0,h=this.Ie.I().color,s=0,r=this.Ie.Yi().Je();s<r.length;s++){var e=r[s],u=e.G[3],a=void 0!==e.ut?e.ut:h,o=si(e.Fs,u,a);++i<this.ku.m.length?this.ku.m[i]=o:this.ku.m.push(o),this.Pe[n++]={P:e.Fs,g:0}}this.lt._(this.ku),this.C.i([this.lt])},i.prototype.He=function(){},i.prototype.Ye=function(){t.prototype.Ye.call(this),this.ku.M=null},i.prototype.$e=function(t,i,n){if(null!==this.Fe){var h=i.Fr(),s=l(i.br()),r=t.Z(this.Ie.I().base,n);i.Ar(this.ku.m),t.Ch(this.ku.m,n),this.ku.gu=r,this.ku.M=Kt(this.ku.m,s,!1),this.ku.Fr=h,this.lt._(this.ku)}},i}($t),ei=function(t){function i(i,n){var h=t.call(this,i,n)||this;return h.tu=new jt,h}return r(i,t),i.prototype.W=function(t,i){if(!this.Ie.Y())return null;var n=this.Ie.I();this.je();var h={m:this.Pe,S:n.color,at:n.lineStyle,Le:n.lineType,et:n.lineWidth,M:this.Fe,Te:this.We.q().Fr()};return this.tu._(h),this.tu},i.prototype.Ge=function(t,i){return this.Xe(t,i)},i}(Xt),ui=/[2-9]/g,ai=function(){function t(t){void 0===t&&(t=50),this.ks=new Map,this.xu=0,this.Nu=Array.from(new Array(t))}return t.prototype.Su=function(){this.ks.clear(),this.Nu.fill(void 0)},t.prototype.Ot=function(t,i,n){var h=n||ui,s=String(i).replace(h,"0"),r=this.ks.get(s);if(void 0===r){if(0===(r=t.measureText(s).width)&&0!==i.length)return 0;var e=this.Nu[this.xu];void 0!==e&&this.ks.delete(e),this.Nu[this.xu]=s,this.xu=(this.xu+1)%this.Nu.length,this.ks.set(s,r)}return r},t}(),oi=function(){function t(t){this.Cu=null,this.ae=null,this.Du="right",this.Ks=0,this.Tu=t}return t.prototype.Eu=function(t,i,n,h){this.Cu=t,this.ae=i,this.Ks=n,this.Du=h},t.prototype.h=function(t,i){null!==this.ae&&null!==this.Cu&&this.Cu.h(t,this.ae,this.Tu,this.Ks,this.Du,i)},t}(),li=function(){function t(t,i,n){this.Lu=t,this.Tu=new ai(50),this.Bu=i,this.B=n,this.le=-1,this.lt=new oi(this.Tu)}return t.prototype.W=function(t,i){var n=this.B.Au(this.Bu);if(null===n)return null;var h=n.Vu(this.Bu)?n.Ti():this.Bu.J();if(null===h)return null;var s=n.Ou(h);if("overlay"===s)return null;var r=this.B.zu();return r.Pt!==this.le&&(this.le=r.Pt,this.Tu.Su()),this.lt.Eu(this.Lu.Jt(),r,i,s),this.lt},t}(),fi=function(){function t(){this.it=null}return t.prototype._=function(t){this.it=t},t.prototype.h=function(t,i,s,r){if(null!==this.it&&!1!==this.it.Y){var e=Math.round(this.it.p*i);if(!(e<0||e>Math.ceil(this.it.Mt*i))){var u=Math.ceil(this.it.wt*i);t.lineCap="butt",t.strokeStyle=this.it.ut,t.lineWidth=Math.floor(this.it.et*i),n(t,this.it.at),h(t,e,0,u)}}},t}(),ci=function(){function t(t){this.Pu={wt:0,Mt:0,p:0,ut:"rgba(0, 0, 0, 0)",et:1,at:0,Y:!1},this.Fu=new fi,this.Ut=!0,this.Ie=t,this.We=t.ct(),this.Fu._(this.Pu)}return t.prototype.V=function(){this.Ut=!0},t.prototype.W=function(t,i){return this.Ie.Y()?(this.Ut&&(this.Iu(t,i),this.Ut=!1),this.Fu):null},t}(),vi=function(t){function i(i){return t.call(this,i)||this}return r(i,t),i.prototype.Iu=function(t,i){this.Pu.Y=!1;var n=this.Ie.J(),h=n.ah().ah;if(2===h||3===h){var s=this.Ie.I();if(s.baseLineVisible&&this.Ie.Y()){var r=this.Ie.K();null!==r&&(this.Pu.Y=!0,this.Pu.p=n.Z(r.G,r.G),this.Pu.wt=i,this.Pu.Mt=t,this.Pu.ut=s.baseLineColor,this.Pu.et=s.baseLineWidth,this.Pu.at=s.baseLineStyle)}}},i}(ci);function _i(t,i){return nt(Math.min(Math.max(t,12),30)*i)}function di(t,i){switch(t){case"arrowDown":case"arrowUp":return _i(i,1);case"circle":return _i(i,.8);case"square":return _i(i,.7)}}function wi(t){return it(_i(t,1))}function Mi(t){return Math.max(_i(t,.1),3)}function bi(t,i,n,h,s){var r=di("square",n),e=(r-1)/2,u=t-e,a=i-e;return h>=u&&h<=u+r&&s>=a&&s<=a+r}function mi(t,i,n,h,s){var r=(di("arrowUp",s)-1)/2,e=(nt(s/2)-1)/2;i.beginPath(),t?(i.moveTo(n-r,h),i.lineTo(n,h-r),i.lineTo(n+r,h),i.lineTo(n+e,h),i.lineTo(n+e,h+r),i.lineTo(n-e,h+r),i.lineTo(n-e,h)):(i.moveTo(n-r,h),i.lineTo(n,h+r),i.lineTo(n+r,h),i.lineTo(n+e,h),i.lineTo(n+e,h-r),i.lineTo(n-e,h-r),i.lineTo(n-e,h)),i.fill()}function gi(t,i,n,h,s,r){return bi(i,n,h,s,r)}var pi=function(t){function i(){var i=null!==t&&t.apply(this,arguments)||this;return i.it=null,i.Tu=new ai,i.le=-1,i.fe="",i.Wu="",i}return r(i,t),i.prototype._=function(t){this.it=t},i.prototype.Eu=function(t,i){this.le===t&&this.fe===i||(this.le=t,this.fe=i,this.Wu=Ot(t,i),this.Tu.Su())},i.prototype.Ru=function(t,i){if(null===this.it||null===this.it.M)return null;for(var n=this.it.M.from;n<this.it.M.to;n++){var h=this.it.m[n];if(ki(h,t,i))return{ju:h.Uu,qu:h.qu}}return null},i.prototype.u=function(t,i,n){if(null!==this.it&&null!==this.it.M){t.textBaseline="middle",t.font=this.Wu;for(var h=this.it.M.from;h<this.it.M.to;h++){var s=this.it.m[h];void 0!==s.Vt&&(s.Vt.wt=this.Tu.Ot(t,s.Vt.Hu),s.Vt.Mt=this.le),yi(s,t)}}},i}(p);function yi(t,i){i.fillStyle=t.ut,void 0!==t.Vt&&function(t,i,n,h){t.fillText(i,n,h)}(i,t.Vt.Hu,t.g-t.Vt.wt/2,t.Vt.p),function(t,i){if(0===t.Ke)return;switch(t.Yu){case"arrowDown":return void mi(!1,i,t.g,t.p,t.Ke);case"arrowUp":return void mi(!0,i,t.g,t.p,t.Ke);case"circle":return void function(t,i,n,h){var s=(di("circle",h)-1)/2;t.beginPath(),t.arc(i,n,s,0,2*Math.PI,!1),t.fill()}(i,t.g,t.p,t.Ke);case"square":return void function(t,i,n,h){var s=di("square",h),r=(s-1)/2,e=i-r,u=n-r;t.fillRect(e,u,s,s)}(i,t.g,t.p,t.Ke)}t.Yu}(t,i)}function ki(t,i,n){return!(void 0===t.Vt||!function(t,i,n,h,s,r){var e=h/2;return s>=t&&s<=t+n&&r>=i-e&&r<=i+e}(t.g,t.Vt.p,t.Vt.wt,t.Vt.Mt,i,n))||function(t,i,n){if(0===t.Ke)return!1;switch(t.Yu){case"arrowDown":case"arrowUp":return gi(0,t.g,t.p,t.Ke,i,n);case"circle":return function(t,i,n,h,s){var r=2+di("circle",n)/2,e=t-h,u=i-s;return Math.sqrt(e*e+u*u)<=r}(t.g,t.p,t.Ke,i,n);case"square":return bi(t.g,t.p,t.Ke,i,n)}t.Yu}(t,i,n)}function xi(t,i,n,h,s,r,e,u,a){var o=v(n)?n:n.close,l=v(n)?n:n.high,f=v(n)?n:n.low,c=v(i.size)?Math.max(i.size,0):1,_=wi(u.Fr())*c,d=_/2;switch(t.Ke=_,i.position){case"inBar":return t.p=e.Z(o,a),void(void 0!==t.Vt&&(t.Vt.p=t.p+d+r+.6*s));case"aboveBar":return t.p=e.Z(l,a)-d-h.Ku,void 0!==t.Vt&&(t.Vt.p=t.p-d-.6*s,h.Ku+=1.2*s),void(h.Ku+=_+r);case"belowBar":return t.p=e.Z(f,a)+d+h.$u,void 0!==t.Vt&&(t.Vt.p=t.p+d+r+.6*s,h.$u+=1.2*s),void(h.$u+=_+r)}i.position}var Ni=function(){function t(t,i){this.Ut=!0,this.Xu=!0,this.Zu=!0,this.Ju=null,this.lt=new pi,this.Gu=t,this.ri=i,this.it={m:[],M:null}}return t.prototype.V=function(t){this.Ut=!0,this.Zu=!0,"data"===t&&(this.Xu=!0)},t.prototype.W=function(t,i,n,h){if(!this.Gu.Y())return null;this.Ut&&this.je();var s=this.ri.I().layout;return this.lt.Eu(s.fontSize,s.fontFamily),this.lt._(this.it),this.lt},t.prototype.Qu=function(){if(this.Zu){if(this.Gu.ta().length>0){var t=this.ri.q().Fr(),i=Mi(t),n=1.5*wi(t)+2*i;this.Ju={above:n,below:n}}else this.Ju=null;this.Zu=!1}return this.Ju},t.prototype.je=function(){var t=this.Gu.J(),i=this.ri.q(),n=this.Gu.ta();this.Xu&&(this.it.m=n.map((function(t){return{P:t.time,g:0,p:0,Ke:0,Yu:t.shape,ut:t.color,Uu:t.Uu,qu:t.id,Vt:void 0}})),this.Xu=!1);var h=this.ri.I().layout;this.it.M=null;var s=i.br();if(null!==s){var r=this.Gu.K();if(null!==r&&0!==this.it.m.length){var e=NaN,u=Mi(i.Fr()),a={Ku:u,$u:u};this.it.M=Kt(this.it.m,s,!0);for(var o=this.it.M.from;o<this.it.M.to;o++){var l=n[o];l.time!==e&&(a.Ku=u,a.$u=u,e=l.time);var f=this.it.m[o];f.g=i.tt(l.time),void 0!==l.text&&l.text.length>0&&(f.Vt={Hu:l.text,p:0,wt:0,Mt:0});var c=this.Gu.ia(l.time);null!==c&&xi(f,l,c,a,h.fontSize,u,t,i,r.G)}this.Ut=!1}}},t}(),Si=function(t){function i(i){return t.call(this,i)||this}return r(i,t),i.prototype.Iu=function(t,i){var n=this.Pu;n.Y=!1;var h=this.Ie.I();if(h.priceLineVisible&&this.Ie.Y()){var s=this.Ie.na(0===h.priceLineSource);s.ha||(n.Y=!0,n.p=s.Ft,n.ut=this.Ie.sa(s.ut),n.wt=i,n.Mt=t,n.et=h.priceLineWidth,n.at=h.priceLineStyle)}},i}(ci),Ci=function(t){function i(i){var n=t.call(this)||this;return n.ft=i,n}return r(i,t),i.prototype.Gt=function(t,i,n){if(t.Y=!1,i.Y=!1,this.ft.Y()){var h=this.ft.I(),s=h.lastValueVisible,r=""!==this.ft.ra(),e=0===h.seriesLastValueMode,u=this.ft.na(!1);if(!u.ha){s&&(t.Vt=this.ea(u,s,e),t.Y=0!==t.Vt.length),(r||e)&&(i.Vt=this.ua(u,s,r,e),i.Y=i.Vt.length>0);var a=this.ft.sa(u.ut),o=A(a);n.yt=o.yt,n.ut=o.kt,n.Ft=u.Ft,i.X=this.ft.ct().I().layout.backgroundColor,t.X=a}}},i.prototype.ua=function(t,i,n,h){var s="",r=this.ft.ra();return n&&0!==r.length&&(s+=r+" "),i&&h&&(s+=this.ft.J().fh()?t.aa:t.oa),s.trim()},i.prototype.ea=function(t,i,n){return i?n?this.ft.J().fh()?t.oa:t.aa:t.Vt:""},i}(I),Di=function(){function t(t,i){this.Pn=t,this.la=i||null}return t.prototype.xh=function(){return this.Pn},t.prototype.es=function(){return this.la},t.prototype.bn=function(){return null===this.Pn?null:{priceRange:this.Pn.bn(),margins:this.la||void 0}},t.mn=function(i){return null===i?null:new t(J.mn(i.priceRange),i.margins)},t}(),Ti=function(t){function i(i,n){var h=t.call(this,i)||this;return h.fa=n,h}return r(i,t),i.prototype.Iu=function(t,i){var n=this.Pu;if(n.Y=!1,this.Ie.Y()){var h=this.fa.ca();if(null!==h){var s=this.fa.I();n.Y=!0,n.p=h,n.ut=s.color,n.wt=i,n.Mt=t,n.et=s.lineWidth,n.at=s.lineStyle}}},i}(ci),Ei=function(t){function i(i,n){var h=t.call(this)||this;return h.Gu=i,h.fa=n,h}return r(i,t),i.prototype.Gt=function(t,i,n){t.Y=!1,i.Y=!1;var h=this.fa.I(),s=h.axisLabelVisible,r=""!==h.title;if(s&&this.Gu.Y()){var e=this.fa.ca();if(null!==e){r&&(i.Vt=h.title,i.Y=!0),i.X=this.Gu.ct().I().layout.backgroundColor,t.Vt=this.Gu.J().Xh(h.price),t.Y=!0;var u=A(h.color);n.yt=u.yt,n.ut=u.kt,n.Ft=e}}},i}(I),Li=function(){function t(t,i){this.Gu=t,this.Si=i,this.va=new Ti(t,this),this.Lu=new Ei(t,this),this._a=new li(this.Lu,t,t.ct())}return t.prototype.rh=function(t){c(this.Si,t),this.V(),this.Gu.ct().Pr()},t.prototype.I=function(){return this.Si},t.prototype._i=function(){return[this.va,this._a]},t.prototype.da=function(){return this.Lu},t.prototype.V=function(){this.va.V(),this.Lu.V()},t.prototype.ca=function(){var t=this.Gu,i=t.J();if(t.ct().q().ii()||i.ii())return null;var n=t.K();return null===n?null:i.Z(this.Si.price,n.G)},t}(),Bi=function(t){function i(i){var n=t.call(this)||this;return n.ri=i,n}return r(i,t),i.prototype.ct=function(){return this.ri},i}(q),Ai={uu:"",Mu:"",wu:""},Vi=function(){function t(t){this.Gu=t}return t.prototype.au=function(t,i){var n=this.Gu.wa(),h=this.Gu.I();switch(n){case"Line":return this.Ma(h);case"Area":return this.ba(h);case"Bar":return this.ma(h,t,i);case"Candlestick":return this.ga(h,t,i);case"Histogram":return this.pa(h,t,i)}throw new Error("Unknown chart style")},t.prototype.ma=function(t,i,n){var h=e({},Ai),s=t.upColor,r=t.downColor,u=s,a=r,o=l(this.ya(i,n)),c=f(o.G[0])<=f(o.G[3]);return h.uu=c?s:r,h.Mu=c?u:a,h},t.prototype.ga=function(t,i,n){var h=e({},Ai),s=t.upColor,r=t.downColor,u=t.borderUpColor,a=t.borderDownColor,o=t.wickUpColor,c=t.wickDownColor,v=l(this.ya(i,n)),_=f(v.G[0])<=f(v.G[3]);return h.uu=_?s:r,h.Mu=_?u:a,h.wu=_?o:c,h},t.prototype.ba=function(t){return e(e({},Ai),{uu:t.lineColor})},t.prototype.Ma=function(t){return e(e({},Ai),{uu:t.color})},t.prototype.pa=function(t,i,n){var h=e({},Ai),s=l(this.ya(i,n));return h.uu=void 0!==s.ut?s.ut:t.color,h},t.prototype.ya=function(t,i){return void 0!==i?i.G:this.Gu.Yi().ka(t)},t}(),Oi=30,zi=function(){function t(){this.xa=[],this.Na=new Map,this.Sa=new Map}return t.prototype.Ca=function(){this.xa=[],this.Na.clear(),this.Sa.clear()},t.prototype.Da=function(){return this.Ke()>0?this.xa[this.xa.length-1]:null},t.prototype.Ta=function(){return this.Ke()>0?this.Ea(0):null},t.prototype.Hi=function(){return this.Ke()>0?this.Ea(this.xa.length-1):null},t.prototype.Ke=function(){return this.xa.length},t.prototype.ii=function(){return 0===this.Ke()},t.prototype.Vs=function(t){return null!==this.La(t,0)},t.prototype.ka=function(t){return this.Ba(t)},t.prototype.Ba=function(t,i){void 0===i&&(i=0);var n=this.La(t,i);return null===n?null:e(e({},this.Aa(n)),{Fs:this.Ea(n)})},t.prototype.Je=function(){return this.xa},t.prototype.Va=function(t,i,n){if(this.ii())return null;for(var h=null,s=0,r=n;s<r.length;s++){var e=r[s];h=Pi(h,this.Oa(t,i,e))}return h},t.prototype.dn=function(t){0!==t.length&&(this.ii()||t[t.length-1].Fs<this.xa[0].Fs?this.za(t):t[0].Fs>this.xa[this.xa.length-1].Fs?this.Pa(t):1!==t.length||t[0].Fs!==this.xa[this.xa.length-1].Fs?this.Fa(t):this.Ia(t[0]))},t.prototype.Ea=function(t){return this.xa[t].Fs},t.prototype.Aa=function(t){return this.xa[t]},t.prototype.La=function(t,i){var n=this.Wa(t);if(null===n&&0!==i)switch(i){case-1:return this.Ra(t);case 1:return this.ja(t);default:throw new TypeError("Unknown search mode")}return n},t.prototype.Ra=function(t){var i=this.Ua(t);return i>0&&(i-=1),i!==this.xa.length&&this.Ea(i)<t?i:null},t.prototype.ja=function(t){var i=this.qa(t);return i!==this.xa.length&&t<this.Ea(i)?i:null},t.prototype.Wa=function(t){var i=this.Ua(t);return i===this.xa.length||t<this.xa[i].Fs?null:i},t.prototype.Ua=function(t){return Ut(this.xa,t,(function(t,i){return t.Fs<i}))},t.prototype.qa=function(t){return qt(this.xa,t,(function(t,i){return i.Fs>t}))},t.prototype.Ha=function(t,i,n){for(var h=null,s=t;s<i;s++){var r=this.xa[s].G[n];Number.isNaN(r)||(null===h?h={Ya:r,Ka:r}:(r<h.Ya&&(h.Ya=r),r>h.Ka&&(h.Ka=r)))}return h},t.prototype.$a=function(t){var i=Math.floor(t.Fs/Oi);this.Na.forEach((function(t){return t.delete(i)}))},t.prototype.za=function(t){a(0!==t.length,"plotRows should not be empty"),this.Sa.clear(),this.Na.clear(),this.xa=t.concat(this.xa)},t.prototype.Pa=function(t){a(0!==t.length,"plotRows should not be empty"),this.Sa.clear(),this.Na.clear(),this.xa=this.xa.concat(t)},t.prototype.Ia=function(t){a(!this.ii(),"plot list should not be empty"),a(this.xa[this.xa.length-1].Fs===t.Fs,"last row index should match new row index"),this.$a(t),this.Sa.delete(t.Fs),this.xa[this.xa.length-1]=t},t.prototype.Fa=function(t){a(0!==t.length,"plot rows should not be empty"),this.Sa.clear(),this.Na.clear(),this.xa=function(t,i){var n=function(t,i){var n=t.length,h=i.length,s=n+h,r=0,e=0;for(;r<n&&e<h;)t[r].Fs<i[e].Fs?r++:t[r].Fs>i[e].Fs?e++:(r++,e++,s--);return s}(t,i),h=new Array(n),s=0,r=0,e=t.length,u=i.length,a=0;for(;s<e&&r<u;)t[s].Fs<i[r].Fs?(h[a]=t[s],s++):t[s].Fs>i[r].Fs?(h[a]=i[r],r++):(h[a]=i[r],s++,r++),a++;for(;s<e;)h[a]=t[s],s++,a++;for(;r<u;)h[a]=i[r],r++,a++;return h}(this.xa,t)},t.prototype.Oa=function(t,i,n){if(this.ii())return null;var h=null,s=l(this.Ta()),r=l(this.Hi()),e=Math.max(t,s),u=Math.min(i,r),a=Math.ceil(e/Oi)*Oi,o=Math.max(a,Math.floor(u/Oi)*Oi),f=this.Ua(e),c=this.qa(Math.min(u,a,i));h=Pi(h,this.Ha(f,c,n));var v=this.Na.get(n);void 0===v&&(v=new Map,this.Na.set(n,v));for(var _=Math.max(a+1,e);_<o;_+=Oi){var d=Math.floor(_/Oi),w=v.get(d);if(void 0===w){var M=this.Ua(d*Oi),b=this.qa((d+1)*Oi-1);w=this.Ha(M,b,n),v.set(d,w)}h=Pi(h,w)}f=this.Ua(o),c=this.qa(u);return h=Pi(h,this.Ha(f,c,n))},t}();function Pi(t,i){return null===t?i:null===i?t:{Ya:Math.min(t.Ya,i.Ya),Ka:Math.max(t.Ka,i.Ka)}}var Fi=function(t){function i(i,n,h){var s=t.call(this,i)||this;s.it=new zi,s.va=new Si(s),s.Xa=[],s.Za=new vi(s),s.Ja=null,s.Ga=[],s.Qa=[],s.Si=n,s.io=h;var r=new Ci(s);return s.gi=[r],s._a=new li(r,s,i),s.no(),s.ho(),s}return r(i,t),i.prototype.un=function(){},i.prototype.sa=function(t){return this.Si.priceLineColor||t},i.prototype.na=function(t,i){var n={ha:!0},h=this.J();if(this.ct().q().ii()||h.ii()||this.it.ii())return n;var s,r,e=this.ct().q().br(),u=this.K();if(null===e||null===u)return n;if(t){var a=this.it.Da();if(null===a)return n;s=a,r=a.Fs}else{var o=this.it.Ba(e.rs(),-1);if(null===o)return n;if(null===(s=this.it.ka(o.Fs)))return n;r=o.Fs}var l=s.G[3],f=this.Ze().au(r,{G:s}),c=h.Z(l,u.G);return{ha:!1,F:i?l:void 0,Vt:h.ni(l,u.G),aa:h.Xh(l),oa:h.Jh(l,u.G),ut:f.uu,Ft:c,Fs:r}},i.prototype.Ze=function(){return null!==this.Ja||(this.Ja=new Vi(this)),this.Ja},i.prototype.I=function(){return this.Si},i.prototype.rh=function(t){var i=t.priceScaleId;void 0!==i&&i!==this.Si.priceScaleId&&this.ct().so(this,i),c(this.Si,t),null!==this.ai&&void 0!==t.scaleMargins&&this.ai.rh({scaleMargins:t.scaleMargins}),void 0!==t.priceFormat&&this.no(),this.ct().ro(this),this.ct().eo(),this.Bi.V("options")},i.prototype.uo=function(){this.it.Ca(),this.ho()},i.prototype.ao=function(t,i){i&&this.it.Ca(),this.it.dn(t),this.oo(),this.Bi.V("data"),this.Ci.V("data");var n=this.ct().Au(this);this.ct().lo(n),this.ct().ro(this),this.ct().eo(),this.ct().Pr()},i.prototype.fo=function(t){this.Ga=t.map((function(t){return e({},t)})),this.oo();var i=this.ct().Au(this);this.Ci.V("data"),this.ct().lo(i),this.ct().ro(this),this.ct().eo(),this.ct().Pr()},i.prototype.ta=function(){return this.Qa},i.prototype.co=function(t){var i=new Li(this,t);return this.Xa.push(i),this.ct().ro(this),i},i.prototype.vo=function(t){var i=this.Xa.indexOf(t);-1!==i&&this.Xa.splice(i,1),this.ct().ro(this)},i.prototype.wa=function(){return this.io},i.prototype.K=function(){var t=this._o();return null===t?null:{G:t.G[3],Ih:t.P}},i.prototype._o=function(){var t=this.ct().q().br();if(null===t)return null;var i=t.ss();return this.it.Ba(i,1)},i.prototype.Yi=function(){return this.it},i.prototype.ia=function(t){var i=this.it.ka(t);return null===i?null:"Bar"===this.io||"Candlestick"===this.io?{open:i.G[0],high:i.G[1],low:i.G[2],close:i.G[3]}:i.G[3]},i.prototype._i=function(){var t=[];this.do()||t.push(this.Za);for(var i=0,n=this.Xa;i<n.length;i++){var h=n[i];t.push.apply(t,h._i())}return t.push(this.Bi,this.va,this._a,this.Ci),t},i.prototype.vi=function(t,i){if(i!==this.ai&&!this.do())return[];for(var n=u([],this.gi),h=0,s=this.Xa;h<s.length;h++){var r=s[h];n.push(r.da())}return n},i.prototype.hs=function(t,i){var n=this;if(void 0!==this.Si.autoscaleInfoProvider){var h=this.Si.autoscaleInfoProvider((function(){var h=n.wo(t,i);return null===h?null:h.bn()}));return Di.mn(h)}return this.wo(t,i)},i.prototype.ts=function(){return this.Si.priceFormat.minMove},i.prototype.Kh=function(){return this.Jn},i.prototype.ji=function(){this.Bi.V(),this.Ci.V();for(var t=0,i=this.gi;t<i.length;t++){i[t].V()}for(var n=0,h=this.Xa;n<h.length;n++){h[n].V()}this.va.V(),this.Za.V()},i.prototype.J=function(){return l(this.ai)},i.prototype.H=function(t){if(!(("Line"===this.io||"Area"===this.io)&&this.Si.crosshairMarkerVisible))return null;var i=this.it.ka(t);return null===i?null:{F:i.G[3],N:this.Mo(),X:this.bo(),$:this.mo(t)}},i.prototype.ra=function(){return this.Si.title},i.prototype.Y=function(){return this.Si.visible},i.prototype.do=function(){return!Pt(this.J().sh())},i.prototype.wo=function(t,i){if(!_(t)||!_(i)||this.it.ii())return null;var n="Line"===this.io||"Area"===this.io||"Histogram"===this.io?[3]:[2,1],h=this.it.Va(t,i,n),s=null!==h?new J(h.Ya,h.Ka):null;if("Histogram"===this.wa()){var r=this.Si.base,e=new J(r,r);s=null!==s?s.dn(e):e}return new Di(s,this.Ci.Qu())},i.prototype.Mo=function(){switch(this.io){case"Line":case"Area":return this.Si.crosshairMarkerRadius}return 0},i.prototype.bo=function(){switch(this.io){case"Line":case"Area":var t=this.Si.crosshairMarkerBorderColor;if(0!==t.length)return t}return this.ct().I().layout.backgroundColor},i.prototype.mo=function(t){switch(this.io){case"Line":case"Area":var i=this.Si.crosshairMarkerBackgroundColor;if(0!==i.length)return i}return this.Ze().au(t).uu},i.prototype.no=function(){switch(this.Si.priceFormat.type){case"custom":this.Jn={format:this.Si.priceFormat.formatter};break;case"volume":this.Jn=new It(this.Si.priceFormat.precision);break;case"percent":this.Jn=new X(this.Si.priceFormat.precision);break;default:var t=Math.pow(10,this.Si.priceFormat.precision);this.Jn=new $(t,this.Si.priceFormat.minMove*t)}null!==this.ai&&this.ai.eh()},i.prototype.oo=function(){var t=this,i=this.ct().q();if(i.ii()||0===this.it.Ke())this.Qa=[];else{var n=l(this.it.Ta());this.Qa=this.Ga.map((function(h,s){var r=l(i.Mr(h.time,!0)),e=r<n?1:-1;return{time:l(t.it.Ba(r,e)).Fs,position:h.position,shape:h.shape,color:h.color,id:h.id,Uu:s,text:h.text,size:h.size}}))}},i.prototype.ho=function(){switch(this.Ci=new Ni(this,this.ct()),this.io){case"Bar":this.Bi=new Qt(this,this.ct());break;case"Candlestick":this.Bi=new ii(this,this.ct());break;case"Line":this.Bi=new ei(this,this.ct());break;case"Area":this.Bi=new Zt(this,this.ct());break;case"Histogram":this.Bi=new ri(this,this.ct());break;default:throw Error("Unknown chart style assigned: "+this.io)}},i}(Bi),Ii=function(){function t(t){this.Si=t}return t.prototype.po=function(t,i,n){var h=t;if(0===this.Si.mode)return h;var s=n.Ti(),r=s.K();if(null===r)return h;var e=s.Z(t,r),u=n.j().filter((function(t){return t instanceof Fi})).reduce((function(t,h){if(n.Vu(h)||!h.Y())return t;var s=h.J(),r=h.Yi();if(s.ii()||!r.Vs(i))return t;var e=r.ka(i);if(null===e)return t;var u=f(h.K());return t.concat([s.Z(e.G[3],u.G)])}),[]);if(0===u.length)return h;u.sort((function(t,i){return Math.abs(t-e)-Math.abs(i-e)}));var a=u[0];return h=s.Ei(a,r)},t}(),Wi=function(){function t(){this.it=null}return t.prototype._=function(t){this.it=t},t.prototype.h=function(t,i,h,s){var r=this;if(null!==this.it){var e=Math.max(1,Math.floor(i));t.lineWidth=e;var u=Math.ceil(this.it.rt*i),a=Math.ceil(this.it.st*i);!function(t,i){t.save(),t.lineWidth%2&&t.translate(.5,.5),i(),t.restore()}(t,(function(){var h=l(r.it);if(h.yo){t.strokeStyle=h.ko,n(t,h.xo),t.beginPath();for(var s=0,o=h.No;s<o.length;s++){var f=o[s],c=Math.round(f.En*i);t.moveTo(c,-e),t.lineTo(c,u+e)}t.stroke()}if(h.So){t.strokeStyle=h.Co,n(t,h.Do),t.beginPath();for(var v=0,_=h.To;v<_.length;v++){var d=_[v],w=Math.round(d.En*i);t.moveTo(-e,w),t.lineTo(a+e,w)}t.stroke()}}))}},t}(),Ri=function(){function t(t){this.lt=new Wi,this.Ut=!0,this.wi=t}return t.prototype.V=function(){this.Ut=!0},t.prototype.W=function(t,i){if(this.Ut){var n=this.wi.ct().I().grid,h={rt:t,st:i,So:n.horzLines.visible,yo:n.vertLines.visible,Co:n.horzLines.color,ko:n.vertLines.color,Do:n.horzLines.style,xo:n.vertLines.style,To:this.wi.Ti().Vn(),No:this.wi.ct().q().Vn()||[]};this.lt._(h),this.Ut=!1}return this.lt},t}(),ji=function(){function t(t){this.Bi=new Ri(t)}return t.prototype.Eo=function(){return this.Bi},t}(),Ui=function(){function t(t,i){this.Yn=[],this.Lo=new Map,this.On=0,this.Ks=0,this.Bo=1e3,this.Kn=null,this.Ao=new Z,this.Vo=t,this.ri=i,this.Oo=new ji(this);var n=i.I();this.zo=this.Po("left",n.leftPriceScale),this.Fo=this.Po("right",n.rightPriceScale),this.zo.mh().Gi(this.Io.bind(this,this.zo),this),this.Fo.mh().Gi(this.Io.bind(this,this.zo),this),this.Wo(n)}return t.prototype.Wo=function(t){if(t.leftPriceScale&&this.zo.rh(t.leftPriceScale),t.rightPriceScale&&this.Fo.rh(t.rightPriceScale),t.localization&&(this.zo.eh(),this.Fo.eh()),t.overlayPriceScales)for(var i=0,n=Array.from(this.Lo.values());i<n.length;i++){var h=l(n[i][0].J());h.rh(t.overlayPriceScales),t.localization&&h.eh()}},t.prototype.Ro=function(t){switch(t){case"left":return this.zo;case"right":return this.Fo}return this.Lo.has(t)?o(this.Lo.get(t))[0].J():null},t.prototype.un=function(){this.ct().jo().sn(this),this.zo.mh().sn(this),this.Fo.mh().sn(this),this.Yn.forEach((function(t){t.un&&t.un()})),this.Ao.rn()},t.prototype.Uo=function(){return this.Bo},t.prototype.qo=function(t){this.Bo=t},t.prototype.ct=function(){return this.ri},t.prototype.wt=function(){return this.Ks},t.prototype.Mt=function(){return this.On},t.prototype.Dr=function(t){this.Ks=t,this.Ho()},t.prototype.gh=function(t){var i=this;this.On=t,this.zo.gh(t),this.Fo.gh(t),this.Yn.forEach((function(n){if(i.Vu(n)){var h=n.J();null!==h&&h.gh(t)}})),this.Ho()},t.prototype.j=function(){return this.Yn},t.prototype.Vu=function(t){var i=t.J();return null===i||this.zo!==i&&this.Fo!==i},t.prototype.zh=function(t,i,n){var h=void 0!==n?n:this.Ko().Yo+1;this.$o(t,i,h)},t.prototype.Fh=function(t){var i=this.Yn.indexOf(t);a(-1!==i,"removeDataSource: invalid data source"),this.Yn.splice(i,1);var n=l(t.J()).sh();if(this.Lo.has(n)){var h=o(this.Lo.get(n)),s=h.indexOf(t);-1!==s&&(h.splice(s,1),0===h.length&&this.Lo.delete(n))}var r=t.J();r&&r.j().indexOf(t)>=0&&r.Fh(t),null!==r&&(r.Ph(),this.Xo(r)),this.Kn=null},t.prototype.Ou=function(t){return t===this.zo?"left":t===this.Fo?"right":"overlay"},t.prototype.Zo=function(){return this.zo},t.prototype.Jo=function(){return this.Fo},t.prototype.Go=function(t,i){t.Rh(i)},t.prototype.Qo=function(t,i){t.jh(i),this.Ho()},t.prototype.tl=function(t){t.Uh()},t.prototype.il=function(t,i){t.qh(i)},t.prototype.nl=function(t,i){t.Hh(i),this.Ho()},t.prototype.hl=function(t){t.Yh()},t.prototype.Ho=function(){this.Yn.forEach((function(t){t.ji()}))},t.prototype.Ti=function(){var t=null;return this.ri.I().rightPriceScale.visible&&0!==this.Fo.j().length?t=this.Fo:this.ri.I().leftPriceScale.visible&&0!==this.zo.j().length?t=this.zo:0!==this.Yn.length&&(t=this.Yn[0].J()),null===t&&(t=this.Fo),t},t.prototype.Xo=function(t){null!==t&&t.lh()&&this.sl(t)},t.prototype.rl=function(t){var i=this.Vo.br();t.uh({dh:!0}),null!==i&&t.Qh(i),this.Ho()},t.prototype.el=function(){this.sl(this.zo),this.sl(this.Fo)},t.prototype.ul=function(){var t=this;this.Xo(this.zo),this.Xo(this.Fo),this.Yn.forEach((function(i){t.Vu(i)&&t.Xo(i.J())})),this.Ho(),this.ri.Pr()},t.prototype.Oh=function(){return null===this.Kn&&(this.Kn=vt(this.Yn)),this.Kn},t.prototype.al=function(){return this.Ao},t.prototype.ol=function(){return this.Oo},t.prototype.sl=function(t){var i=t.Gh();if(i&&i.length>0&&!this.Vo.ii()){var n=this.Vo.br();null!==n&&t.Qh(n)}t.ji()},t.prototype.Ko=function(){var t=this.Oh();if(0===t.length)return{ll:0,Yo:0};for(var i=0,n=0,h=0;h<t.length;h++){var s=t[h].li();null!==s&&(s<i&&(i=s),s>n&&(n=s))}return{ll:i,Yo:n}},t.prototype.$o=function(t,i,n){var h=this.Ro(i);if(null===h&&(h=this.Po(i,this.ri.I().overlayPriceScales)),this.Yn.push(t),!Pt(i)){var s=this.Lo.get(i)||[];s.push(t),this.Lo.set(i,s)}h.zh(t),t.ci(h),t.fi(n),this.Xo(h),this.Kn=null},t.prototype.Io=function(t,i,n){i.ah!==n.ah&&this.sl(t)},t.prototype.Po=function(t,i){var n=e({visible:!0,autoScale:!0},M(i)),h=new Mt(t,n,this.ri.I().layout,this.ri.I().localization);return h.gh(this.Mt()),h},t}(),qi=function(t){function i(i){var n=t.call(this)||this;return n.fl=new Map,n.it=i,n}return r(i,t),i.prototype.u=function(t){},i.prototype.l=function(t){if(this.it.Y){t.save();for(var i=0,n=0,h=this.it.cl;n<h.length;n++){if(0!==(a=h[n]).Vt.length){t.font=a.Nt;var s=this.vl(t,a.Vt);s>this.it.wt?a.Ur=this.it.wt/s:a.Ur=1,i+=a._l*a.Ur}}var r=0;switch(this.it.dl){case"top":r=0;break;case"center":r=Math.max((this.it.Mt-i)/2,0);break;case"bottom":r=Math.max(this.it.Mt-i,0)}t.fillStyle=this.it.ut;for(var e=0,u=this.it.cl;e<u.length;e++){var a=u[e];t.save();var o=0;switch(this.it.wl){case"left":t.textAlign="left",o=a._l/2;break;case"center":t.textAlign="center",o=this.it.wt/2;break;case"right":t.textAlign="right",o=this.it.wt-1-a._l/2}t.translate(o,r),t.textBaseline="top",t.font=a.Nt,t.scale(a.Ur,a.Ur),t.fillText(a.Vt,0,a.Ml),t.restore(),r+=a._l*a.Ur}t.restore()}},i.prototype.vl=function(t,i){var n=this.bl(t.font),h=n.get(i);return void 0===h&&(h=t.measureText(i).width,n.set(i,h)),h},i.prototype.bl=function(t){var i=this.fl.get(t);return void 0===i&&(i=new Map,this.fl.set(t,i)),i},i}(p),Hi=function(){function t(t){this.Ut=!0,this.ot={Y:!1,ut:"",Mt:0,wt:0,cl:[],dl:"center",wl:"center"},this.lt=new qi(this.ot),this.ft=t}return t.prototype.V=function(){this.Ut=!0},t.prototype.W=function(t,i){return this.Ut&&(this.R(t,i),this.Ut=!1),this.lt},t.prototype.R=function(t,i){var n=this.ft.I(),h=this.ot;h.Y=n.visible,h.Y&&(h.ut=n.color,h.wt=i,h.Mt=t,h.wl=n.horzAlign,h.dl=n.vertAlign,h.cl=[{Vt:n.text,Nt:Ot(n.fontSize,n.fontFamily,n.fontStyle),_l:1.2*n.fontSize,Ml:0,Ur:0}])},t}(),Yi=function(t){function i(i,n){var h=t.call(this)||this;return h.Si=n,h.Bi=new Hi(h),h}return r(i,t),i.prototype._i=function(){return[this.Bi]},i.prototype.I=function(){return this.Si},i.prototype.ji=function(){this.Bi.V()},i}(q),Ki=function(){function t(t,i){this.ml=[],this.gl=[],this.Ks=0,this.pl=null,this.yl=null,this.kl=new Z,this.xl=new Z,this.Nl=t,this.Si=i,this.Sl=new zt(this),this.Vo=new Lt(this,i.timeScale,this.Si.localization),this.A=new H(this,i.crosshair),this.Cl=new Ii(i.crosshair),this.Dl=new Yi(this,i.watermark),this.Tl(),this.ml[0].qo(2e3)}return t.prototype.El=function(){this.Ll(new Ft(3))},t.prototype.Pr=function(){this.Ll(new Ft(2))},t.prototype.ro=function(t){var i=this.Bl(t);this.Ll(i)},t.prototype.Al=function(){return this.yl},t.prototype.Vl=function(t){var i=this.yl;this.yl=t,null!==i&&this.ro(i.Ol),null!==t&&this.ro(t.Ol)},t.prototype.I=function(){return this.Si},t.prototype.rh=function(t){c(this.Si,t),this.ml.forEach((function(i){return i.Wo(t)})),void 0!==t.timeScale&&this.Vo.rh(t.timeScale),void 0!==t.localization&&this.Vo.lr(t.localization),(t.leftPriceScale||t.rightPriceScale)&&this.kl.rn(),this.El()},t.prototype.zl=function(t,i){var n=this.Pl(t);null!==n&&(n.J.rh(i),this.kl.rn())},t.prototype.Pl=function(t){for(var i=0,n=this.ml;i<n.length;i++){var h=n[i],s=h.Ro(t);if(null!==s)return{vt:h,J:s}}return null},t.prototype.q=function(){return this.Vo},t.prototype.Fl=function(){return this.ml},t.prototype.Il=function(){return this.Dl},t.prototype.Wl=function(){return this.A},t.prototype.Rl=function(){return this.xl},t.prototype.jl=function(t,i){t.gh(i),this.zr()},t.prototype.Dr=function(t){this.Ks=t,this.Vo.Dr(this.Ks),this.ml.forEach((function(i){return i.Dr(t)})),this.zr()},t.prototype.Tl=function(t){var i=new Ui(this.Vo,this);void 0!==t?this.ml.splice(t,0,i):this.ml.push(i);var n=void 0===t?this.ml.length-1:t,h=new Ft(3);return h.Me(n,{be:0,dh:!0}),this.Ll(h),i},t.prototype.Go=function(t,i,n){t.Go(i,n)},t.prototype.Qo=function(t,i,n){t.Qo(i,n),this.eo(),this.Ll(this.Ul(t,2))},t.prototype.tl=function(t,i){t.tl(i),this.Ll(this.Ul(t,2))},t.prototype.il=function(t,i,n){i.lh()||t.il(i,n)},t.prototype.nl=function(t,i,n){i.lh()||(t.nl(i,n),this.eo(),this.Ll(this.Ul(t,2)))},t.prototype.hl=function(t,i){i.lh()||(t.hl(i),this.Ll(this.Ul(t,2)))},t.prototype.rl=function(t,i){t.rl(i),this.Ll(this.Ul(t,2))},t.prototype.ql=function(t){this.Vo.Rh(t)},t.prototype.Hl=function(t,i){var n=this.q();if(!n.ii()&&0!==i){var h=n.wt();t=Math.max(1,Math.min(t,h)),n.Ur(t,i),this.zr()}},t.prototype.Yl=function(t){this.Kl(0),this.$l(t),this.Xl()},t.prototype.Zl=function(t){this.Vo.jh(t),this.zr()},t.prototype.Jl=function(){this.Vo.Uh(),this.Pr()},t.prototype.Kl=function(t){this.pl=t,this.Vo.qh(t)},t.prototype.$l=function(t){var i=!1;return null!==this.pl&&Math.abs(t-this.pl)>20&&(this.pl=null,i=!0),this.Vo.Hh(t),this.zr(),i},t.prototype.Xl=function(){this.Vo.Yh(),this.Pr(),this.pl=null},t.prototype.O=function(){return this.gl},t.prototype.Gl=function(t,i,n){this.A.Ai(t,i);var h=NaN,s=this.Vo.Vr(t),r=this.Vo.br();null!==r&&(s=Math.min(Math.max(r.ss(),s),r.rs()));var e=n.Ti(),u=e.K();null!==u&&(h=e.Ei(i,u)),h=this.Cl.po(h,s,n),this.A.Pi(s,h,n),this.Ql(),this.xl.rn(this.A.U(),{x:t,y:i})},t.prototype.tf=function(){this.Wl().Ii(),this.Ql(),this.xl.rn(null,null)},t.prototype.eo=function(){var t=this.A.vt();if(null!==t){var i=this.A.Oi(),n=this.A.zi();this.Gl(i,n,t)}this.A.ji()},t.prototype.if=function(t,i){var n=this.Vo.ei(0);void 0!==i&&this.Vo.V(i);var h=this.Vo.ei(0),s=this.Vo.Br(),r=this.Vo.br();if(null!==r&&null!==n&&null!==h){var e=r.Vs(s),u=n.Ds>h.Ds,a=null!==t&&t>s&&!u,o=e&&this.Vo.I().shiftVisibleRangeOnNewBar;if(a&&!o&&null!==t){var l=t-s;this.Vo.wr(this.Vo.Ir()-l)}}this.Vo.jr(t)},t.prototype.lo=function(t){null!==t&&t.ul()},t.prototype.Au=function(t){var i=this.ml.find((function(i){return i.Oh().includes(t)}));return void 0===i?null:i},t.prototype.zr=function(){this.Dl.ji(),this.ml.forEach((function(t){return t.ul()})),this.eo()},t.prototype.un=function(){this.ml.forEach((function(t){return t.un()})),this.ml.length=0,this.Si.localization.priceFormatter=void 0,this.Si.localization.timeFormatter=void 0},t.prototype.nf=function(){return this.Sl},t.prototype.zu=function(){return this.Sl.I()},t.prototype.jo=function(){return this.kl},t.prototype.hf=function(t,i){var n=i.pane||0;this.ml.length-1<n&&this.Tl(n);var h=this.ml[n],s=this.sf(i,t,h);return this.gl.push(s),1===this.gl.length?this.El():this.Pr(),s},t.prototype.rf=function(t){var i=this.Au(t),n=this.gl.indexOf(t);a(-1!==n,"Series not found"),this.gl.splice(n,1),l(i).Fh(t),t.un&&t.un()},t.prototype.so=function(t,i){var n=l(this.Au(t));n.Fh(t);var h=this.Pl(i);if(null===h){var s=t.li();n.zh(t,i,s)}else{s=h.vt===n?t.li():void 0;h.vt.zh(t,i,s)}},t.prototype.Gr=function(){var t=new Ft(2);t.pe(),this.Ll(t)},t.prototype.ef=function(t){var i=new Ft(2);i.ke(t),this.Ll(i)},t.prototype.xe=function(){var t=new Ft(2);t.xe(),this.Ll(t)},t.prototype.dr=function(t){var i=new Ft(2);i.dr(t),this.Ll(i)},t.prototype.wr=function(t){var i=new Ft(2);i.wr(t),this.Ll(i)},t.prototype.uf=function(){return this.Si.rightPriceScale.visible?"right":"left"},t.prototype.Ul=function(t,i){var n=new Ft(i);if(null!==t){var h=this.ml.indexOf(t);n.Me(h,{be:i})}return n},t.prototype.Bl=function(t,i){return void 0===i&&(i=2),this.Ul(this.Au(t),i)},t.prototype.Ll=function(t){this.Nl&&this.Nl(t),this.ml.forEach((function(t){return t.ol().Eo().V()}))},t.prototype.Ql=function(){this.Ll(new Ft(1))},t.prototype.sf=function(t,i,n){var h=new Fi(this,t,i),s=void 0!==t.priceScaleId?t.priceScaleId:this.uf();return n.zh(h,s),Pt(s)||h.rh(t),h},t}(),$i={allowDownsampling:!0};var Xi=function(){function t(t,i){var n=this;this._resolutionMediaQueryList=null,this._resolutionListener=function(t){return n._onResolutionChanged()},this._canvasConfiguredListeners=[],this.canvas=t,this._canvasSize={width:this.canvas.clientWidth,height:this.canvas.clientHeight},this._options=i,this._configureCanvas(),this._installResolutionListener()}return t.prototype.destroy=function(){this._canvasConfiguredListeners.length=0,this._uninstallResolutionListener(),this.canvas=null},Object.defineProperty(t.prototype,"canvasSize",{get:function(){return{width:this._canvasSize.width,height:this._canvasSize.height}},enumerable:!0,configurable:!0}),t.prototype.resizeCanvas=function(t){this._canvasSize={width:t.width,height:t.height},this._configureCanvas()},Object.defineProperty(t.prototype,"pixelRatio",{get:function(){var t=this.canvas.ownerDocument.defaultView;if(null==t)throw new Error("No window is associated with the canvas");return t.devicePixelRatio>1||this._options.allowDownsampling?t.devicePixelRatio:1},enumerable:!0,configurable:!0}),t.prototype.subscribeCanvasConfigured=function(t){this._canvasConfiguredListeners.push(t)},t.prototype.unsubscribeCanvasConfigured=function(t){this._canvasConfiguredListeners=this._canvasConfiguredListeners.filter((function(i){return i!=t}))},t.prototype._configureCanvas=function(){var t=this.pixelRatio;this.canvas.style.width=this._canvasSize.width+"px",this.canvas.style.height=this._canvasSize.height+"px",this.canvas.width=this._canvasSize.width*t,this.canvas.height=this._canvasSize.height*t,this._emitCanvasConfigured()},t.prototype._emitCanvasConfigured=function(){var t=this;this._canvasConfiguredListeners.forEach((function(i){return i.call(t)}))},t.prototype._installResolutionListener=function(){if(null!==this._resolutionMediaQueryList)throw new Error("Resolution listener is already installed");var t=this.canvas.ownerDocument.defaultView;if(null==t)throw new Error("No window is associated with the canvas");var i=t.devicePixelRatio;this._resolutionMediaQueryList=t.matchMedia("all and (resolution: "+i+"dppx)"),this._resolutionMediaQueryList.addListener(this._resolutionListener)},t.prototype._uninstallResolutionListener=function(){null!==this._resolutionMediaQueryList&&(this._resolutionMediaQueryList.removeListener(this._resolutionListener),this._resolutionMediaQueryList=null)},t.prototype._reinstallResolutionListener=function(){this._uninstallResolutionListener(),this._installResolutionListener()},t.prototype._onResolutionChanged=function(){this._configureCanvas(),this._reinstallResolutionListener()},t}(),Zi=function(){function t(t,i){this.st=t,this.rt=i}return t.prototype.ln=function(t){return this.st===t.st&&this.rt===t.rt},t}();function Ji(t){return t.ownerDocument&&t.ownerDocument.defaultView&&t.ownerDocument.defaultView.devicePixelRatio||1}function Gi(t){var i=l(t.getContext("2d"));return i.setTransform(1,0,0,1,0,0),i}function Qi(t,i){var n=t.createElement("canvas"),h=Ji(n);return n.style.width=i.st+"px",n.style.height=i.rt+"px",n.width=i.st*h,n.height=i.rt*h,n}function tn(t,i){var n=l(t.ownerDocument).createElement("canvas");t.appendChild(n);var h=function(t,i){return void 0===i&&(i=$i),new Xi(t,i)}(n);return h.resizeCanvas({width:i.st,height:i.rt}),h}var nn="undefined"!=typeof window;var hn=function(){if(!nn)return!1;var t=!!navigator.maxTouchPoints||!!navigator.msMaxTouchPoints||!!nn&&("ontouchstart"in window||Boolean(window.DocumentTouch&&document instanceof window.DocumentTouch));return"onorientationchange"in window&&t}();var sn=function(){if(!nn)return!1;var t=/Android/i.test(navigator.userAgent),i=/iPhone|iPad|iPod|AppleWebKit.+Mobile/i.test(navigator.userAgent);return t||i}(),rn=function(){function t(t,i,n){this.af=0,this.lf=null,this.ff=null,this.cf=!1,this.vf=null,this._f=!1,this.df=!1,this.wf=null,this.Mf=null,this.bf=null,this.mf=null,this.gf=0,this.pf=!1,this.yf=!1,this.kf=!1,this.xf=t,this.Nf=i,this.Si=n,this.Sf()}return t.prototype.un=function(){null!==this.wf&&(this.wf(),this.wf=null),null!==this.Mf&&(this.Mf(),this.Mf=null),null!==this.bf&&(this.bf(),this.bf=null),this.Cf(),this.Df()},t.prototype.Tf=function(t){var i=this;this.Mf&&this.Mf();var n=this.Ef.bind(this);this.Mf=function(){i.xf.removeEventListener("mousemove",n)},this.xf.addEventListener("mousemove",n),an(t)&&this.Ef(t);var h=this.Lf(t);this.Bf(h,this.Nf.Af)},t.prototype.Df=function(){null!==this.lf&&clearTimeout(this.lf),this.af=0,this.lf=null},t.prototype.Ef=function(t){if(!this.kf||an(t)){var i=this.Lf(t);this.Bf(i,this.Nf.Vf)}},t.prototype.Of=function(t){if((!("button"in t)||0===t.button)&&null===this.mf){var i=an(t);if(!this.yf||!i){this.pf=!0;var n=this.Lf(t),h=f(this.vf),s=Math.abs(h.g-n.zf),r=Math.abs(h.p-n.Pf),e=s+r>5;if(e||!i){if(e&&!this._f&&i){var u=.5*s,a=r>=u&&!this.Si.Ff,o=u>r&&!this.Si.If;a||o||(this.yf=!0)}e&&(this._f=!0,this.df=!0,i&&this.Cf()),this.yf||(this.Bf(n,this.Nf.Wf),i&&on(t))}}}},t.prototype.Rf=function(t){if(!("button"in t)||0===t.button){var i=this.Lf(t);this.Cf(),this.vf=null,this.kf=!1,this.bf&&(this.bf(),this.bf=null),an(t)&&this.jf(t),this.Bf(i,this.Nf.Uf),++this.af,this.lf&&this.af>1?(this.Bf(i,this.Nf.qf),this.Df()):this.df||this.Bf(i,this.Nf.Hf),an(t)&&(on(t),this.jf(t),0===t.touches.length&&(this.cf=!1))}},t.prototype.Cf=function(){null!==this.ff&&(clearTimeout(this.ff),this.ff=null)},t.prototype.Yf=function(t){if(!("button"in t)||0===t.button){var i=this.Lf(t);this.df=!1,this._f=!1,this.yf=!1,an(t)&&this.Tf(t),this.vf={g:i.zf,p:i.Pf},this.bf&&(this.bf(),this.bf=null);var n=this.Of.bind(this),h=this.Rf.bind(this),s=this.xf.ownerDocument.documentElement;this.bf=function(){s.removeEventListener("touchmove",n),s.removeEventListener("touchend",h),s.removeEventListener("mousemove",n),s.removeEventListener("mouseup",h)},s.addEventListener("touchmove",n,{passive:!1}),s.addEventListener("touchend",h,{passive:!1}),this.Cf(),an(t)&&1===t.touches.length?this.ff=setTimeout(this.Kf.bind(this,t),240):(s.addEventListener("mousemove",n),s.addEventListener("mouseup",h)),this.kf=!0,this.Bf(i,this.Nf.$f),this.lf||(this.af=0,this.lf=setTimeout(this.Df.bind(this),500))}},t.prototype.Sf=function(){var t=this;this.xf.addEventListener("mouseenter",this.Tf.bind(this)),this.xf.addEventListener("touchcancel",this.Cf.bind(this));var i=this.xf.ownerDocument,n=function(i){t.Nf.Xf&&(i.composed&&t.xf.contains(i.composedPath()[0])||i.target&&t.xf.contains(i.target)||t.Nf.Xf())};this.wf=function(){i.removeEventListener("mousedown",n),i.removeEventListener("touchstart",n)},i.addEventListener("mousedown",n),i.addEventListener("touchstart",n,{passive:!0}),this.xf.addEventListener("mouseleave",this.jf.bind(this)),this.xf.addEventListener("touchstart",this.Yf.bind(this),{passive:!0}),hn||this.xf.addEventListener("mousedown",this.Yf.bind(this)),this.Zf(),this.xf.addEventListener("touchmove",(function(){}),{passive:!1})},t.prototype.Zf=function(){var t=this;void 0===this.Nf.Jf&&void 0===this.Nf.Gf&&void 0===this.Nf.Qf||(this.xf.addEventListener("touchstart",(function(i){return t.tc(i.touches)}),{passive:!0}),this.xf.addEventListener("touchmove",(function(i){if(2===i.touches.length&&null!==t.mf&&void 0!==t.Nf.Gf){var n=un(i.touches[0],i.touches[1])/t.gf;t.Nf.Gf(t.mf,n),on(i)}}),{passive:!1}),this.xf.addEventListener("touchend",(function(i){t.tc(i.touches)})))},t.prototype.tc=function(t){1===t.length&&(this.pf=!1),2!==t.length||this.pf||this.cf?this.ic():this.nc(t)},t.prototype.nc=function(t){var i=en(this.xf);this.mf={g:(t[0].clientX-i.left+(t[1].clientX-i.left))/2,p:(t[0].clientY-i.top+(t[1].clientY-i.top))/2},this.gf=un(t[0],t[1]),void 0!==this.Nf.Jf&&this.Nf.Jf(),this.Cf()},t.prototype.ic=function(){null!==this.mf&&(this.mf=null,void 0!==this.Nf.Qf&&this.Nf.Qf())},t.prototype.jf=function(t){this.Mf&&this.Mf();var i=this.Lf(t);this.Bf(i,this.Nf.hc)},t.prototype.Kf=function(t){var i=this.Lf(t);this.Bf(i,this.Nf.sc),this.df=!0,this.cf=!0},t.prototype.Bf=function(t,i){i&&i.call(this.Nf,t)},t.prototype.Lf=function(t){var i;i="touches"in t&&t.touches.length?t.touches[0]:"changedTouches"in t&&t.changedTouches.length?t.changedTouches[0]:t;var n=en(this.xf);return{rc:i.clientX,ec:i.clientY,zf:i.pageX,Pf:i.pageY,uc:i.screenX,ac:i.screenY,oc:i.clientX-n.left,lc:i.clientY-n.top,fc:t.ctrlKey,cc:t.altKey,vc:t.shiftKey,_c:t.metaKey,ye:t.type.startsWith("mouse")?"mouse":"touch",dc:t.view}},t}();function en(t){return t.getBoundingClientRect()||{left:0,top:0}}function un(t,i){var n=t.clientX-i.clientX,h=t.clientY-i.clientY;return Math.sqrt(n*n+h*h)}function an(t){return Boolean(t.touches)}function on(t){t.cancelable&&t.preventDefault()}var ln=function(){function t(t,i,n,h){if(this.wc=0,this.Mc=0,this.bc=0,this.mc=0,this.gc=0,this.yc=0,this.kc=0,this.xc=!1,this.Nc=t,this.Sc=t.Cc()[i],this.Dc=t.Cc()[n],this.Tc=document.createElement("tr"),this.Tc.style.height="1px",this.Ec=document.createElement("td"),this.Ec.style.position="relative",this.Ec.style.padding="0",this.Ec.style.margin="0",this.Ec.setAttribute("colspan","3"),this.Lc(),this.Tc.appendChild(this.Ec),h)this.Bc=null,this.Ac=null;else{this.Bc=document.createElement("div"),this.Bc.style.position="absolute",this.Bc.style.zIndex="50",this.Bc.style.top="-4px",this.Bc.style.height="9px",this.Bc.style.width="100%",this.Bc.style.backgroundColor="",this.Bc.style.cursor="row-resize",this.Ec.appendChild(this.Bc);var s={Af:this.Vc.bind(this),hc:this.Oc.bind(this),$f:this.zc.bind(this),Wf:this.Pc.bind(this),Uf:this.Fc.bind(this)};this.Ac=new rn(this.Bc,s,{Ff:!1,If:!0})}}return t.prototype.un=function(){null!==this.Ac&&this.Ac.un()},t.prototype.Ic=function(){return this.Tc},t.prototype.Wc=function(){return new Zi(this.Sc.Wc().st,1)},t.prototype.Rc=function(){var t=this.Wc(),i=Qi(document,t),n=Gi(i);return n.fillStyle=this.Nc.I().timeScale.borderColor,n.fillRect(0,0,t.st,t.rt),i},t.prototype.V=function(){this.Lc()},t.prototype.Lc=function(){this.Ec.style.background=this.Nc.I().timeScale.borderColor},t.prototype.Vc=function(t){null!==this.Bc&&(this.Bc.style.backgroundColor="hsla(225,8%,72%,.2)")},t.prototype.Oc=function(t){null===this.Bc||this.xc||(this.Bc.style.backgroundColor="")},t.prototype.zc=function(t){this.wc=t.Pf,this.Mc=0,this.bc=this.Sc.Wc().rt+this.Dc.Wc().rt,this.mc=this.Sc.Uo()+this.Dc.Uo(),this.gc=30,this.yc=this.bc-this.gc,this.kc=this.mc/this.bc,this.xc=!0},t.prototype.Pc=function(t){this.Mc=t.Pf-this.wc;var i=this.Sc.Wc().rt,n=G(i+this.Mc,this.gc,this.yc)*this.kc,h=this.mc-n;this.Sc.qo(n),this.Dc.qo(h),this.Nc.jc(),this.Sc.Wc().rt!==i&&(this.wc=t.Pf),this.Nc.ct().El()},t.prototype.Fc=function(t){this.wc=0,this.Mc=0,this.bc=0,this.mc=0,this.gc=0,this.yc=0,this.kc=0,this.xc=!1,this.Oc(t)},t}(),fn=function(){function t(t,i,n,h){this.Tu=new ai(200),this.le=0,this.Uc="",this.Wu="",this.Nu=[],this.qc=new Map,this.le=t,this.Uc=i,this.Wu=Ot(t,n,h)}return t.prototype.un=function(){this.Tu.Su(),this.Nu=[],this.qc.clear()},t.prototype.Hc=function(t,i,n,h,s){var r=this.Yc(t,i);if("left"!==s){var e=Ji(t.canvas);n-=Math.floor(r.Kc*e)}h-=Math.floor(r.Mt/2),t.drawImage(r.$c,n,h,r.wt,r.Mt)},t.prototype.Yc=function(t,i){var n,h=this;if(this.qc.has(i))n=o(this.qc.get(i));else{if(this.Nu.length>=200){var s=o(this.Nu.shift());this.qc.delete(s)}var r=Ji(t.canvas),e=Math.ceil(this.le/4.5),u=Math.round(this.le/10),a=Math.ceil(this.Tu.Ot(t,i)),l=it(Math.round(a+2*e)),f=it(this.le+2*e),c=Qi(document,new Zi(l,f));n={Vt:i,Kc:Math.round(Math.max(1,a)),wt:Math.ceil(l*r),Mt:Math.ceil(f*r),$c:c},0!==a&&(this.Nu.push(n.Vt),this.qc.set(n.Vt,n)),O(t=Gi(n.$c),r,(function(){t.font=h.Wu,t.fillStyle=h.Uc,t.fillText(i,0,f-e-u)}))}return n},t}(),cn=function(){function t(t,i,n,h){var s=this;this.Qt=null,this.Xc=null,this.Zc=null,this.Jc=!1,this.Gc=new ai(50),this.Qc=new fn(11,"#000"),this.Uc=null,this.Wu=null,this.tv=0,this.iv=function(){s.nv(s.Sl.I()),s.wi.hv().ct().Pr()},this.sv=function(){s.wi.hv().ct().Pr()},this.wi=t,this.Si=i,this.Sl=n,this.rv="left"===h,this.Ec=document.createElement("div"),this.Ec.style.height="100%",this.Ec.style.overflow="hidden",this.Ec.style.width="25px",this.Ec.style.left="0",this.Ec.style.position="relative",this.ev=tn(this.Ec,new Zi(16,16)),this.ev.subscribeCanvasConfigured(this.iv);var r=this.ev.canvas;r.style.position="absolute",r.style.zIndex="1",r.style.left="0",r.style.top="0",this.uv=tn(this.Ec,new Zi(16,16)),this.uv.subscribeCanvasConfigured(this.sv);var e=this.uv.canvas;e.style.position="absolute",e.style.zIndex="2",e.style.left="0",e.style.top="0";var u={$f:this.zc.bind(this),Wf:this.Pc.bind(this),Xf:this.av.bind(this),Uf:this.Fc.bind(this),qf:this.ov.bind(this),Af:this.lv.bind(this),hc:this.Oc.bind(this)};this.Ac=new rn(this.uv.canvas,u,{Ff:!1,If:!0})}return t.prototype.un=function(){this.Ac.un(),this.uv.unsubscribeCanvasConfigured(this.sv),this.uv.destroy(),this.ev.unsubscribeCanvasConfigured(this.iv),this.ev.destroy(),null!==this.Qt&&this.Qt.Wh().sn(this),this.Qt=null,null!==this.Zc&&(clearTimeout(this.Zc),this.Zc=null),this.Qc.un()},t.prototype.Ic=function(){return this.Ec},t.prototype.$=function(){return this.Si.backgroundColor},t.prototype.S=function(){return l(this.Qt).I().borderColor},t.prototype.fv=function(){return this.Si.textColor},t.prototype.Pt=function(){return this.Si.fontSize},t.prototype.cv=function(){return Ot(this.Pt(),this.Si.fontFamily)},t.prototype.vv=function(){var t=this.Sl.I(),i=this.Uc!==t.ut,n=this.Wu!==t.Nt;return(i||n)&&(this.nv(t),this.Uc=t.ut),n&&(this.Gc.Su(),this.Wu=t.Nt),t},t.prototype._v=function(){if(null===this.Qt)return 0;var t=34,i=this.vv(),n=Gi(this.ev.canvas),h=this.Qt.Vn();n.font=this.cv(),h.length>0&&(t=Math.max(this.Gc.Ot(n,h[0].Ln),this.Gc.Ot(n,h[h.length-1].Ln)));for(var s=this.dv(),r=s.length;r--;){var e=this.Gc.Ot(n,s[r].Vt());e>t&&(t=e)}var u=Math.ceil(i.Tt+i.Dt+i.Bt+i.At+t);return u+=u%2},t.prototype.wv=function(t){if(t.st<0||t.rt<0)throw new Error("Try to set invalid size to PriceAxisWidget "+JSON.stringify(t));null!==this.Xc&&this.Xc.ln(t)||(this.Xc=t,this.ev.resizeCanvas({width:t.st,height:t.rt}),this.uv.resizeCanvas({width:t.st,height:t.rt}),this.Ec.style.width=t.st+"px",this.Ec.style.height=t.rt+"px",this.Ec.style.minWidth=t.st+"px")},t.prototype.Mv=function(){return l(this.Xc).st},t.prototype.ci=function(t){this.Qt!==t&&(null!==this.Qt&&this.Qt.Wh().sn(this),this.Qt=t,t.Wh().Gi(this.qn.bind(this),this))},t.prototype.J=function(){return this.Qt},t.prototype.Su=function(){var t=this.wi.bv();this.wi.hv().ct().rl(t,l(this.J()))},t.prototype.mv=function(t){if(null!==this.Xc){if(1!==t){var i=Gi(this.ev.canvas);this.gv(),this.pv(i,this.ev.pixelRatio),this.cu(i,this.ev.pixelRatio),this.yv(i,this.ev.pixelRatio),this.kv(i,this.ev.pixelRatio)}var n=Gi(this.uv.canvas),h=this.Xc.st,s=this.Xc.rt;O(n,this.uv.pixelRatio,(function(){n.clearRect(0,0,h,s)})),this.xv(n,this.uv.pixelRatio)}},t.prototype.Rc=function(){return this.ev.canvas},t.prototype.zc=function(t){if(null!==this.Qt&&!this.Qt.ii()&&this.wi.hv().I().handleScale.axisPressedMouseMove.price){var i=this.wi.hv().ct(),n=this.wi.bv();this.Jc=!0,i.Go(n,this.Qt,t.lc)}},t.prototype.Pc=function(t){if(null!==this.Qt&&this.wi.hv().I().handleScale.axisPressedMouseMove.price){var i=this.wi.hv().ct(),n=this.wi.bv(),h=this.Qt;i.Qo(n,h,t.lc)}},t.prototype.av=function(){if(null!==this.Qt&&this.wi.hv().I().handleScale.axisPressedMouseMove.price){var t=this.wi.hv().ct(),i=this.wi.bv(),n=this.Qt;this.Jc&&(this.Jc=!1,t.tl(i,n))}},t.prototype.Fc=function(t){if(null!==this.Qt&&this.wi.hv().I().handleScale.axisPressedMouseMove.price){var i=this.wi.hv().ct(),n=this.wi.bv();this.Jc=!1,i.tl(n,this.Qt)}},t.prototype.ov=function(t){this.wi.hv().I().handleScale.axisDoubleClickReset&&this.Su()},t.prototype.lv=function(t){null!==this.Qt&&(!this.wi.hv().ct().I().handleScale.axisPressedMouseMove.price||this.Qt.fh()||this.Qt._h()||this.Nv(1))},t.prototype.Oc=function(t){this.Nv(0)},t.prototype.dv=function(){var t=this,i=[],n=null===this.Qt?void 0:this.Qt;return function(h){for(var s=0;s<h.length;++s)for(var r=h[s].vi(t.wi.bv(),n),e=0;e<r.length;e++)i.push(r[e])}(this.wi.bv().Oh()),i},t.prototype.pv=function(t,i){var n=this;if(null!==this.Xc){var h=this.Xc.st,s=this.Xc.rt;O(t,i,(function(){z(t,0,0,h,s,n.$())}))}},t.prototype.cu=function(t,i){if(null!==this.Xc&&null!==this.Qt&&this.Qt.I().borderVisible){t.save(),t.fillStyle=this.S();var n,h=Math.max(1,Math.floor(this.vv().Tt*i));n=this.rv?Math.floor(this.Xc.st*i)-h:0,t.fillRect(n,0,h,Math.ceil(this.Xc.rt*i)),t.restore()}},t.prototype.yv=function(t,i){if(null!==this.Xc&&null!==this.Qt){var n=this.Qt.Vn();t.save(),t.strokeStyle=this.S(),t.font=this.cv(),t.fillStyle=this.S();var h=this.vv(),s=this.Qt.I().borderVisible&&this.Qt.I().drawTicks,r=this.rv?Math.floor((this.Xc.st-h.Dt)*i-h.Tt*i):Math.floor(h.Tt*i),e=this.rv?Math.round(r-h.Bt*i):Math.round(r+h.Dt*i+h.Bt*i),u=this.rv?"right":"left",a=Math.max(1,Math.floor(i)),o=Math.floor(.5*i);if(s){var l=Math.round(h.Dt*i);t.beginPath();for(var f=0,c=n;f<c.length;f++){var v=c[f];t.rect(r,Math.round(v.En*i)-o,l,a)}t.fill()}t.fillStyle=this.fv();for(var _=0,d=n;_<d.length;_++){v=d[_];this.Qc.Hc(t,v.Ln,e,Math.round(v.En*i),u)}t.restore()}},t.prototype.gv=function(){if(null!==this.Xc&&null!==this.Qt){var t=this.Xc.rt/2,i=[],n=this.Qt.Oh().slice(),h=this.wi.bv(),s=this.vv();this.Qt===h.Ti()&&this.wi.bv().Oh().forEach((function(t){h.Vu(t)&&n.push(t)}));var r=this.Qt.j()[0],e=this.Qt;n.forEach((function(n){var s=n.vi(h,e);s.forEach((function(t){t.$t(null),t.Xt()&&i.push(t)})),r===n&&s.length>0&&(t=s[0].Ft())}));var u=i.filter((function(i){return i.Ft()<=t})),a=i.filter((function(i){return i.Ft()>t}));if(u.sort((function(t,i){return i.Ft()-t.Ft()})),u.length&&a.length&&a.push(u[0]),a.sort((function(t,i){return t.Ft()-i.Ft()})),i.forEach((function(t){return t.$t(t.Ft())})),this.Qt.I().alignLabels){for(var o=1;o<u.length;o++){var l=u[o],f=(v=u[o-1]).Mt(s,!1);l.Ft()>(_=v.Kt())-f&&l.$t(_-f)}for(var c=1;c<a.length;c++){var v,_;l=a[c],f=(v=a[c-1]).Mt(s,!0);l.Ft()<(_=v.Kt())+f&&l.$t(_+f)}}}},t.prototype.kv=function(t,i){var n=this;if(null!==this.Xc){t.save();var h=this.Xc,s=this.dv(),r=this.vv(),e=this.rv?"right":"left";s.forEach((function(s){if(s.Zt()){var u=s.W(l(n.Qt));t.save(),u.h(t,r,n.Gc,h.st,e,i),t.restore()}})),t.restore()}},t.prototype.xv=function(t,i){var n=this;if(null!==this.Xc&&null!==this.Qt){t.save();var h=this.Xc,s=this.wi.hv().ct(),r=[],e=this.wi.bv(),u=s.Wl().vi(e,this.Qt);u.length&&r.push(u);var a=this.vv(),o=this.rv?"right":"left";r.forEach((function(s){s.forEach((function(s){t.save(),s.W(l(n.Qt)).h(t,a,n.Gc,h.st,o,i),t.restore()}))})),t.restore()}},t.prototype.Nv=function(t){this.Ec.style.cursor=1===t?"ns-resize":"default"},t.prototype.qn=function(){var t=this,i=this._v();if(this.tv<i){var n=this.wi.hv();null===this.Zc&&(this.Zc=setTimeout((function(){n&&n.ct().El(),t.Zc=null}),100))}this.tv=i},t.prototype.nv=function(t){this.Qc.un(),this.Qc=new fn(t.Pt,t.ut,t.oe)},t}(),vn=sn,_n=function(){function t(t,i){var n=this;this.Xc=new Zi(0,0),this.Sv=null,this.Cv=null,this.Dv=null,this.Tv=!1,this.Ev=new Z,this.Lv=0,this.Bv=!1,this.Av=null,this.Vv=!1,this.Ov=null,this.iv=function(){return n.zv&&n.ri().Pr()},this.sv=function(){return n.zv&&n.ri().Pr()},this.Pv=t,this.zv=i,this.zv.al().Gi(this.Fv.bind(this),this,!0),this.Iv=document.createElement("td"),this.Iv.style.padding="0",this.Iv.style.position="relative";var h=document.createElement("div");h.style.width="100%",h.style.height="100%",h.style.position="relative",h.style.overflow="hidden",this.Wv=document.createElement("td"),this.Wv.style.padding="0",this.Rv=document.createElement("td"),this.Rv.style.padding="0",this.Iv.appendChild(h),this.ev=tn(h,new Zi(16,16)),this.ev.subscribeCanvasConfigured(this.iv);var s=this.ev.canvas;s.style.position="absolute",s.style.zIndex="1",s.style.left="0",s.style.top="0",this.uv=tn(h,new Zi(16,16)),this.uv.subscribeCanvasConfigured(this.sv);var r=this.uv.canvas;r.style.position="absolute",r.style.zIndex="2",r.style.left="0",r.style.top="0",this.Tc=document.createElement("tr"),this.Tc.appendChild(this.Wv),this.Tc.appendChild(this.Iv),this.Tc.appendChild(this.Rv),this.jv();var e=this.hv().I().handleScroll;this.Ac=new rn(this.uv.canvas,this,{Ff:!e.vertTouchDrag,If:!e.horzTouchDrag})}return t.prototype.un=function(){null!==this.Sv&&this.Sv.un(),null!==this.Cv&&this.Cv.un(),this.uv.unsubscribeCanvasConfigured(this.sv),this.uv.destroy(),this.ev.unsubscribeCanvasConfigured(this.iv),this.ev.destroy(),null!==this.zv&&this.zv.al().sn(this),this.Ac.un()},t.prototype.bv=function(){return l(this.zv)},t.prototype.Uv=function(i){null!==this.zv&&this.zv.al().sn(this),this.zv=i,null!==this.zv&&this.zv.al().Gi(t.prototype.Fv.bind(this),this,!0),this.jv()},t.prototype.hv=function(){return this.Pv},t.prototype.Ic=function(){return this.Tc},t.prototype.jv=function(){if(null!==this.zv&&(this.qv(),0!==this.ri().O().length)){if(null!==this.Sv){var t=this.zv.Zo();this.Sv.ci(l(t))}if(null!==this.Cv){var i=this.zv.Jo();this.Cv.ci(l(i))}}},t.prototype.Uo=function(){return null!==this.zv?this.zv.Uo():0},t.prototype.qo=function(t){this.zv&&this.zv.qo(t)},t.prototype.Af=function(t){if(this.zv){var i=t.oc,n=t.lc;hn||this.Hv(i,n)}},t.prototype.$f=function(t){if(this.Bv=!1,this.Vv=null!==this.Av,this.zv){if(document.activeElement!==document.body&&document.activeElement!==document.documentElement)l(document.activeElement).blur();else{var i=document.getSelection();null!==i&&i.removeAllRanges()}var n=this.ri();if(!this.zv.Ti().ii()&&!n.q().ii()){if(null!==this.Av){var h=n.Wl();this.Ov={x:h.bt(),y:h.gt()},this.Av={x:t.oc,y:t.lc}}hn||this.Hv(t.oc,t.lc)}}},t.prototype.Vf=function(t){if(this.zv){var i=t.oc,n=t.lc;if(this.Yv()&&this.Kv(),!hn){this.Hv(i,n);var h=this.Ru(i,n);this.ri().Vl(h&&{Ol:h.Ol,$v:h.$v}),null!==h&&void 0!==h.dc.Xv&&h.dc.Xv(i,n)}}},t.prototype.Hf=function(t){if(null!==this.zv){var i=t.oc,n=t.lc,h=this.Ru(i,n);if(null!==h&&void 0!==h.dc.Zv&&h.dc.Zv(i,n),this.Ev.en()){var s=this.ri().Wl().U();this.Ev.rn(s,{x:i,y:n})}this.Jv()}},t.prototype.Wf=function(t){if(null!==this.zv){var i=this.ri(),n=t.oc,h=t.lc;if(null!==this.Av){this.Vv=!1;var s=l(this.Ov),r=s.x+(n-this.Av.x),e=s.y+(h-this.Av.y);this.Hv(r,e)}else this.Yv()||this.Hv(n,h);if(!i.q().ii()){var u=this.Pv.I().handleScroll;if(u.pressedMouseMove&&"touch"!==t.ye||(u.horzTouchDrag||u.vertTouchDrag)&&"mouse"!==t.ye){var a=this.zv.Ti();null!==this.Dv||this.Gv()||(this.Dv={x:t.rc,y:t.ec}),null===this.Dv||this.Dv.x===t.rc&&this.Dv.y===t.ec||this.Tv||(a.ii()||i.il(this.zv,a,t.lc),i.Kl(t.oc),this.Tv=!0),this.Tv&&(a.ii()||i.nl(this.zv,a,t.lc),i.$l(t.oc))}}}},t.prototype.Uf=function(t){if(null!==this.zv){this.Bv=!1;var i=this.ri();if(this.Tv){var n=this.zv.Ti();i.hl(this.zv,n),i.Xl(),this.Dv=null,this.Tv=!1}}},t.prototype.sc=function(t){if(this.Bv=!0,null===this.Av&&vn){var i={x:t.oc,y:t.lc};this.Qv(i,i)}},t.prototype.hc=function(t){null!==this.zv&&(this.zv.ct().Vl(null),sn||this.Kv())},t.prototype.t_=function(){return this.Ev},t.prototype.Jf=function(){this.Lv=1},t.prototype.Gf=function(t,i){if(this.Pv.I().handleScale.pinch){var n=5*(i-this.Lv);this.Lv=i,this.ri().Hl(t.g,n)}},t.prototype.Ru=function(t,i){var n=this.zv;if(null===n)return null;for(var h=0,s=n.Oh();h<s.length;h++){var r=s[h],e=this.i_(r._i(n),t,i);if(null!==e)return{Ol:r,dc:e.dc,$v:e.$v}}return null},t.prototype.n_=function(t,i){l("left"===i?this.Sv:this.Cv).wv(new Zi(t,this.Xc.rt))},t.prototype.Wc=function(){return this.Xc},t.prototype.wv=function(t){if(t.st<0||t.rt<0)throw new Error("Try to set invalid size to PaneWidget "+JSON.stringify(t));this.Xc.ln(t)||(this.Xc=t,this.ev.resizeCanvas({width:t.st,height:t.rt}),this.uv.resizeCanvas({width:t.st,height:t.rt}),this.Iv.style.width=t.st+"px",this.Iv.style.height=t.rt+"px")},t.prototype.h_=function(){var t=l(this.zv);t.Xo(t.Zo()),t.Xo(t.Jo());for(var i=0,n=t.j();i<n.length;i++){var h=n[i];if(t.Vu(h)){var s=h.J();null!==s&&t.Xo(s),h.ji()}}},t.prototype.Rc=function(){return this.ev.canvas},t.prototype.mv=function(t){if(0!==t&&null!==this.zv){if(t>1&&this.h_(),null!==this.Sv&&this.Sv.mv(t),null!==this.Cv&&this.Cv.mv(t),1!==t){var i=Gi(this.ev.canvas);i.save(),this.pv(i,this.s_(),this.ev.pixelRatio),this.zv&&(this.r_(i,this.ev.pixelRatio),this.e_(i,this.ev.pixelRatio),this.u_(i,this.ev.pixelRatio)),i.restore()}var n=Gi(this.uv.canvas);n.clearRect(0,0,Math.ceil(this.Xc.st*this.uv.pixelRatio),Math.ceil(this.Xc.rt*this.uv.pixelRatio)),this.a_(n,this.uv.pixelRatio)}},t.prototype.o_=function(){return this.Sv},t.prototype.l_=function(){return this.Cv},t.prototype.s_=function(){return this.Pv.I().layout.backgroundColor},t.prototype.Fv=function(){null!==this.zv&&this.zv.al().sn(this),this.zv=null},t.prototype.pv=function(t,i,n){var h=this;O(t,n,(function(){z(t,0,0,h.Xc.st,h.Xc.rt,i)}))},t.prototype.r_=function(t,i){var n=l(this.zv),h=n.ol().Eo().W(n.Mt(),n.wt(),n);null!==h&&(t.save(),h.h(t,i,!1),t.restore())},t.prototype.e_=function(t,i){var n=this.ri().Il();this.f_(n,t,i),this.c_(n,t,i)},t.prototype.a_=function(t,i){this.c_(this.ri().Wl(),t,i)},t.prototype.u_=function(t,i){for(var n=l(this.zv).Oh(),h=0,s=n;h<s.length;h++){var r=s[h];this.f_(r,t,i)}for(var e=0,u=n;e<u.length;e++){r=u[e];this.c_(r,t,i)}},t.prototype.c_=function(t,i,n){for(var h=l(this.zv),s=t._i(h),r=h.Mt(),e=h.wt(),u=h.ct().Al(),a=null!==u&&u.Ol===t,o=null!==u&&a&&void 0!==u.$v?u.$v.ju:void 0,f=0,c=s;f<c.length;f++){var v=c[f].W(r,e,h);null!==v&&(i.save(),v.h(i,n,a,o),i.restore())}},t.prototype.f_=function(t,i,n){for(var h=l(this.zv),s=t._i(h),r=h.Mt(),e=h.wt(),u=h.ct().Al(),a=null!==u&&u.Ol===t,o=null!==u&&a&&void 0!==u.$v?u.$v.ju:void 0,f=0,c=s;f<c.length;f++){var v=c[f].W(r,e,h);null!==v&&void 0!==v.o&&(i.save(),v.o(i,n,a,o),i.restore())}},t.prototype.i_=function(t,i,n){for(var h=l(this.zv),s=0,r=t;s<r.length;s++){var e=r[s],u=e.W(this.Xc.rt,this.Xc.st,h);if(null!==u&&u.Ru){var a=u.Ru(i,n);if(null!==a)return{dc:e,$v:a}}}return null},t.prototype.qv=function(){if(null!==this.zv){var t=this.Pv;t.I().leftPriceScale.visible||null===this.Sv||(this.Wv.removeChild(this.Sv.Ic()),this.Sv.un(),this.Sv=null),t.I().rightPriceScale.visible||null===this.Cv||(this.Rv.removeChild(this.Cv.Ic()),this.Cv.un(),this.Cv=null);var i=t.ct().nf();t.I().leftPriceScale.visible&&null===this.Sv&&(this.Sv=new cn(this,t.I().layout,i,"left"),this.Wv.appendChild(this.Sv.Ic())),t.I().rightPriceScale.visible&&null===this.Cv&&(this.Cv=new cn(this,t.I().layout,i,"right"),this.Rv.appendChild(this.Cv.Ic()))}},t.prototype.Yv=function(){return vn&&null===this.Av},t.prototype.Gv=function(){return vn&&this.Bv||null!==this.Av},t.prototype.v_=function(t){return Math.max(0,Math.min(t,this.Xc.st-1))},t.prototype.__=function(t){return Math.max(0,Math.min(t,this.Xc.rt-1))},t.prototype.Hv=function(t,i){this.ri().Gl(this.v_(t),this.__(i),l(this.zv))},t.prototype.Kv=function(){this.ri().tf()},t.prototype.Jv=function(){this.Vv&&(this.Av=null,this.Kv())},t.prototype.Qv=function(t,i){this.Av=t,this.Vv=!1,this.Hv(i.x,i.y);var n=this.ri().Wl();this.Ov={x:n.bt(),y:n.gt()}},t.prototype.ri=function(){return this.Pv.ct()},t}(),dn=function(){function t(t,i,n,h){var s=this;this.Ut=!0,this.Xc=new Zi(0,0),this.iv=function(){return s.mv(3)},this.rv="left"===t,this.Sl=n.nf,this.Si=i,this.d_=h,this.Ec=document.createElement("div"),this.Ec.style.width="25px",this.Ec.style.height="100%",this.Ec.style.overflow="hidden",this.ev=tn(this.Ec,new Zi(16,16)),this.ev.subscribeCanvasConfigured(this.iv)}return t.prototype.un=function(){this.ev.unsubscribeCanvasConfigured(this.iv),this.ev.destroy()},t.prototype.Ic=function(){return this.Ec},t.prototype.Wc=function(){return this.Xc},t.prototype.wv=function(t){if(t.st<0||t.rt<0)throw new Error("Try to set invalid size to PriceAxisStub "+JSON.stringify(t));this.Xc.ln(t)||(this.Xc=t,this.ev.resizeCanvas({width:t.st,height:t.rt}),this.Ec.style.width=t.st+"px",this.Ec.style.minWidth=t.st+"px",this.Ec.style.height=t.rt+"px",this.Ut=!0)},t.prototype.mv=function(t){if((!(t<3)||this.Ut)&&0!==this.Xc.st&&0!==this.Xc.rt){this.Ut=!1;var i=Gi(this.ev.canvas);this.pv(i,this.ev.pixelRatio),this.cu(i,this.ev.pixelRatio)}},t.prototype.Rc=function(){return this.ev.canvas},t.prototype.cu=function(t,i){if(this.d_()){var n=this.Xc.st;t.save(),t.fillStyle=this.Si.timeScale.borderColor;var h=Math.floor(this.Sl.I().Tt*i),s=this.rv?Math.round(n*i)-h:0;t.fillRect(s,0,h,h),t.restore()}},t.prototype.pv=function(t,i){var n=this;O(t,i,(function(){z(t,0,0,n.Xc.st,n.Xc.rt,n.Si.layout.backgroundColor)}))},t}();function wn(t,i){return t.Is>i.Is?t:i}var Mn=function(){function t(t){var i=this;this.w_=null,this.M_=null,this.ae=null,this.b_=!1,this.Xc=new Zi(0,0),this.iv=function(){return i.Pv.ct().Pr()},this.sv=function(){return i.Pv.ct().Pr()},this.Pv=t,this.Si=t.I().layout,this.m_=document.createElement("tr"),this.g_=document.createElement("td"),this.g_.style.padding="0",this.p_=document.createElement("td"),this.p_.style.padding="0",this.Ec=document.createElement("td"),this.Ec.style.height="25px",this.Ec.style.padding="0",this.y_=document.createElement("div"),this.y_.style.width="100%",this.y_.style.height="100%",this.y_.style.position="relative",this.y_.style.overflow="hidden",this.Ec.appendChild(this.y_),this.ev=tn(this.y_,new Zi(16,16)),this.ev.subscribeCanvasConfigured(this.iv);var n=this.ev.canvas;n.style.position="absolute",n.style.zIndex="1",n.style.left="0",n.style.top="0",this.uv=tn(this.y_,new Zi(16,16)),this.uv.subscribeCanvasConfigured(this.sv);var h=this.uv.canvas;h.style.position="absolute",h.style.zIndex="2",h.style.left="0",h.style.top="0",this.m_.appendChild(this.g_),this.m_.appendChild(this.Ec),this.m_.appendChild(this.p_),this.k_(),this.Pv.ct().jo().Gi(this.k_.bind(this),this),this.Ac=new rn(this.uv.canvas,this,{Ff:!0,If:!1})}return t.prototype.un=function(){this.Ac.un(),null!==this.w_&&this.w_.un(),null!==this.M_&&this.M_.un(),this.uv.unsubscribeCanvasConfigured(this.sv),this.uv.destroy(),this.ev.unsubscribeCanvasConfigured(this.iv),this.ev.destroy()},t.prototype.Ic=function(){return this.m_},t.prototype.x_=function(){return this.w_},t.prototype.N_=function(){return this.M_},t.prototype.$f=function(t){if(!this.b_){this.b_=!0;var i=this.Pv.ct();!i.q().ii()&&this.Pv.I().handleScale.axisPressedMouseMove.time&&i.ql(t.oc)}},t.prototype.Xf=function(){var t=this.Pv.ct();!t.q().ii()&&this.b_&&(this.b_=!1,this.Pv.I().handleScale.axisPressedMouseMove.time&&t.Jl())},t.prototype.Wf=function(t){var i=this.Pv.ct();!i.q().ii()&&this.Pv.I().handleScale.axisPressedMouseMove.time&&i.Zl(t.oc)},t.prototype.Uf=function(t){this.b_=!1;var i=this.Pv.ct();i.q().ii()&&!this.Pv.I().handleScale.axisPressedMouseMove.time||i.Jl()},t.prototype.qf=function(){this.Pv.I().handleScale.axisDoubleClickReset&&this.Pv.ct().xe()},t.prototype.Af=function(t){this.Pv.ct().I().handleScale.axisPressedMouseMove.time&&this.Nv(1)},t.prototype.hc=function(t){this.Nv(0)},t.prototype.Wc=function(){return this.Xc},t.prototype.S_=function(t,i,n){this.Xc&&this.Xc.ln(t)||(this.Xc=t,this.ev.resizeCanvas({width:t.st,height:t.rt}),this.uv.resizeCanvas({width:t.st,height:t.rt}),this.Ec.style.width=t.st+"px",this.Ec.style.height=t.rt+"px"),null!==this.w_&&this.w_.wv(new Zi(i,t.rt)),null!==this.M_&&this.M_.wv(new Zi(n,t.rt))},t.prototype.C_=function(){var t=this.D_();return Math.ceil(t.Tt+t.Dt+t.Pt+t.Et+t.Lt)},t.prototype.V=function(){this.Pv.ct().q().Vn()},t.prototype.Rc=function(){return this.ev.canvas},t.prototype.mv=function(t){if(0!==t){if(1!==t){var i=Gi(this.ev.canvas);this.pv(i,this.ev.pixelRatio),this.cu(i,this.ev.pixelRatio),this.yv(i,this.ev.pixelRatio),null!==this.w_&&this.w_.mv(t),null!==this.M_&&this.M_.mv(t)}var n=Gi(this.uv.canvas),h=this.uv.pixelRatio;n.clearRect(0,0,Math.ceil(this.Xc.st*h),Math.ceil(this.Xc.rt*h)),this.T_([this.Pv.ct().Wl()],n,h)}},t.prototype.pv=function(t,i){var n=this;O(t,i,(function(){z(t,0,0,n.Xc.st,n.Xc.rt,n.s_())}))},t.prototype.cu=function(t,i){if(this.Pv.I().timeScale.borderVisible){t.save(),t.fillStyle=this.E_();var n=Math.max(1,Math.floor(this.D_().Tt*i));t.fillRect(0,0,Math.ceil(this.Xc.st*i),n),t.restore()}},t.prototype.yv=function(t,i){var n=this,h=this.Pv.ct().q().Vn();if(h&&0!==h.length){var s=h.reduce(wn,h[0]).Is;s>30&&s<40&&(s=30),t.save(),t.strokeStyle=this.E_();var r=this.D_(),e=r.Tt+r.Dt+r.Et+r.Pt-r.zt;t.textAlign="center",t.fillStyle=this.E_();var u=Math.floor(this.D_().Tt*i),a=Math.max(1,Math.floor(i)),o=Math.floor(.5*i);if(this.Pv.ct().q().I().borderVisible){t.beginPath();for(var l=Math.round(r.Dt*i),f=h.length;f--;){var c=Math.round(h[f].En*i);t.rect(c-o,u,a,l)}t.fill()}t.fillStyle=this.ce(),O(t,i,(function(){t.font=n.L_();for(var i=0,r=h;i<r.length;i++){(o=r[i]).Is<s&&t.fillText(o.Ln,o.En,e)}t.font=n.B_();for(var u=0,a=h;u<a.length;u++){var o;(o=a[u]).Is>=s&&t.fillText(o.Ln,o.En,e)}}))}},t.prototype.T_=function(t,i,n){for(var h=this.D_(),s=0,r=t;s<r.length;s++)for(var e=0,u=r[s].di();e<u.length;e++){var a=u[e];i.save(),a.W().h(i,h,n),i.restore()}},t.prototype.s_=function(){return this.Si.backgroundColor},t.prototype.E_=function(){return this.Pv.I().timeScale.borderColor},t.prototype.ce=function(){return this.Si.textColor},t.prototype.le=function(){return this.Si.fontSize},t.prototype.L_=function(){return Ot(this.le(),this.Si.fontFamily)},t.prototype.B_=function(){return Ot(this.le(),this.Si.fontFamily,"bold")},t.prototype.D_=function(){null===this.ae&&(this.ae={Tt:1,zt:NaN,Et:NaN,Lt:NaN,si:NaN,Dt:3,Pt:NaN,Nt:"",hi:new ai});var t=this.ae,i=this.L_();if(t.Nt!==i){var n=this.le();t.Pt=n,t.Nt=i,t.Et=Math.ceil(n/2.5),t.Lt=t.Et,t.si=Math.ceil(n/2),t.zt=Math.round(this.le()/5),t.hi.Su()}return this.ae},t.prototype.Nv=function(t){this.Ec.style.cursor=1===t?"ew-resize":"default"},t.prototype.k_=function(){var t=this.Pv.ct(),i=t.I();i.leftPriceScale.visible||null===this.w_||(this.g_.removeChild(this.w_.Ic()),this.w_.un(),this.w_=null),i.rightPriceScale.visible||null===this.M_||(this.p_.removeChild(this.M_.Ic()),this.M_.un(),this.M_=null);var n={nf:this.Pv.ct().nf()};if(i.leftPriceScale.visible&&null===this.w_){var h=function(){return i.leftPriceScale.borderVisible&&t.q().I().borderVisible};this.w_=new dn("left",this.Pv.I(),n,h),this.g_.appendChild(this.w_.Ic())}if(i.rightPriceScale.visible&&null===this.M_){h=function(){return i.rightPriceScale.borderVisible&&t.q().I().borderVisible};this.M_=new dn("right",this.Pv.I(),n,h),this.p_.appendChild(this.M_.Ic())}},t}(),bn=function(){function t(t,i){var n;this.A_=[],this.V_=[],this.O_=0,this.On=0,this.Ks=0,this.z_=0,this.P_=0,this.F_=null,this.I_=!1,this.Ev=new Z,this.xl=new Z,this.Si=i,this.m_=document.createElement("div"),this.m_.classList.add("tv-lightweight-charts"),this.m_.style.overflow="hidden",this.m_.style.width="100%",this.m_.style.height="100%",(n=this.m_).style.userSelect="none",n.style.webkitUserSelect="none",n.style.msUserSelect="none",n.style.MozUserSelect="none",n.style.webkitTapHighlightColor="transparent",this.W_=document.createElement("table"),this.W_.setAttribute("cellspacing","0"),this.m_.appendChild(this.W_),this.R_=this.j_.bind(this),this.m_.addEventListener("wheel",this.R_,{passive:!1}),this.ri=new Ki(this.Nl.bind(this),this.Si),this.ct().Rl().Gi(this.U_.bind(this),this),this.q_=new Mn(this),this.W_.appendChild(this.q_.Ic());var h=this.Si.width,s=this.Si.height;if(0===h||0===s){var r=t.getBoundingClientRect();0===h&&(h=Math.floor(r.width),h-=h%2),0===s&&(s=Math.floor(r.height),s-=s%2)}this.H_(h,s),this.Y_(),t.appendChild(this.m_),this.K_(),this.ri.q().Zr().Gi(this.ri.El.bind(this.ri),this),this.ri.jo().Gi(this.ri.El.bind(this.ri),this)}return t.prototype.ct=function(){return this.ri},t.prototype.I=function(){return this.Si},t.prototype.Cc=function(){return this.A_},t.prototype.un=function(){this.m_.removeEventListener("wheel",this.R_),0!==this.O_&&window.cancelAnimationFrame(this.O_),this.ri.Rl().sn(this),this.ri.q().Zr().sn(this),this.ri.jo().sn(this),this.ri.un();for(var t=0,i=this.A_;t<i.length;t++){var n=i[t];this.W_.removeChild(n.Ic()),n.t_().sn(this),n.un()}this.A_=[];for(var h=0,s=this.V_;h<s.length;h++){var r=s[h];this.X_(r)}this.V_=[],l(this.q_).un(),null!==this.m_.parentElement&&this.m_.parentElement.removeChild(this.m_),this.xl.un(),this.Ev.un()},t.prototype.H_=function(t,i,n){if(void 0===n&&(n=!1),this.On!==i||this.Ks!==t){this.On=i,this.Ks=t;var h=i+"px",s=t+"px";l(this.m_).style.height=h,l(this.m_).style.width=s,this.W_.style.height=h,this.W_.style.width=s,n?this.Z_(new Ft(3)):this.ri.El()}},t.prototype.mv=function(t){void 0===t&&(t=new Ft(3));for(var i=0;i<this.A_.length;i++)this.A_[i].mv(t.ge(i).be);this.q_.mv(t.me())},t.prototype.rh=function(t){this.ri.rh(t),this.K_();var i=t.width||this.Ks,n=t.height||this.On;this.H_(i,n)},t.prototype.t_=function(){return this.Ev},t.prototype.Rl=function(){return this.xl},t.prototype.J_=function(){var t=this;null!==this.F_&&(this.Z_(this.F_),this.F_=null);var i=this.A_[0],n=Qi(document,new Zi(this.Ks,this.On)),h=Gi(n),s=Ji(n);return O(h,s,(function(){var n=0,s=0,r=function(i){for(var r=0;r<t.A_.length;r++){var e=t.A_[r],u=e.Wc().rt,a=l("left"===i?e.o_():e.l_()),o=a.Rc();if(h.drawImage(o,n,s,a.Mv(),u),s+=u,r<t.A_.length-1){var f=t.V_[r],c=f.Wc(),v=f.Rc();h.drawImage(v,n,s,c.st,c.rt),s+=c.rt}}};t.G_()&&(r("left"),n=l(i.o_()).Mv()),s=0;for(var e=0;e<t.A_.length;e++){var u=t.A_[e],a=u.Wc(),o=u.Rc();if(h.drawImage(o,n,s,a.st,a.rt),s+=a.rt,e<t.A_.length-1){var f=t.V_[e],c=f.Wc(),v=f.Rc();h.drawImage(v,n,s,c.st,c.rt),s+=c.rt}}n+=i.Wc().st,t.Q_()&&(s=0,r("right"));var _=function(i){var r=l("left"===i?t.q_.x_():t.q_.N_()),e=r.Wc(),u=r.Rc();h.drawImage(u,n,s,e.st,e.rt)};if(t.Si.timeScale.visible){n=0,t.G_()&&(_("left"),n=l(i.o_()).Mv());var d=t.q_.Wc();o=t.q_.Rc();h.drawImage(o,n,s,d.st,d.rt),t.Q_()&&(n+=i.Wc().st,_("right"),h.restore())}})),n},t.prototype.td=function(t){return"none"===t?0:("left"!==t||this.G_())&&("right"!==t||this.Q_())?0===this.A_.length?0:l("left"===t?this.A_[0].o_():this.A_[0].l_()).Mv():0},t.prototype.jc=function(){this.nd()},t.prototype.nd=function(){for(var t,i=0,n=0,h=0,s=0,r=this.A_;s<r.length;s++){var e=r[s];this.G_()&&(n=Math.max(n,l(e.o_())._v())),this.Q_()&&(h=Math.max(h,l(e.l_())._v())),i+=e.Uo()}var u=this.Ks,a=this.On,o=Math.max(u-n-h,0),f=1*this.V_.length,c=this.Si.timeScale.visible?this.q_.C_():0;c%2&&(c+=1);for(var v=f+c,_=a<v?0:a-v,d=_/i,w=0,M=(null===(t=document.body.ownerDocument.defaultView)||void 0===t?void 0:t.devicePixelRatio)||1,b=0;b<this.A_.length;++b){(e=this.A_[b]).Uv(this.ri.Fl()[b]);var m,g=0;g=b===this.A_.length-1?Math.ceil((_-w)*M)/M:Math.round(e.Uo()*d*M)/M,w+=m=Math.max(g,2),e.wv(new Zi(o,m)),this.G_()&&e.n_(n,"left"),this.Q_()&&e.n_(h,"right"),e.bv()&&this.ri.jl(e.bv(),m)}this.q_.S_(new Zi(o,c),n,h),this.ri.Dr(o),this.z_!==n&&(this.z_=n),this.P_!==h&&(this.P_=h)},t.prototype.j_=function(t){var i=t.deltaX/100,n=-t.deltaY/100;if(0!==i&&this.Si.handleScroll.mouseWheel||0!==n&&this.Si.handleScale.mouseWheel){switch(t.cancelable&&t.preventDefault(),t.deltaMode){case t.DOM_DELTA_PAGE:i*=120,n*=120;break;case t.DOM_DELTA_LINE:i*=32,n*=32}if(0!==n&&this.Si.handleScale.mouseWheel){var h=Math.sign(n)*Math.min(1,Math.abs(n)),s=t.clientX-this.m_.getBoundingClientRect().left;this.ct().Hl(s,h)}0!==i&&this.Si.handleScroll.mouseWheel&&this.ct().Yl(-80*i)}},t.prototype.Z_=function(t){var i=t.me();if(3===i&&this.hd(),3===i||2===i){for(var n=this.ri.Fl(),h=0;h<n.length;h++)t.ge(h).dh&&n[h].el();for(var s=t.Ne(),r=0,e=s;r<e.length;r++){var u=e[r];this.Se(u)}s.length>0&&(this.ri.zr(),this.ri.eo(),this.ri.Pr()),this.q_.V()}this.mv(t)},t.prototype.Se=function(t){var i=this.ri.q();switch(t.ye){case 0:i.Gr();break;case 1:i.Qr(t.G);break;case 2:i.dr(t.G);break;case 3:i.wr(t.G);break;case 4:i.Rr()}},t.prototype.Nl=function(t){var i=this;null!==this.F_?this.F_.dn(t):this.F_=t,this.I_||(this.I_=!0,this.O_=window.requestAnimationFrame((function(){i.I_=!1,i.O_=0,null!==i.F_&&(i.Z_(i.F_),i.F_=null)})))},t.prototype.hd=function(){this.Y_()},t.prototype.X_=function(t){this.W_.removeChild(t.Ic()),t.un()},t.prototype.Y_=function(){for(var t=this.ri.Fl(),i=t.length,n=this.A_.length,h=i;h<n;h++){var s=o(this.A_.pop());this.W_.removeChild(s.Ic()),s.t_().sn(this),s.un(),void 0!==(r=this.V_.pop())&&this.X_(r)}for(h=n;h<i;h++){if((s=new _n(this,t[h])).t_().Gi(this.sd.bind(this),this),this.A_.push(s),h>0){var r=new ln(this,h-1,h,!1);this.V_.push(r),this.W_.insertBefore(r.Ic(),this.q_.Ic())}this.W_.insertBefore(s.Ic(),this.q_.Ic())}for(h=0;h<i;h++){var e=t[h];(s=this.A_[h]).bv()!==e?s.Uv(e):s.jv()}this.K_(),this.nd()},t.prototype.rd=function(t,i){var n,h=new Map;null!==t&&this.ri.O().forEach((function(i){var n=i.ia(t);null!==n&&h.set(i,n)}));if(null!==t){var s=this.ri.q().ei(t);null!==s&&(n=s)}var r=this.ct().Al(),e=null!==r&&r.Ol instanceof Fi?r.Ol:void 0,u=null!==r&&void 0!==r.$v?r.$v.qu:void 0;return{P:n,ed:i||void 0,ud:e,ad:h,od:u}},t.prototype.sd=function(t,i){var n=this;this.Ev.rn((function(){return n.rd(t,i)}))},t.prototype.U_=function(t,i){var n=this;this.xl.rn((function(){return n.rd(t,i)}))},t.prototype.K_=function(){var t=this.Si.timeScale.visible?"":"none";this.q_.Ic().style.display=t},t.prototype.G_=function(){return this.Si.leftPriceScale.visible},t.prototype.Q_=function(){return this.Si.rightPriceScale.visible},t}();function mn(t,i,n){var h=n.value,s={Fs:i,P:t,G:[h,h,h,h]};return"color"in n&&void 0!==n.color&&(s.ut=n.color),s}function gn(t,i,n){return{Fs:i,P:t,G:[n.open,n.high,n.low,n.close]}}function pn(t){return void 0!==t.G}function yn(t){return function(i,n,h){return void 0===(s=h).open&&void 0===s.value?{P:i,Fs:n}:t(i,n,h);var s}}var kn={Candlestick:yn(gn),Bar:yn(gn),Area:yn(mn),Histogram:yn(mn),Line:yn(mn)};function xn(t){return kn[t]}function Nn(t){return 60*t*60*1e3}function Sn(t){return 60*t*1e3}var Cn,Dn=[{ld:1,Is:20},{ld:(Cn=1,1e3*Cn),Is:19},{ld:Sn(1),Is:20},{ld:Sn(5),Is:21},{ld:Sn(30),Is:22},{ld:Nn(1),Is:30},{ld:Nn(3),Is:31},{ld:Nn(6),Is:32},{ld:Nn(12),Is:33}];function Tn(t,i){if(null!==i){var n=new Date(1e3*i),h=new Date(1e3*t);if(h.getUTCFullYear()!==n.getUTCFullYear())return 70;if(h.getUTCMonth()!==n.getUTCMonth())return 60;if(h.getUTCDate()!==n.getUTCDate())return 50;for(var s=Dn.length-1;s>=0;--s)if(Math.floor(n.getTime()/Dn[s].ld)!==Math.floor(h.getTime()/Dn[s].ld))return Dn[s].Is}return 20}function En(t){if(!Bt(t))throw new Error("time must be of type BusinessDay");var i=new Date(Date.UTC(t.year,t.month-1,t.day,0,0,0,0));return{Ds:Math.round(i.getTime()/1e3),Cs:t}}function Ln(t){if(!At(t))throw new Error("time must be of type isUTCTimestamp");return{Ds:t}}function Bn(t){return 0===t.length?null:Bt(t[0].time)?En:Ln}function An(t){return At(t)?Ln(t):Bt(t)?En(t):En(Vn(t))}function Vn(t){var i=new Date(t);if(isNaN(i.getTime()))throw new Error("Invalid date string="+t+", expected format=yyyy-mm-dd");return{day:i.getUTCDate(),month:i.getUTCMonth()+1,year:i.getUTCFullYear()}}function On(t){d(t.time)&&(t.time=Vn(t.time))}function zn(t){return{Fs:0,fd:new Map,Ih:t}}var Pn=function(){function t(){this.vd=new Map,this._d=new Map,this.dd=new Map,this.wd=[]}return t.prototype.un=function(){this.vd.clear(),this._d.clear(),this.dd.clear(),this.wd=[]},t.prototype.Md=function(t,i){var n=this;this.dd.has(t)&&this.vd.forEach((function(i){return i.fd.delete(t)}));var h=[];if(0!==i.length){!function(t){t.forEach(On)}(i);var s=l(Bn(i)),r=xn(t.wa());h=i.map((function(i){var h=s(i.time),e=n.vd.get(h.Ds);void 0===e&&(e=zn(h),n.vd.set(h.Ds,e));var u=r(h,e.Fs,i);return e.fd.set(t,u),u}))}return this.bd(),this.md(t,h),this.gd(t)},t.prototype.rf=function(t){return this.Md(t,[])},t.prototype.pd=function(t,i){On(i);var n=l(Bn([i]))(i.time),h=this.dd.get(t);if(void 0!==h&&n.Ds<h.Ds)throw new Error("Cannot update oldest data, last time="+h.Ds+", new time="+n.Ds);var s=this.vd.get(n.Ds),r=void 0===s;void 0===s&&(s=zn(n),this.vd.set(n.Ds,s));var e=xn(t.wa())(n,s.Fs,i);s.fd.set(t,e);var u=this.yd(t,e);if(!r){var a=new Map;return null!==u&&a.set(t,u),{kd:a,q:{Br:this.xd()}}}return this.gd(t)},t.prototype.yd=function(t,i){var n=this._d.get(t);void 0===n&&(n=[],this._d.set(t,n));var h=0!==n.length?n[n.length-1]:null,s=null;return null===h||i.P.Ds>h.P.Ds?pn(i)&&(n.push(i),s={El:!1,Nd:[i]}):pn(i)?(n[n.length-1]=i,s={El:!1,Nd:[i]}):(n.splice(-1,1),s={El:!0,Nd:n}),this.dd.set(t,i.P),s},t.prototype.md=function(t,i){0!==i.length?(this._d.set(t,i.filter(pn)),this.dd.set(t,i[i.length-1].P)):(this._d.delete(t),this.dd.delete(t))},t.prototype.bd=function(){var t=new Map;this.vd.forEach((function(i,n){i.fd.size>0&&t.set(n,i)})),this.vd=t},t.prototype.Sd=function(t){for(var i=-1,n=0;n<this.wd.length&&n<t.length;++n){var h=this.wd[n],s=t[n];if(h.P.Ds!==s.P.Ds){i=n;break}s.Ps=h.Ps}if(-1===i&&this.wd.length!==t.length&&(i=Math.min(this.wd.length,t.length)),-1===i)return-1;var r=function(i){var n=o(e.vd.get(t[i].P.Ds));n.Fs=i,n.fd.forEach((function(t){t.Fs=i}))},e=this;for(n=i;n<t.length;++n)r(n);return function(t,i){void 0===i&&(i=0);for(var n=0===i||0===t.length?null:t[i-1].P.Ds,h=0,s=i;s<t.length;++s){var r=t[s];r.Ps=Tn(r.P.Ds,n),h+=r.P.Ds-(n||r.P.Ds),n=r.P.Ds}if(0===i&&t.length>1){var e=Math.ceil(h/(t.length-1)),u=t[0].P.Ds-e;t[0].Ps=Tn(t[0].P.Ds,u)}}(t,i),this.wd=t,i},t.prototype.xd=function(){if(0===this._d.size)return null;var t=0;return this._d.forEach((function(i){0!==i.length&&(t=Math.max(t,i[i.length-1].Fs))})),t},t.prototype.gd=function(t){var i=Array.from(this.vd.values()).map((function(t){return{Ps:0,P:t.Ih}}));i.sort((function(t,i){return t.P.Ds-i.P.Ds}));var n=this.Sd(i),h={kd:new Map,q:{Br:this.xd()}};if(-1!==n)this._d.forEach((function(t,i){h.kd.set(i,{Nd:t,El:!0})})),this._d.has(t)||h.kd.set(t,{Nd:[],El:!0}),h.q.Cd=this.wd;else{var s=this._d.get(t);h.kd.set(t,{Nd:s||[],El:!0})}return h},t}();var Fn={color:"#FF0000",price:0,lineStyle:2,lineWidth:1,axisLabelVisible:!0,title:""},In=function(){function t(t){this.fa=t}return t.prototype.applyOptions=function(t){this.fa.rh(t)},t.prototype.options=function(){return this.fa.I()},t.prototype.Dd=function(){return this.fa},t}();function Wn(t){var i=t.overlay,n=function(t,i){var n={};for(var h in t)Object.prototype.hasOwnProperty.call(t,h)&&i.indexOf(h)<0&&(n[h]=t[h]);if(null!=t&&"function"==typeof Object.getOwnPropertySymbols){var s=0;for(h=Object.getOwnPropertySymbols(t);s<h.length;s++)i.indexOf(h[s])<0&&Object.prototype.propertyIsEnumerable.call(t,h[s])&&(n[h[s]]=t[h[s]])}return n}(t,["overlay"]);return i&&(n.priceScaleId=""),n}var Rn=function(){function t(t,i,n){this.Ie=t,this.Td=i,this.Ed=n}return t.prototype.priceFormatter=function(){return this.Ie.Kh()},t.prototype.priceToCoordinate=function(t){var i=this.Ie.K();return null===i?null:this.Ie.J().Z(t,i.G)},t.prototype.coordinateToPrice=function(t){var i=this.Ie.K();return null===i?null:this.Ie.J().Ei(t,i.G)},t.prototype.barsInLogicalRange=function(t){if(null===t)return null;var i=new Et(new St(t.from,t.to)).qs(),n=this.Ie.Yi();if(n.ii())return null;var h=n.Ba(i.ss(),1),s=n.Ba(i.rs(),-1),r=l(n.Ta()),e=l(n.Hi());if(null!==h&&null!==s&&h.Fs>s.Fs)return{barsBefore:t.from-r,barsAfter:e-t.to};var u={barsBefore:null===h||h.Fs===r?t.from-r:h.Fs-r,barsAfter:null===s||s.Fs===e?e-t.to:e-s.Fs};return null!==h&&null!==s&&(u.from=h.P.Cs||h.P.Ds,u.to=s.P.Cs||s.P.Ds),u},t.prototype.setData=function(t){this.Ie.wa(),this.Td.Ld(this.Ie,t)},t.prototype.update=function(t){this.Ie.wa(),this.Td.ao(this.Ie,t)},t.prototype.setMarkers=function(t){var i=t.map((function(t){return e(e({},t),{time:An(t.time)})}));this.Ie.fo(i)},t.prototype.applyOptions=function(t){var i=Wn(t);this.Ie.rh(i)},t.prototype.options=function(){return M(this.Ie.I())},t.prototype.priceScale=function(){return this.Ed.priceScale(this.Ie.J().sh())},t.prototype.createPriceLine=function(t){var i=c(M(Fn),t),n=this.Ie.co(i);return new In(n)},t.prototype.removePriceLine=function(t){this.Ie.vo(t.Dd())},t.prototype.seriesType=function(){return this.Ie.wa()},t}(),jn=function(t){function i(){return null!==t&&t.apply(this,arguments)||this}return r(i,t),i.prototype.applyOptions=function(i){bt(i),t.prototype.applyOptions.call(this,i)},i}(Rn),Un={autoScale:!0,mode:0,invertScale:!1,alignLabels:!0,borderVisible:!0,borderColor:"#2B2B43",entireTextOnly:!1,visible:!1,drawTicks:!0,scaleMargins:{bottom:.1,top:.2}},qn={color:"rgba(0, 0, 0, 0)",visible:!1,fontSize:48,fontFamily:Vt,fontStyle:"",text:"",horzAlign:"center",vertAlign:"center"},Hn={width:0,height:0,layout:{backgroundColor:"#FFFFFF",textColor:"#191919",fontSize:11,fontFamily:Vt},crosshair:{vertLine:{color:"#758696",width:1,style:3,visible:!0,labelVisible:!0,labelBackgroundColor:"#4c525e"},horzLine:{color:"#758696",width:1,style:3,visible:!0,labelVisible:!0,labelBackgroundColor:"#4c525e"},mode:1},grid:{vertLines:{color:"#D6DCDE",style:0,visible:!0},horzLines:{color:"#D6DCDE",style:0,visible:!0}},overlayPriceScales:e({},Un),leftPriceScale:e(e({},Un),{visible:!1}),rightPriceScale:e(e({},Un),{visible:!0}),timeScale:{rightOffset:0,barSpacing:6,minBarSpacing:.5,fixLeftEdge:!1,fixRightEdge:!1,lockVisibleTimeRangeOnResize:!1,rightBarStaysOnScroll:!1,borderVisible:!0,borderColor:"#2B2B43",visible:!0,timeVisible:!1,secondsVisible:!0,shiftVisibleRangeOnNewBar:!0},watermark:qn,localization:{locale:nn?navigator.language:"",dateFormat:"dd MMM 'yy"},handleScroll:{mouseWheel:!0,pressedMouseMove:!0,horzTouchDrag:!0,vertTouchDrag:!0},handleScale:{axisPressedMouseMove:{time:!0,price:!0},axisDoubleClickReset:!0,mouseWheel:!0,pinch:!0}},Yn={upColor:"#26a69a",downColor:"#ef5350",wickVisible:!0,borderVisible:!0,borderColor:"#378658",borderUpColor:"#26a69a",borderDownColor:"#ef5350",wickColor:"#737375",wickUpColor:"#26a69a",wickDownColor:"#ef5350"},Kn={upColor:"#26a69a",downColor:"#ef5350",openVisible:!0,thinBars:!0},$n={color:"#2196f3",lineStyle:0,lineWidth:3,lineType:0,crosshairMarkerVisible:!0,crosshairMarkerRadius:4,crosshairMarkerBorderColor:"",crosshairMarkerBackgroundColor:""},Xn={topColor:"rgba( 46, 220, 135, 0.4)",bottomColor:"rgba( 40, 221, 100, 0)",lineColor:"#33D778",lineStyle:0,lineWidth:3,lineType:0,crosshairMarkerVisible:!0,crosshairMarkerRadius:4,crosshairMarkerBorderColor:"",crosshairMarkerBackgroundColor:""},Zn={color:"#26a69a",base:0},Jn={title:"",visible:!0,lastValueVisible:!0,priceLineVisible:!0,priceLineSource:0,priceLineWidth:1,priceLineColor:"",priceLineStyle:2,baseLineVisible:!0,baseLineWidth:1,baseLineColor:"#B2B5BE",baseLineStyle:0,priceFormat:{type:"price",precision:2,minMove:.01}},Gn=function(){function t(t,i){this.Nc=t,this.Bd=i}return t.prototype.applyOptions=function(t){this.Nc.ct().zl(this.Bd,t)},t.prototype.options=function(){return this.Qt().I()},t.prototype.width=function(){return Pt(this.Bd)?this.Nc.td("left"===this.Bd?"left":"right"):0},t.prototype.Qt=function(){return l(this.Nc.ct().Pl(this.Bd)).J},t}(),Qn=function(){function t(t){this.Ad=new Z,this.ir=new Z,this.ri=t,this.Vo().$r().Gi(this.Vd.bind(this)),this.Vo().Xr().Gi(this.Od.bind(this))}return t.prototype.un=function(){this.Vo().$r().sn(this),this.Vo().Xr().sn(this),this.Ad.un()},t.prototype.scrollPosition=function(){return this.Vo().Ir()},t.prototype.scrollToPosition=function(t,i){i?this.Vo().Kr(t,1e3):this.ri.wr(t)},t.prototype.scrollToRealTime=function(){this.Vo().Yr()},t.prototype.getVisibleRange=function(){var t,i,n=this.Vo().pr();return null===n?null:{from:null!==(t=n.from.Cs)&&void 0!==t?t:n.from.Ds,to:null!==(i=n.to.Cs)&&void 0!==i?i:n.to.Ds}},t.prototype.setVisibleRange=function(t){var i={from:An(t.from),to:An(t.to)},n=this.Vo().Sr(i);this.ri.ef(n)},t.prototype.getVisibleLogicalRange=function(){var t=this.Vo().gr();return null===t?null:{from:t.ss(),to:t.rs()}},t.prototype.setVisibleLogicalRange=function(t){a(t.from<=t.to,"The from index cannot be after the to index."),this.ri.ef(t)},t.prototype.resetTimeScale=function(){this.ri.xe()},t.prototype.fitContent=function(){this.ri.Gr()},t.prototype.logicalToCoordinate=function(t){var i=this.ri.q();return i.ii()?null:i.tt(t)},t.prototype.coordinateToLogical=function(t){var i=this.ri.q();return i.ii()?null:i.Vr(t)},t.prototype.timeToCoordinate=function(t){var i=An(t),n=this.ri.q(),h=n.Mr(i,!1);return null===h?null:n.tt(h)},t.prototype.coordinateToTime=function(t){var i,n=this.ri.q(),h=n.Vr(t),s=n.ei(h);return null===s?null:null!==(i=s.Cs)&&void 0!==i?i:s.Ds},t.prototype.subscribeVisibleTimeRangeChange=function(t){this.Ad.Gi(t)},t.prototype.unsubscribeVisibleTimeRangeChange=function(t){this.Ad.hn(t)},t.prototype.subscribeVisibleLogicalRangeChange=function(t){this.ir.Gi(t)},t.prototype.unsubscribeVisibleLogicalRangeChange=function(t){this.ir.hn(t)},t.prototype.applyOptions=function(t){this.Vo().rh(t)},t.prototype.options=function(){return M(this.Vo().I())},t.prototype.Vo=function(){return this.ri.q()},t.prototype.Vd=function(){this.Ad.en()&&this.Ad.rn(this.getVisibleRange())},t.prototype.Od=function(){this.ir.en()&&this.ir.rn(this.getVisibleLogicalRange())},t}();function th(t){if(void 0!==t&&"custom"!==t.type){var i=t;void 0!==i.minMove&&void 0===i.precision&&(i.precision=function(t){if(t>=1)return 0;for(var i=0;i<8;i++){var n=Math.round(t);if(Math.abs(n-t)<1e-8)return i;t*=10}return i}(i.minMove))}}function ih(t){return function(t){if(w(t.handleScale)){var i=t.handleScale;t.handleScale={axisDoubleClickReset:i,axisPressedMouseMove:{time:i,price:i},mouseWheel:i,pinch:i}}else if(void 0!==t.handleScale&&w(t.handleScale.axisPressedMouseMove)){var n=t.handleScale.axisPressedMouseMove;t.handleScale.axisPressedMouseMove={time:n,price:n}}var h=t.handleScroll;w(h)&&(t.handleScroll={horzTouchDrag:h,vertTouchDrag:h,mouseWheel:h,pressedMouseMove:h})}(t),function(t){if(t.priceScale){t.leftPriceScale=t.leftPriceScale||{},t.rightPriceScale=t.rightPriceScale||{};var i=t.priceScale.position;delete t.priceScale.position,t.leftPriceScale=c(t.leftPriceScale,t.priceScale),t.rightPriceScale=c(t.rightPriceScale,t.priceScale),"left"===i&&(t.leftPriceScale.visible=!0,t.rightPriceScale.visible=!1),"right"===i&&(t.leftPriceScale.visible=!1,t.rightPriceScale.visible=!0),"none"===i&&(t.leftPriceScale.visible=!1,t.rightPriceScale.visible=!1),t.overlayPriceScales=t.overlayPriceScales||{},void 0!==t.priceScale.invertScale&&(t.overlayPriceScales.invertScale=t.priceScale.invertScale),void 0!==t.priceScale.scaleMargins&&(t.overlayPriceScales.scaleMargins=t.priceScale.scaleMargins)}}(t),t}var nh=function(){function t(t,i){var n=this;this.zd=new Pn,this.Pd=new Map,this.Fd=new Map,this.Id=new Z,this.Wd=new Z;var h=void 0===i?M(Hn):c(M(Hn),ih(i));this.Nc=new bn(t,h),this.Nc.t_().Gi((function(t){n.Id.en()&&n.Id.rn(n.Rd(t()))}),this),this.Nc.Rl().Gi((function(t){n.Wd.en()&&n.Wd.rn(n.Rd(t()))}),this);var s=this.Nc.ct();this.jd=new Qn(s)}return t.prototype.remove=function(){this.Nc.t_().sn(this),this.Nc.Rl().sn(this),this.jd.un(),this.Nc.un(),this.Pd.clear(),this.Fd.clear(),this.Id.un(),this.Wd.un(),this.zd.un()},t.prototype.resize=function(t,i,n){this.Nc.H_(t,i,n)},t.prototype.addAreaSeries=function(t){void 0===t&&(t={}),th((t=Wn(t)).priceFormat);var i=c(M(Jn),Xn,t),n=this.Nc.ct().hf("Area",i),h=new Rn(n,this,this);return this.Pd.set(h,n),this.Fd.set(n,h),h},t.prototype.addBarSeries=function(t){void 0===t&&(t={}),th((t=Wn(t)).priceFormat);var i=c(M(Jn),Kn,t),n=this.Nc.ct().hf("Bar",i),h=new Rn(n,this,this);return this.Pd.set(h,n),this.Fd.set(n,h),h},t.prototype.addCandlestickSeries=function(t){void 0===t&&(t={}),bt(t=Wn(t)),th(t.priceFormat);var i=c(M(Jn),Yn,t),n=this.Nc.ct().hf("Candlestick",i),h=new jn(n,this,this);return this.Pd.set(h,n),this.Fd.set(n,h),h},t.prototype.addHistogramSeries=function(t){void 0===t&&(t={}),th((t=Wn(t)).priceFormat);var i=c(M(Jn),Zn,t),n=this.Nc.ct().hf("Histogram",i),h=new Rn(n,this,this);return this.Pd.set(h,n),this.Fd.set(n,h),h},t.prototype.addLineSeries=function(t){void 0===t&&(t={}),th((t=Wn(t)).priceFormat);var i=c(M(Jn),$n,t),n=this.Nc.ct().hf("Line",i),h=new Rn(n,this,this);return this.Pd.set(h,n),this.Fd.set(n,h),h},t.prototype.removeSeries=function(t){var i=o(this.Pd.get(t)),n=this.zd.rf(i);this.Nc.ct().rf(i),this.Ud(n),this.Pd.delete(t),this.Fd.delete(i)},t.prototype.Ld=function(t,i){this.Ud(this.zd.Md(t,i))},t.prototype.ao=function(t,i){this.Ud(this.zd.pd(t,i))},t.prototype.subscribeClick=function(t){this.Id.Gi(t)},t.prototype.unsubscribeClick=function(t){this.Id.hn(t)},t.prototype.subscribeCrosshairMove=function(t){this.Wd.Gi(t)},t.prototype.unsubscribeCrosshairMove=function(t){this.Wd.hn(t)},t.prototype.priceScale=function(t){return void 0===t&&(t=this.Nc.ct().uf()),new Gn(this.Nc,t)},t.prototype.timeScale=function(){return this.jd},t.prototype.applyOptions=function(t){this.Nc.rh(ih(t))},t.prototype.options=function(){return this.Nc.I()},t.prototype.takeScreenshot=function(){return this.Nc.J_()},t.prototype.Ud=function(t){var i=this.Nc.ct();i.if(t.q.Br,t.q.Cd),t.kd.forEach((function(t,i){return i.ao(t.Nd,t.El)})),i.zr()},t.prototype.qd=function(t){return o(this.Fd.get(t))},t.prototype.Rd=function(t){var i=this,n=new Map;t.ad.forEach((function(t,h){n.set(i.qd(h),t)}));var h=void 0===t.ud?void 0:this.qd(t.ud);return{time:t.P&&(t.P.Cs||t.P.Ds),point:t.ed,hoveredSeries:h,hoveredMarkerId:t.od,seriesPrices:n}},t}();var hh=Object.freeze({__proto__:null,version:function(){return"3.6.0-dev+202108221751"},get LineStyle(){return i},get LineType(){return t},get CrosshairMode(){return P},get PriceScaleMode(){return lt},get PriceLineSource(){return _t},get TickMarkType(){return Dt},isBusinessDay:Bt,isUTCTimestamp:At,createChart:function(t,i){var n;if(d(t)){var h=document.getElementById(t);a(null!==h,"Cannot find element in DOM with id="+t),n=h}else n=t;return new nh(n,i)}});window.LightweightCharts=hh}();
</script>
"""
        tpl += r"""
<script>
{{!candleData}}
{{!metrics}}
{{!orderData}}

const processData = (data, mapper) => data.split('\n').map(mapper);
let candleColorsEnabled = false; // By default, candlestick colors are not applied

const candleMapper = (row) => {
    const [time, open, high, low, close, volume, color, borderColor, wickColor] = row.split(',');
    const res = {
        time: time * 1,
        open: open * 1,
        high: high * 1,
        low: low * 1,
        close: close * 1
    };
    if (candleColorsEnabled && color.trim() && borderColor.trim() && wickColor.trim()) {
        res.color = color;
        res.borderColor = borderColor;
        res.wickColor = wickColor;
    }
    return res;
};

const volumeMapper = (row) => {
    const [time, , , , , volume] = row.split(',');
    return {
        time: time * 1,
        value: volume * 1
    };
};

const orderMapper = (row) => {
    const [time, mode, side, type, qty, price, pnl_order] = row.split(',');
    return {
        time: time * 1,
        position: side === 'sell' ? 'aboveBar' : 'belowBar',
        color: side === 'sell' ? 'rgba(251, 192, 45, 1)' : '#2196F3',
        shape: side === 'sell' ? 'arrowDown' : 'arrowUp',
        text: `${type} @ ${price} : ${qty}${mode} $${Math.round(pnl_order * 100) / 100}`
    };
};

const pnlMapper = (row) => {
    const [time, , , , , , , pnl_accumulated] = row.split(',');
    return {
        time: time * 1,
        value: pnl_accumulated * 1
    };
};

// Data processing with error handling
const getCandleData = async () => {
    try {
        return processData(candleData, candleMapper);
    } catch (error) {
        console.error("Error processing candle data:", error);
        throw new Error("Failed to process candle data.");
    }
};

const getVolumeData = async () => {
    try {
        return processData(candleData, volumeMapper);
    } catch (error) {
        console.error("Error processing volume data:", error);
        throw new Error("Failed to process volume data.");
    }
};

const getOrderData = async () => {
    try {
        return processData(orderData, orderMapper);
    } catch (error) {
        console.error("Error processing order data:", error);
        throw new Error("Failed to process order data.");
    }
};

const getPnlData = async () => {
    try {
        return processData(orderData, pnlMapper);
    } catch (error) {
        console.error("Error processing PnL data:", error);
        throw new Error("Failed to process PnL data.");
    }
};

const getCustomData = async (offset) => {
    try {
        const data = candleData.split('\n').map((row) => {
            const arr = row.split(',');
            return {
                time: arr[0] * 1,
                value: arr[offset + 9] * 1
            };
        });
        return data;
    } catch (error) {
        console.error("Error processing custom data:", error);
        throw new Error("Failed to process custom data.");
    }
};

    var chartWidth = window.innerWidth-20;
    var chartHeight = window.innerHeight-20;
    const displayChart = async () => {
      const chartProperties = {
        width: chartWidth,
        height: chartHeight,
        handleScale: {
            mouseWheel: true,
            pinch: true,
        },
        handleScroll: {
            mouseWheel: true,
            pressedMouseMove: true,
        },
        layout: {
          background: {color: '#FFFFFF'},
          textColor: '#000000',
        },
        grid: {
          vertLines: {
            color: 'transparent',
          },
          horzLines: {
            color: 'transparent',
          },
        }, rightPriceScale:
          {		visible: true,
              borderColor: 'rgba(197, 203, 206, 1)'	},
          leftPriceScale:
            { visible: true,
              borderColor: 'rgba(197, 203, 206, 1)'	},
        timeScale: {
          timeVisible: true,
          secondsVisible: true,
        },
        crosshair: {
            // Change mode from default 'magnet' to 'normal'.
            // Allows the crosshair to move freely without snapping to datapoints
            mode: LightweightCharts.CrosshairMode.Normal,

            // Vertical crosshair line (showing Date in Label)
            vertLine: {
                width: 6,
                color: '#C3BCDB44',
                style: LightweightCharts.LineStyle.Solid,
                labelBackgroundColor: '#9B7DFF',
            },

            // Horizontal crosshair line (showing Price in Label)
            horzLine: {
                color: '#9B7DFF',
                labelBackgroundColor: '#9B7DFF',
            },
        },
      };


      const domElement = document.getElementById('tvchart');
      const chart = LightweightCharts.createChart(domElement, chartProperties);
      const candleseries = chart.addCandlestickSeries();
      const klinedata = await getCandleData();
      candleseries.setData(klinedata);
      const odata = await getOrderData();
      candleseries.setMarkers(odata);

      const volumeSeries = chart.addHistogramSeries({
            color: 'rgba(4, 111, 232, 0.2)',
            priceFormat: {
                type: 'volume',
            },
            priceScaleId: 'volume',
            scaleMargins: {
                top: 0.7,
                bottom: 0,
            },
        });
      const vdata = await getVolumeData();
      volumeSeries.priceScale().applyOptions({
        scaleMargins: {
            top: 0.7, // highest point of the series will be 70% away from the top
            bottom: 0,
        },
    });
      volumeSeries.setData(vdata);

    {{!customCharts}}
  
      const pnl = chart.addLineSeries({color: 'rgba(93, 147, 187, 0.8)', lineWidth: 1, priceScaleId: 'left',})
      const pnl_data = await getPnlData()
      pnl.setData(pnl_data)

      //chart.timeScale().fitContent();

        //chart.timeScale().scrollToPosition(-20, false);

      // Create a button with common attributes
      function createNavigationButton(className, innerSVG, leftOffset, clickCallback) {
          const button = document.createElement('div');
          button.className = className;
          button.id = "navi-button"
          button.style.color = '#4c525e';
          button.innerHTML = innerSVG;

          button.addEventListener('click', clickCallback);

          button.addEventListener('mouseover', function() {
              button.style.background = 'rgba(250, 250, 250, 1)';
              button.style.color = '#000';
          });

          button.addEventListener('mouseout', function() {
              button.style.background = 'rgba(250, 250, 250, 0.6)';
              button.style.color = '#4c525e';
          });

          document.body.appendChild(button);
          return button;
      }

      const timeScale = chart.timeScale();

      // Button to go to the real time (end of the chart)
      const endButtonSVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14" width="14" height="14"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-width="2" d="M6.5 1.5l5 5.5-5 5.5M3 4l2.5 3L3 10"></path></svg>';
      const endButton = createNavigationButton('go-to-realtime-button', endButtonSVG, 60, () => {
          timeScale.scrollToRealTime();
      });

      // Button to go to the beginning of the chart
      const startButtonSVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14" width="14" height="14"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-width="2" d="M7.5 12.5l-5 -5.5 5 -5.5M11 10l-2.5 -3L11 4"></path></svg>';
      const startButton = createNavigationButton('go-to-beginning-button', startButtonSVG, 825, () => {
          timeScale.scrollToPosition(-(klinedata.length), true);
      });
        // Update the button positioning logic
        function updateButtonPositions() {
            chartWidth = window.innerWidth - 20;
            chartHeight = window.innerHeight - 20;

            startButton.style.left = '80px'; // Fixed position from left
            startButton.style.top = (chartHeight - 27 - 30) + 'px';

            endButton.style.right = '95px'; // Fixed position from right
            endButton.style.left = 'auto'; // Reset the left position in case it's set
            endButton.style.top = (chartHeight - 27 - 30) + 'px';
        }
        // Attach the resize event listener
        window.addEventListener('resize', updateButtonPositions);

        // Call the updateButtonPositions function to set initial positions
        updateButtonPositions();



      timeScale.subscribeVisibleTimeRangeChange(function() {
          const buttonVisible = timeScale.scrollPosition() < 0;
          endButton.style.display = buttonVisible ? 'block' : 'none';
          startButton.style.display = 'block';
      });

        // other functions:
      const dayProperties = {
      layout: {
        background: {color: '#FFFFFF'}, // White background for day mode
        textColor: '#000000',
      }};

      const nightProperties = {
      layout: {
        background: {color: '#000000'}, // Black background for night mode
        textColor: '#FFFFFF',
      }};


      // Tool Tip
      let symbolName = document.title.split('-')
      symbolName = symbolName[0] + ' ' + symbolName[1] + ' ' + symbolName[2]
      + '-' + symbolName[3] + ' ' + symbolName[4];
      const container = document.getElementById('tvchart');

      const legend = document.createElement('div');
      legend.style = `position: absolute; left: 8%; top: 0.5%; z-index: 6; font-size: 14px; font-family: sans-serif; line-height: 18px; font-weight: 300;`;
      legend.style.color = 'black';
      container.appendChild(legend);

      const getLastBar = series => {
        return series.dataByIndex(-1);
      };

      const getMostRecentPnlBeforeTime = (pnl_data, timestamp) => {
      for (let i = pnl_data.length - 1; i >= 0; i--) {
          if (pnl_data[i].time <= timestamp) {
              return pnl_data[i];
          }
      }
      return null;  // Return null if no such element is found
      };
      const symbol = document.title.split('-')[2];
      const setTooltipHtml = (name, date, open,close,high,low,volume,color,pnl,pnl_color,pnlicon) => {

        legend.innerHTML =
        `
          <div style="font-size: 19px; margin: 7px 0px 6px 0px;">
          ${name}</div>
          <div style="font-size: 16px; margin: 8px 0px;">
            O <span style="color: ${color};">${open}</span>
            H <span style="color: ${color};">${high}</span>
            L <span style="color: ${color};">${low}</span>
            C <span style="color: ${color};">${close}</span>
          </div>
          <div style="margin:8px 0px;">${date}</div>
          <div  style="margin:8px 0px;"><strong>Volume:</strong> ${volume} ${symbol}</div>
          <div><strong>PnL:</strong>
            <span style="color: ${pnl_color};">${pnl} </span> <i class="fas fa-palette" id="pnlIcon" style="margin-left: 3px;"></i>
            <input id="pnlColorPicker" class="jscolor" data-jscolor="{}" value="FF0000" style="display:none;">
            <button id="togglePnlVisibility"><i class="${pnlicon}"></i></button>
           </div>

        `;
      };

      const updateLegend = param => {
        const validCrosshairPoint = !(
        param === undefined || param.time === undefined || param.point.x < 0 || param.point.y < 0
        );

        const bar = validCrosshairPoint ? param.seriesData.get(candleseries) : getLastBar(candleseries);
        // time is in the same format that you supplied to the setData method,
        // which in this case is YYYY-MM-DD
        var time = new Date(bar.time*1000);

        time = time.toLocaleString() + ' EST';
        const volume = validCrosshairPoint ? param.seriesData.get(volumeSeries) : getLastBar(volumeSeries);
        const volume_value = volume.value.toFixed(1);
        const color = bar.close > bar.open ? 'green' : 'red'; // Determine color based on close and open prices
        const mostRecentPnl = getMostRecentPnlBeforeTime(pnl_data, bar.time);
        const pnl_value = mostRecentPnl ? mostRecentPnl.value.toFixed(1) : "N/A";
        const pnl_color = pnl_value > 0 ? 'green' : 'red';
        if (pnlVisible){
          pnl_icon = 'fas fa-eye'
        } else {
          pnl_icon = 'fas fa-eye-slash'
        }
        setTooltipHtml(symbolName, time, bar.open.toFixed(1),
        bar.close.toFixed(1),bar.high.toFixed(1),
        bar.low.toFixed(1), volume_value,color,pnl_value,pnl_color,pnl_icon);
        //const markerInfo = odata.find((marker) => marker.time === bar.time);

      };

      chart.subscribeCrosshairMove(updateLegend);

      let pnlVisible = true;
      document.body.addEventListener('click', function(event) {
      if (event.target.matches('#pnlIcon')) {
          jscolor.install();
          const pnlColorPicker = document.getElementById('pnlColorPicker');
          pnlColorPicker.jscolor.show();
          pnlColorPicker.onchange = function() {
              const newColor = this.jscolor.toRGBString();
              pnl.applyOptions({ color: newColor }); // Change the color of the PnL plot
              localStorage.setItem('pnlColor', newColor); // Save the color in local storage
          };
         }
      else     if (event.target.matches('#togglePnlVisibility') || event.target.closest('#togglePnlVisibility')) {
    pnlVisible = !pnlVisible;  // Toggle the visibility state
    pnl.applyOptions({ visible: pnlVisible });  // Set the visibility of the pnl series
          }
      });

      document.getElementById('toggleCandleColors').addEventListener('click', async function() {
          candleColorsEnabled = !candleColorsEnabled; // Toggle the state
          const klinedata = await getCandleData(); // Fetch the updated candle data
          candleseries.setData(klinedata); // Update the chart with the new data
      });


      let isNightMode = false; // Default to day mode
      document.getElementById('toggleNightMode').addEventListener('click', function() {
        const dn_iconElement = this.querySelector('i');
        if (isNightMode) {
          chart.applyOptions(dayProperties); // Apply day mode
          // Optionally, change other UI elements for day mode
          legend.style.color = 'black'
          document.getElementById('main-body').style.backgroundColor = '#FFFFFF'
          volumeSeries.applyOptions({color: 'rgba(4, 111, 232, 0.2)'})
          dn_iconElement.className = 'fas fa-moon';
        } else {
          chart.applyOptions(nightProperties); // Apply night mode
          // Optionally, change other UI elements for night mode
          legend.style.color = 'white';
          document.getElementById('main-body').style.backgroundColor = '#000000'
          volumeSeries.applyOptions({color: 'rgba(122, 168, 228, 0.55)' });
          dn_iconElement.className = 'fas fa-sun';
        }
        isNightMode = !isNightMode; // Toggle the mode
      });

        document.getElementById('resetScales').addEventListener('click', function() {
        const rightPriceScale = chart.priceScale('right');
        const leftPriceScale = chart.priceScale('left');
        chart.applyOptions({
          rightPriceScale: {autoScale: true},
          leftPriceScale: {autoScale: true}
        });

    });

      document.getElementById('toggleUtilityBox').addEventListener('click', function() {
        const utilityBox = document.getElementById('utilityBox');
        if (utilityBox.style.display === 'none' || utilityBox.style.display === '') {
            utilityBox.style.display = 'block';
        } else {
            utilityBox.style.display = 'none';
        }
    });


    document.addEventListener('keydown', function(event) {
    const timeScale = chart.timeScale();
    const currentPosition = timeScale.scrollPosition();
    const currentRange = timeScale.getVisibleLogicalRange();
    const rangeLength = currentRange.to - currentRange.from;
    const zoomFactor = 0.2;
    let newRangeLength;

    switch(event.code) {
        // Left arrow key
        case 'ArrowLeft':
            timeScale.scrollToPosition(currentPosition - 1000, false);
            return;  // Exit the function early after handling the arrow key

        // Right arrow key
        case 'ArrowRight':
            timeScale.scrollToPosition(currentPosition + 1000, false);
            return;  // Exit the function early after handling the arrow key

        case 'Equal':  // This corresponds to the "+" key
            newRangeLength = rangeLength * (1 - zoomFactor);
            break;

        case 'Minus':  // This corresponds to the "-" key
            newRangeLength = rangeLength * (1 + zoomFactor);
            break;

        default:
            return;  // If any other key is pressed, exit the function early
    }

      const newFrom = currentRange.from + (rangeLength - newRangeLength) / 2;
      const newTo = newFrom + newRangeLength;

      timeScale.setVisibleLogicalRange({
          from: newFrom,
          to: newTo
      });
  });

    // Event Listener for Reset Button
    document.getElementById('resetButton').addEventListener('click', function() {
        localStorage.clear();  // Clear local storage
        location.reload();    // Refresh the page
    });

// Step 1: Refactor the Tippy initialization into a separate function
function initializeTippy() {
    tippy('#utilityBox button i, #utilityBox div svg', {
        content: function(reference) {
            let parent = reference.parentElement;
            switch(parent.id || parent.parentElement.id) {
                case 'toggleNightMode':
                  return isNightMode ? 'Day Mode' : 'Night Mode';
                case 'resetScales':
                    return 'Reset Y-Axis Scales';
                case 'resetButton':
                    return 'Reset Settings';
                case 'toggleCandleColors':
                    return candleColorsEnabled ? 'Default Candle Colors' : 'PVRSA Candle Colors';
                default:
                    return ''; // default tooltip content
            }
        },
        interactive: false,
        placement: 'left',
        arrow: true,
        delay: [50, 25],
        animation: 'scale'
    });
}

// Step 2: Use the function in the DOMContentLoaded event
document.addEventListener('DOMContentLoaded', function() {
    initializeTippy();

    // Step 3: Attach click event listeners to the utility buttons
    let utilityButtons = document.querySelectorAll('#utilityBox button, #utilityBox div');
    utilityButtons.forEach(button => {
        button.addEventListener('click', initializeTippy);
    });
});


    function updateWindowSize() {
        chartWidth = window.innerWidth-20;
        chartHeight = window.innerHeight-20;
      chart.applyOptions({     width: chartWidth,    height: chartHeight, });

    }

      window.onresize = updateWindowSize;

        // populate data from localstorage
        const savedPnlColor = localStorage.getItem('pnlColor');
        if (savedPnlColor) {
        // If there's a saved color in local storage, apply it
        pnl.applyOptions({ color: savedPnlColor });
       }
    };


    displayChart();
  </script>
</html>
      
        """

        # if('mainChartLines' in customData and len(customData['mainChartLines'])>0):
        #   for key, value in customData['mainChartLines'].items():
        #   #   candles += [value]
        #     for idx, item in enumerate(candles):
        #       item = np.append(item, value[idx])
        
        
        

        pvsraData = pvsra(candles, True)

        candleDataList = []

        for idx, candle in enumerate(candles):
            # Extract commonly used data
            current_date = str(candle[CD.date] / 1000)
            current_open = str(candle[CD.open])
            current_high = str(candle[CD.high])
            current_low = str(candle[CD.low])
            current_close = str(candle[CD.close])
            current_volume = str(candle[CD.volume])


            color_data = [',gray,gray,gray,']  # default
            if pvsraData['climaxBullVolume'].iloc[idx] == 1:
                color_data = [',lime,lime,white,']
            elif pvsraData['climaxBearVolume'].iloc[idx] == 1:
                color_data = [',red,red,gray,']
            elif pvsraData['risingBullVolume'].iloc[idx] == 1:
                color_data = [',blue,blue,white,']
            elif pvsraData['risingBearVolume'].iloc[idx] == 1:
                color_data = [',fuchsia,fuchsia,gray,']
            elif pvsraData['isBull'].iloc[idx] == 1:
                color_data = [',silver,silver,gray,']


            custom_data_list = []
            if customData:
                for key, value in customData.items():
                    if len(value['data']) > idx:
                        custom_data_list.append(f"{(value['data'][idx])}")
                    else:
                        custom_data_list.append("")

            # Build the complete candle data string
            candleDataList.append(
                f"{current_date},{current_open},{current_high},{current_low},{current_close},{current_volume}"
                f"{''.join(color_data)}"
                f"{','.join(custom_data_list)}"
            )

        # Join all the candle data strings
        candleData = '\n'.join(candleDataList)
        candleData = f'const candleData = `{candleData}`'

        if candleData[-1] == '\n':
            candleData = candleData[:-1]  # remove last new line
        candleData += ';'

        pnl_accumulated = 0
        orderDataList = ['const orderData = `']

        # Extract common configuration once
        config_prefix = 'env.exchanges.'
        trades = store.completed_trades.trades

        for trade in trades:
            trading_fee = jh.get_config(f'{config_prefix}{trade.exchange}.fee')
            average_entry_price = 0
            average_entry_size = 0
            side_factor = 1 if trade.type != trade_types.SHORT else -1

            for order in trade.orders:
                if not order.is_executed:
                    continue

                fee = abs(order.qty) * order.price * trading_fee
                is_buy_for_long = trade.type == trade_types.LONG and order.side == 'buy'
                is_sell_for_short = trade.type == trade_types.SHORT and order.side == 'sell'

                if is_buy_for_long or is_sell_for_short:
                    pnl_order = -fee
                    total_price = average_entry_price * average_entry_size + order.price * abs(order.qty)
                    total_qty = average_entry_size + abs(order.qty)
                    average_entry_price = total_price / total_qty
                    average_entry_size = total_qty
                else:
                    pnl_order = (order.price - average_entry_price) * abs(order.qty) * side_factor - fee
                    average_entry_size -= abs(order.qty)

                pnl_accumulated += pnl_order

                mode = ''
                if order.is_stop_loss:
                    mode = ' (SL)'
                elif order.is_take_profit:
                    mode = ' (TP)'

                orderDataList.append(f"{order.executed_at/1000},{mode},{order.side},{order.type},{order.qty},{order.price},{pnl_order},{pnl_accumulated},{trade.id}\n")

        # Join list to form the final string
        orderData = ''.join(orderDataList).rstrip('\n') + '`;'

        customCharts=''
        if(len(customData)>0):
              idx = 0
              for key, value in customData.items():
                if(not 'options' in value):
                  value['options'] = {}
                value['options']['title'] = key
                if(not 'type' in value):
                  value['type']='LineSeries'
                customCharts += template(cstLineTpl, {'options':str(value['options']), 'offset':idx, 'type':value['type']})
                idx += 1
        
        pnlCharts = ''
        priceScale = ''
        pnlCharts = 'chart.addLineSeries({color: \'rgba(4, 111, 232, 1)\', lineWidth: 1, priceScaleId: \'left\',}).setData(await getPnlData())'
        priceScale = ' rightPriceScale: {		visible: true, borderColor: \'rgba(197, 203, 206, 1)\'	}, leftPriceScale: { visible: true, borderColor: \'rgba(197, 203, 206, 1)\'	},'

        info = {'title': studyname,
            'candleData': candleData,
            'orderData': orderData,
            'customCharts':customCharts,
            'pnlCharts':pnlCharts,
            'priceScale': priceScale,
            'metrics': metrics_json
            }
            
        result = template(tpl, info)

        filename = "storage/JesseTradingViewLightReport/" + file_name + '.html'
        if new_path:
            filename= new_path + file_name + ' Interactive Chart .html'
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with codecs.open(filename, "w", "utf-8") as f:
            f.write(result)
            
        if not new_path:
            import webbrowser
            url = f'C:/Python39/Algotrading/{filename}'
            webbrowser.open(url, new=2)  # open in new tab
        else:
            return filename
