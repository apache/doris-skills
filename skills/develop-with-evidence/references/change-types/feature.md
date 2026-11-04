# New features and APIs: take expectations from the contract

Write the requirement as "given a condition, when an action is taken, then a result is observed", covering the normal path and the meaningful failure behaviors this change introduces. Expected values come from the requirement, a protocol, an existing contract, or an independent calculation, never from a copy of the new implementation.

Check the places that really need wiring in: entry points, registration, routing, config defaults, serialization and deserialization, privileges, documentation, and examples. Change only what actually applies. For a new feature, there is no need to manufacture a failure from "the old version doesn't have this interface"; verifying the new promises and compatibility with the existing behavior is enough.
