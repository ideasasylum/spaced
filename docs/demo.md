# Moving the bakery's ordering system

This proposal replaces the paper order book with a shared tablet at the counter. It affects everyone who takes orders, so please read the whole thing. The change happens over one quiet week in January.

## Why change

We lost eleven orders in December because pages were torn out or misread. Two of those were wedding cakes. A shared screen means the kitchen and the counter always see the same list.

- Orders are visible to the kitchen the moment they are taken
- Nothing is lost when someone goes off shift
  - The night baker can see tomorrow's list before leaving
- [x] Tablet and stand have arrived
- [ ] Everyone has had a practice session

## The plan

1. Run paper and tablet side by side for three days
2. Check each evening that the two lists match
3. Retire the paper book on Friday

### Who does what

| Task | Owner | When |
| --- | --- | --- |
| Set up the tablet and accounts | Priya | Monday |
| Practice sessions for counter staff | Tom | Tuesday and Wednesday |
| Nightly comparison of both lists | Whoever closes | Monday to Thursday |
| Decide whether to retire the book | Priya and Tom | Friday morning |

### How an order is stored

Each order is one small record. The kitchen screen only shows orders that are not yet collected.

```ruby
class Order
  attr_reader :customer, :items, :collect_at

  def ready_for_kitchen?
    !collected && collect_at > Time.now
  end
end
```

```json
{"customer": "Mrs Okafor", "items": ["sourdough", "6 scones"], "collect_at": "2027-01-14T09:30"}
```

## Risks

> The last time we changed the till, nobody was shown how to do a refund and we found out on a Saturday.

The main risk is that people keep using paper out of habit. The second is the tablet running out of charge. Both are cheap to prevent if we decide who is responsible before the week starts.

## What we need from you

Tell Priya by Friday whether the January week works for your shifts. Say which practice session you can make. Raise anything that worries you now, not on the day.
