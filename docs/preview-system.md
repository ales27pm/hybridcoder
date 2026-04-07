# Preview System

The previous local sandbox approach is not a faithful React Native preview system.

## Why

React Native and Expo projects depend on:

- navigation wiring
- asset resolution
- package expectations
- workspace structure
- preview-aware validation

## Planned stages

1. Validation and diagnostics
2. Structural preview
3. Stronger runtime bridge

## Documentation rule

Until a true runtime path exists, preview should be documented as validation, diagnostics, and structural preview — not as a full React Native runtime.
