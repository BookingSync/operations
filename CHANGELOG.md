# Changelog

## [0.7.0](https://github.com/BookingSync/operations/tree/main)

### Added

- Implement new forms system detaching it from operations [\#47](https://github.com/BookingSync/operations/pull/47) ([pyromaniac](https://github.com/pyromaniac))

### Improvements

- Better inspect for all the opjects [\#45](https://github.com/BookingSync/operations/pull/45) ([pyromaniac](https://github.com/pyromaniac))
- Use #to_hash instead of #as_json [\#44](https://github.com/BookingSync/operations/pull/44) ([pyromaniac](https://github.com/pyromaniac))

### Fixes

- In some cases, `Operation::Command#form_class` was evaluated before `form_base` was evaluated [\#41](https://github.com/BookingSync/operations/pull/41) ([pyromaniac](https://github.com/pyromaniac))

## [0.6.2]

### Added

- Support Rails 7.1 [\#40](https://github.com/BookingSync/operations/pull/40) ([pyromaniac](https://github.com/pyromaniac))
- Include `Dry::Monads[:result]` in Policies, Preconditions and Callbacks [\#39](https://github.com/BookingSync/operations/pull/39) ([ston1x](https://github.com/ston1x))
- Add `callback` method to `Operations::Convenience` [\#37](https://github.com/BookingSync/operations/pull/37) ([pyromaniac](https://github.com/pyromaniac))
- Ability to access operation result in callbacks [\#36](https://github.com/BookingSync/operations/pull/36) ([pyromaniac](https://github.com/pyromaniac))
- Introduce Command#merge [\#34](https://github.com/BookingSync/operations/pull/34) ([pyromaniac](https://github.com/pyromaniac))
