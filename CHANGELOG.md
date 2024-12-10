# Changelog

## [main](https://github.com/BookingSync/operations/tree/main)

### Added

- Allow receiving params in preconditions. [\#56](https://github.com/BookingSync/operations/pull/56) ([pyromaniac](https://github.com/pyromaniac))

### Changes

- Changed `Operations::Command::OperationFailed#message` to include detailed error messages. [\#55](https://github.com/BookingSync/operations/pull/55) ([Azdaroth](https://github.com/Azdaroth))
- Rename Operations::Form#model_name parameter to param_key and make it public preserving backwards compatibility. [\#52](https://github.com/BookingSync/operations/pull/52) ([pyromaniac](https://github.com/pyromaniac))

## [0.7.2](https://github.com/BookingSync/operations/tree/v0.7.2)

### Added

- Allow referencing and arbitrary model attrbiute from form object attribute with `model_name: "Post#title"` [\#50](https://github.com/BookingSync/operations/pull/50) ([pyromaniac](https://github.com/pyromaniac))
- Allow passing multiple `hydrators:` to Operations::Form [\#49](https://github.com/BookingSync/operations/pull/49) ([pyromaniac](https://github.com/pyromaniac))

### Improvements

- Change default form hydration behavior - it is now deep merging params after hydration, so no need to do it in the hydrator. Controlled with `hydration_merge_params:` option. [\#49](https://github.com/BookingSync/operations/pull/49) ([pyromaniac](https://github.com/pyromaniac))

## [0.7.1](https://github.com/BookingSync/operations/tree/v0.7.1)

### Added

- Added `persisted:` option to the new forms definition. [\#48](https://github.com/BookingSync/operations/pull/48) ([pyromaniac](https://github.com/pyromaniac))

## [0.7.0](https://github.com/BookingSync/operations/tree/v0.7.0)

### Added

- Implement new forms system detaching it from operations. Please check [UPGRADING_FORMS.md](UPGRADING_FORMS.md) for more details. [\#47](https://github.com/BookingSync/operations/pull/47) ([pyromaniac](https://github.com/pyromaniac))

### Improvements

- Better inspect for all the opjects [\#45](https://github.com/BookingSync/operations/pull/45) ([pyromaniac](https://github.com/pyromaniac))
- Use #to_hash instead of #as_json [\#44](https://github.com/BookingSync/operations/pull/44) ([pyromaniac](https://github.com/pyromaniac))

### Fixes

- In some cases, `Operation::Command#form_class` was evaluated before `form_base` was evaluated [\#41](https://github.com/BookingSync/operations/pull/41) ([pyromaniac](https://github.com/pyromaniac))

## [0.6.3](https://github.com/BookingSync/operations/tree/v0.6.3)

### Added

- Support Rails 7.1 [\#40](https://github.com/BookingSync/operations/pull/40) ([pyromaniac](https://github.com/pyromaniac))
- Include `Dry::Monads[:result]` in Policies, Preconditions and Callbacks [\#39](https://github.com/BookingSync/operations/pull/39) ([ston1x](https://github.com/ston1x))
- Add `callback` method to `Operations::Convenience` [\#37](https://github.com/BookingSync/operations/pull/37) ([pyromaniac](https://github.com/pyromaniac))
- Ability to access operation result in callbacks [\#36](https://github.com/BookingSync/operations/pull/36) ([pyromaniac](https://github.com/pyromaniac))
- Introduce Command#merge [\#34](https://github.com/BookingSync/operations/pull/34) ([pyromaniac](https://github.com/pyromaniac))
