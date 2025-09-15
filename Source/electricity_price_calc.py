#!/usr/bin/env python3
import argparse
import sys

# Default tariffs in CHF per kWh
DEFAULT_HIGH_RATE = 0.3173  # peak (06:00-22:00)
DEFAULT_LOW_RATE = 0.1994   # off-peak (22:00-06:00)
HIGH_HOUR_START = 6
HIGH_HOUR_END = 22  # exclusive -> hours 6..21 are peak

HOURS_PER_DAY = 24
DAYS_PER_YEAR = 365


def parse_watt(value: str) -> float:
    try:
        return float(value)
    except ValueError:
        # try to strip trailing 'W' or 'w'
        s = value.strip()
        if s.lower().endswith("w"):
            try:
                return float(s[:-1])
            except ValueError:
                pass
        raise argparse.ArgumentTypeError(f"invalid wattage: {value}")


def yearly_kwh_from_watt(watt: float, days: int = DAYS_PER_YEAR) -> float:
    return watt * HOURS_PER_DAY * days / 1000.0


def split_yearly_kwh(watt: float, days: int = DAYS_PER_YEAR):
    peak_hours_per_day = len(range(HIGH_HOUR_START, HIGH_HOUR_END))
    offpeak_hours_per_day = HOURS_PER_DAY - peak_hours_per_day
    peak_kwh = watt * peak_hours_per_day * days / 1000.0
    offpeak_kwh = watt * offpeak_hours_per_day * days / 1000.0
    return peak_kwh, offpeak_kwh


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    p = argparse.ArgumentParser(description="Calculate yearly kWh and CHF cost for a device running 24/7.")
    p.add_argument("watt", type=parse_watt, help="Device power in watts (e.g. 65 or 65W)")
    p.add_argument("--high", type=float, default=DEFAULT_HIGH_RATE,
                   help=f"Peak tariff in CHF/kWh (default {DEFAULT_HIGH_RATE})")
    p.add_argument("--low", type=float, default=DEFAULT_LOW_RATE,
                   help=f"Off-peak tariff in CHF/kWh (default {DEFAULT_LOW_RATE})")
    p.add_argument("--days", type=int, default=DAYS_PER_YEAR,
                   help=f"Days per year to use for calculation (default {DAYS_PER_YEAR})")
    args = p.parse_args(argv)

    if args.watt <= 0:
        p.error("watt must be positive")

    peak_kwh, offpeak_kwh = split_yearly_kwh(args.watt, days=args.days)
    total_kwh = peak_kwh + offpeak_kwh
    cost = peak_kwh * args.high + offpeak_kwh * args.low

    print(f"Device: {args.watt:g} W (running 24/7)")
    print(f"Year length: {args.days} days")
    print(f"Yearly energy: {total_kwh:.2f} kWh")
    print(f"  Peak (hours {HIGH_HOUR_START}:00-{HIGH_HOUR_END}:00): {peak_kwh:.2f} kWh @ {args.high:.4f} CHF/kWh")
    print(f"  Off-peak: {offpeak_kwh:.2f} kWh @ {args.low:.4f} CHF/kWh")
    print(f"Yearly cost: CHF {cost:.2f}")


if __name__ == "__main__":
    main()