This is a maintained modified version of the Jesse backtesting framework. Created with the intention of maximizing backtesting speed and introducing support for stock and forex backtesting/optimization.

 Built-in methods were added for pregenerating candles and precalculating indicators to improve speed wihtout affecting accuracy. If the indicators are precalculated then the last candle close is used for higher timeframe indicator calculations rather than the current partially formed candle. It's possible to backtest stocks, forex, and cryptocurrency concurrently if the indicators are precalculated and the candles are not pregenerated. 

## New Features

* Stock backtesting/optimization 
* Forex backtesting/optimization
* Optional indicator precalculation w/o candle preloading
* Monte Carlo Simulation
* Significantly improved backtest simulation speed
* Polygon.io stock and forex candle importing driver

## Removed Features

* live trading

## Installation 

First, install the necessary python packages listed in the "requirements.txt" via the pip package manager. Then execute the cythonize.py script in the root of where you downloaded this repository. Copy the "jesse" folder and place it where you downloaded the origional Jesse repository. 


## Benchmark

Iteration times for multiple timeframes were recorded for a backtest using the example [SMACrossover](https://github.com/jesse-ai/example-strategies/blob/master/SMACrossover/__init__.py) strategy on the Bitfinex exchange with the BTC-USD pair from 2018-01-01 - 2023-09-01
##### Original 

```bash
3m : 96.39 seconds 
5m : 77.32 seconds
15m : 61.08 seconds
30m : 57.41 seconds
45m : 56.57 seconds
1h : 54.30 seconds
2h : 53.50 seconds
3h : 52.93 seconds
4h : 52.23 seconds
```

##### Optimized (Without Indicator Precalculation)

```bash
3m : 15.14 seconds 
5m : 9.06 seconds
15m : 3.13 seconds
30m : 1.65 seconds
45m : 1.14 seconds
1h : 0.89 seconds 
2h : 0.52 seconds
3h : 0.40 seconds
4h : 0.34 seconds
```

##### Optimized (With Indicator Precalculation and Preloaded Candles)

```bash
3m : 3.62 seconds 
5m : 2.21 seconds
15m : 0.79 seconds 
30m : 0.44 seconds
45m : 0.35 seconds
1h : 0.28 seconds
2h : 0.18 seconds
3h : 0.15 seconds
4h : 0.13 seconds
```

## Acknowledgements

 - [Jesse](https://github.com/jesse-ai/jesse)