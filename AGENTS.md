# Engulfing Fibo Project Context

This project contains a TradingView Pine indicator and an MT5 Expert Advisor for the same engulfing 0.5 fib setup strategy.

## Main Files

- `engulfing_fib_setup_tracker.pine` - TradingView indicator.
- `EngulfingFibSetupEA.mq5` - MT5 Expert Advisor source.
- `EngulfingFibSetupEA.ex5` - compiled MT5 Expert Advisor.
- `.set` files - MT5 Strategy Tester presets.
- `ReportTester*.html/png` and `20260501_last_run_with_diagnostics.log` - tester reports/debug artifacts used during development.

## Strategy Summary

The strategy works on the 15 minute timeframe.

It detects bullish and bearish engulfing setups, then draws the setup range and enters from the configured fib level, usually 0.5.

For a bullish setup:
- the entry is a long limit at the configured fib retracement;
- fib range uses the lowest low and highest high of the two setup candles;
- SL is at the lower extreme of the setup;
- TP is based on configured R multiple.

For a bearish setup:
- the entry is a short limit at the configured fib retracement;
- fib range uses the highest high and lowest low of the two setup candles;
- SL is at the upper extreme of the setup;
- TP is based on configured R multiple.

Setup detection currently uses body engulfing logic with a gap tolerance based on the close-open gap capped by ATR percentage.

Size comparison:
- engulfing candle size uses only the body;
- opposite-color setups use the regular size multiplier;
- same-color setups use the separate same-color multiplier;
- same-color setup default multiplier is 3.0 in the TradingView indicator.

## Important Current Defaults

- `requireOppositeColor`: false.
- regular size multiplier: 2.0.
- same-color size multiplier: 3.0.
- entry fib: 0.5.
- RR target: 2.0.
- break-even enabled at 85% of the way to TP.
- pending invalidation default: close beyond TP.
- ATR filter exists but is off by default in the indicator unless enabled manually.
- close wick filter exists but is off by default unless enabled manually.
- trend filter exists but is off by default unless enabled manually.

## Trend Filters

The project has multiple trend filter options.

TradingView indicator:
- EMA mode, using fast/slow EMA defaults 9 and 21.
- LuxAlgo-style Supertrend AI mode.
- TTD 5m+15m+1h alignment mode.

TradingView TTD logic:
- long allowed only when 5m, 15m, and 1h are all up;
- short allowed only when 5m, 15m, and 1h are all down;
- 1h uses the last closed H1 candle to avoid repainting.

EA:
- includes EMA trend filter;
- includes LuxAlgo-style Supertrend AI filter;
- includes TTD M15+H1 alignment filter.

EA TTD logic:
- long allowed only when M15 and H1 are both up;
- short allowed only when M15 and H1 are both down.

## Non-Repaint / Alerts

TradingView setups and alerts should only fire after candle close using confirmed bars.

The indicator has options to show filtered-out setups. Filtered setups:
- still show a yellow `B` or `S` label;
- include a short reason such as `Trend`, `ATR`, or `Knot`;
- do not trigger normal setup alerts;
- can trigger separate filtered setup alerts if enabled.

## MT5 EA Notes

The EA should place pending limit orders immediately after a valid pattern is detected.

Position sizing supports fixed lot and dollar-risk based lot calculation.

Order comments and journal logs should include the setup candle date/time so tester results can be matched back to the setup candle.

When using real tick data, same-candle TP/SL assumptions matter less than OHLC-only backtesting, but the settings still exist for non-tick modeling.

## Compilation

Compile the EA with MetaEditor. On this machine the command previously used was:

```powershell
$compileArg = '/compile:"C:\Users\padma\Documents\Engulfing Fibo\EngulfingFibSetupEA.mq5"'
$logArg = '/log:"C:\Users\padma\Documents\Engulfing Fibo\metaeditor-engulfing-ea.log"'
$p = Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList $compileArg,$logArg -Wait -PassThru -WindowStyle Hidden
$p.ExitCode
```

Always inspect `metaeditor-engulfing-ea.log`; MetaEditor may return a non-zero exit code even when compilation succeeds.

## Development Preferences

- Keep Pine and EA logic aligned when changing strategy rules.
- Prefer adding explicit inputs instead of hardcoding strategy behavior.
- Preserve Polish UI labels in the indicator and EA settings.
- Do not remove existing tester reports or diagnostics unless explicitly asked.
- Avoid committing credentials, account numbers, or broker login data.
