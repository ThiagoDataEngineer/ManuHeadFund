import json

with open('btcusd_bitstamp_1day.json') as f:
    data = json.load(f)
    print(f'Total candles: {len(data)}')
    if data:
        print(f'First: {json.dumps(data[0], indent=2)}')
        print(f'Last: {json.dumps(data[-1], indent=2)}')
