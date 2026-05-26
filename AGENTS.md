# Engulfing Fibo Project Context

This project contains a TradingView Pine indicator and an MT5 Expert Advisor for the same engulfing 0.5 fib setup strategy.

## Main Files

- `engulfing_fib_setup_tracker.pine` - TradingView indicator named `MBA Pacman`.
- `MBA Pacman.mq5` - MT5 Expert Advisor source.
- `MBA Pacman.ex5` - compiled MT5 Expert Advisor.
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
- same-color setup default multiplier is 4.0 in the TradingView indicator.

## Important Current Defaults

- `requireOppositeColor`: false.
- regular size multiplier: 2.0.
- same-color size multiplier: 4.0.
- entry fib: 0.5.
- RR target: 2.0.
- break-even disabled by default; if enabled, it triggers at 85% of the way to TP.
- pending invalidation default: close beyond TP.
- ATR filter exists in the indicator, uses the full setup candle range including both wicks, uses length 8 by default, and is off by default unless enabled manually.
- close wick filter exists but is off by default unless enabled manually.
- the TradingView indicator no longer has a trend filter or configuration dashboard.

## Trend Filters

The TradingView indicator has no trend filter.

EA:
- no longer exposes trend filter settings, matching the TradingView indicator.
- can show a manual chart panel with Risk $, calculated lot size, last setup details, and buttons to place the setup limit order or enter now.
- automatic order placement is intended only for Strategy Tester; when attached to a normal chart, orders should be placed manually from the panel.

## Non-Repaint / Alerts

TradingView setups and alerts should only fire after candle close using confirmed bars.

The indicator has options to show filtered-out setups. Filtered setups:
- still show a yellow `B` or `S` label;
- are shown by default;
- include a short reason such as `ATR` or `Knot`;
- include the actual multiple, such as `x1.87`, when a setup is filtered only because its size is up to 0.2 below the required multiplier;
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
$compileArg = '/compile:"C:\Users\padma\Documents\Engulfing Fibo\MBA Pacman.mq5"'
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
